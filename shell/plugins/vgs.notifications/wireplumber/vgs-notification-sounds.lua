-- VGS notifications: an app's own notification sound held silent from its
-- first sample by routing only held streams to the private mute output.
-- The shell writes subject 0, `hold`, on daemon-owned `vgs-notification-hold`:
-- { pid, apps, roles, streams, released, deadlineMs }. Names/serials are strings.
-- apps/roles admit NEW nodes; streams is the shell's exact held set and
-- released exempts known nodes, even while their app remains in apps.
-- An unadopted rule-held node expires at the shell-provided deadline.
-- The lease ends with the shell's persistent pw-cli client. No stream Props
-- or target metadata are changed, so app volume and mute memory stay intact.

local args = ...
args = args and args:parse(1) or {}
local version = args["version"]
local log = Log.open_topic("s-vgs-notification-sounds")
local lutils = require("linking-utils")
local NAME = "vgs-notification-sounds"
local HOLD_NAME = "vgs-notification-hold"
local SINK = "vgs-notification-mute-hold"
local hold = nil
-- object.serial -> { pid, origin, id, deadline }: bounded by live output streams.
local held = {}
local sink = nil
local sink_bound = false
local gone = {}
local GONE_MAX = 64

local function gone_index(pid)
  for i, p in ipairs(gone) do
    if p == pid then return i end
  end
  return nil
end

local function set_of(list)
  if type(list) ~= "table" then return nil end
  local set = {}
  for _, item in ipairs(list) do
    if type(item) ~= "string" then return nil end
    set[item] = true
  end
  return set
end

local function parse_hold(value)
  local json = Json.Raw(value)
  if not json:is_object() then return nil, "not-object" end
  local parsed = json:parse(2)
  local pid = math.tointeger(parsed.pid)
  if pid == nil or pid <= 0 then return nil, "pid" end
  local deadline = math.tointeger(parsed.deadlineMs)
  if deadline == nil or deadline <= 0 or deadline > 2147483647 then return nil, "deadlineMs" end
  local result = { pid = tostring(pid), deadlineMs = deadline }
  for _, key in ipairs({ "apps", "roles", "streams", "released" }) do
    result[key] = set_of(parsed[key])
    if result[key] == nil then return nil, key end
  end
  for serial in pairs(result.streams) do
    if result.released[serial] then return nil, "held-and-released" end
  end
  return result
end

-- The component requires support.standard-event-source. Its ENABLED feature
-- follows installation of all initial object managers (WP 0.5.18
-- module-standard-event-source.c:382-427). Use that one prepared owner;
-- starting duplicate managers behind node admission can block its progress.
local source = Plugin.find("standard-event-source")
local clients = source:call("get-object-manager", "client")
local nodes = source:call("get-object-manager", "node")
local stores = source:call("get-object-manager", "metadata")
local metadata = ImplMetadata(NAME)
local store = nil
local metadata_ready = false
local readiness = "pending"
local waiting = {}

local function holder_present(pid)
  for client in clients:iterate() do
    if client.properties["pipewire.sec.pid"] == pid then return true end
  end
  return false
end

local function matches(props)
  local role = props["media.role"]
  if role ~= nil and hold.roles[role:lower()] then return true end
  for _, key in ipairs({ "application.name", "application.process.binary" }) do
    local name = props[key]
    if name ~= nil and hold.apps[name:lower()] then return true end
  end
  return false
end

-- The sink shares the held set's lifetime, not the installed rule's. A
-- remote Node needs request_destroy; dropping its Lua reference leaves it
-- in PipeWire. Activation is asynchronous, so a release before BOUND
-- destroys that node in its callback (WirePlumber Lua object/proxy API:
-- https://pipewire.pages.freedesktop.org/wireplumber/scripting/lua_api/lua_object_api.html
-- https://pipewire.pages.freedesktop.org/wireplumber/scripting/lua_api/lua_proxies_api.html).
local function sync_sink()
  if next(held) == nil then
    local previous = sink
    sink = nil
    if previous ~= nil and sink_bound then previous:request_destroy() end
    sink_bound = false
    return
  end
  if sink ~= nil then return end
  -- Adapter properties follow WirePlumber's fallback-sink.lua. No stream
  -- Props or target metadata changes; state-stream.lua skips this sink.
  sink = Node("adapter", {
    ["factory.name"] = "support.null-audio-sink",
    ["node.name"] = SINK,
    ["node.description"] = "VGS notification mute hold",
    ["media.class"] = "Audio/Sink",
    ["audio.rate"] = 48000,
    ["audio.channels"] = 2,
    ["audio.position"] = "FL,FR",
    ["node.virtual"] = true,
    ["priority.session"] = -1000,
    ["state.restore-props"] = false,
    ["state.restore-target"] = false,
  })
  sink:activate(Feature.Proxy.BOUND, function(node, error)
    if error then
      if sink == node then sink = nil end
      log:warning("sink=failed " .. tostring(error))
    elseif sink ~= node then
      node:request_destroy()
    else
      sink_bound = true
    end
  end)
end

local function publish()
  sync_sink()
  local serials = {}
  for serial in pairs(held) do table.insert(serials, serial) end
  table.sort(serials)
  metadata:set(0, "held", "Spa:String:JSON", Json.Array(serials):to_string())
end

local function cancel_deadline(entry)
  if entry.deadline ~= nil then entry.deadline:destroy(); entry.deadline = nil end
end

local function release(serial)
  local entry = held[serial]
  if entry ~= nil then cancel_deadline(entry); held[serial] = nil end
end

local function adopt_exact()
  if hold ~= nil and holder_present(hold.pid) then
    for node in nodes:iterate() do
      local serial = node.properties["object.serial"]
      if hold.streams[serial] then
        release(serial)
        held[serial] = { pid = hold.pid, origin = "shell", id = node.id }
      end
    end
  end
  publish()
end

-- Priority alone still wins when no other output exists. The supported
-- select-default-node event supplies available-nodes to all three stock
-- selectors (default-nodes/rescan.lua and README.rst, WirePlumber 0.5.18).
SimpleEventHook {
  name = "default-nodes/vgs-exclude-mute-hold",
  before = { "default-nodes/find-selected-default-node", "default-nodes/find-stored-default-node", "default-nodes/find-best-default-node" },
  interests = { EventInterest { Constraint { "event.type", "=", "select-default-node" } } },
  execute = function(event)
    local available = event:get_data("available-nodes")
    if available == nil then return end
    local filtered = {}
    for _, props in ipairs(available:parse()) do
      if props["node.name"] ~= SINK then table.insert(filtered, Json.Object(props)) end
    end
    event:set_data("available-nodes", Json.Array(filtered))
  end,
}:register()

AsyncEventHook {
  name = "node/vgs-notification-sounds",
  after = { "node/restore-stream" },
  before = { "node/create-item" },
  interests = { EventInterest {
    Constraint { "event.type", "=", "node-added" },
    Constraint { "media.class", "=", "Stream/Output/Audio" },
  } },
  steps = {
    start = { next = "admit", execute = function(_, transition)
      -- Only this rule's own metadata activation may still be pending; the
      -- required standard event source already prepared the client/store set.
      if readiness ~= "pending" then transition:advance() else table.insert(waiting, transition) end
    end },
    admit = { next = "none", execute = function(event, transition)
      if readiness == "ready" and hold ~= nil and holder_present(hold.pid) then
        local node = event:get_subject()
        local serial = node.properties["object.serial"]
        if not hold.released[serial] and (hold.streams[serial] or matches(node.properties)) then
          release(serial)
          local entry = { pid = hold.pid, origin = hold.streams[serial] and "shell" or "rule", id = node.id }
          held[serial] = entry
          if entry.origin == "rule" then
            local source = event:get_source()
            -- Core.timeout_add returns a cancellable GSource; false removes
            -- it after one dispatch (WP 0.5.18 node/suspend-node.lua).
            entry.deadline = Core.timeout_add(hold.deadlineMs, function()
              entry.deadline = nil
              if held[serial] == entry then
                held[serial] = nil
                publish()
                source:call("schedule-rescan", "linking")
              end
              return false
            end)
          end
          publish()
        end
      end
      transition:advance()
    end },
  },
}:register()

SimpleEventHook {
  name = "linking/vgs-notification-sounds",
  before = { "linking/find-defined-target" },
  interests = { EventInterest { Constraint { "event.type", "=", "select-target" } } },
  execute = function(event)
    local _, om, _, props = lutils:unwrap_select_target_event(event)
    local entry = held[props["object.serial"]]
    if entry == nil or hold == nil or entry.pid ~= hold.pid or not holder_present(hold.pid) then return end
    local target = sink ~= nil and sink_bound and om:lookup { type = "SiLinkable", Constraint { "node.id", "=", tostring(sink["bound-id"]) } } or nil
    if target == nil then
      -- Never send the held stream to a real output while the owned sink
      -- registers. Its session-item-added event schedules another rescan.
      event:stop_processing()
      return
    end
    event:set_data("target", target)
  end,
}:register()

-- Stock best-target can choose the only remaining sink, and a smart filter
-- can replace an earlier target. The last routing decision keeps the owned
-- sink exclusive to held serials (WirePlumber 0.5.18 linking/README.rst).
SimpleEventHook {
  name = "linking/vgs-isolate-mute-hold",
  after = { "linking/get-filter-from-target", "linking/find-best-target" },
  before = { "linking/prepare-link" },
  interests = { EventInterest { Constraint { "event.type", "=", "select-target" } } },
  execute = function(event)
    local _, om, _, props, _, target = lutils:unwrap_select_target_event(event)
    local entry = held[props["object.serial"]]
    if entry ~= nil and hold ~= nil and entry.pid == hold.pid and holder_present(hold.pid) then
      event:set_data("target", sink ~= nil and sink_bound and om:lookup { type = "SiLinkable", Constraint { "node.id", "=", tostring(sink["bound-id"]) } } or nil)
    elseif target ~= nil and target.properties["node.name"] == SINK then
      event:set_data("target", nil)
    end
  end,
}:register()

SimpleEventHook {
  name = "node/vgs-notification-sounds-removed",
  interests = { EventInterest {
    Constraint { "event.type", "=", "node-removed" },
    Constraint { "media.class", "=", "Stream/Output/Audio" },
  } },
  execute = function(event)
    -- WirePlumber 0.5.18's node/destroy-item also uses node.id here:
    -- removed proxies have no properties or bound-id, but keep this identity.
    local id = event:get_subject().id
    for serial, entry in pairs(held) do
      if entry.id == id then release(serial) end
    end
    publish()
  end,
}:register()

local function clear()
  hold = nil
  for serial in pairs(held) do release(serial) end
  publish()
end

clients:connect("object-removed", function(_, client)
  local pid = client.properties["pipewire.sec.pid"]
  if pid == nil then return end
  -- The pw-metadata publisher can leave before the persistent pw-cli
  -- holder is prepared. Only loss of that holder ends its pending lease;
  -- another client's removal must not erase the snapshot before adoption.
  if hold ~= nil and hold.pid == pid and not holder_present(hold.pid) then
    clear()
  end
  if gone_index(pid) == nil then
    table.insert(gone, pid)
    if #gone > GONE_MAX then table.remove(gone, 1) end
  end
end)
clients:connect("object-added", function(_, client)
  local pid = client.properties["pipewire.sec.pid"]
  local i = pid ~= nil and gone_index(pid) or nil
  if i ~= nil then table.remove(gone, i) end
  if hold ~= nil and hold.pid == pid then adopt_exact() end
end)

-- The metadata write and holder-removal callback run on this same main
-- loop. Rescan is queued after them, so release uses the reconciled set.
SimpleEventHook {
  name = "linking/vgs-notification-sounds-rescan",
  interests = {
    EventInterest { Constraint { "event.type", "=", "metadata-changed" }, Constraint { "metadata.name", "=", HOLD_NAME } },
    EventInterest { Constraint { "event.type", "=", "client-removed" } },
  },
  execute = function(event) event:get_source():call("schedule-rescan", "linking") end,
}:register()

-- All hold changes, including the startup read, use this parser and lease.
local function read_hold(value)
  if value == nil then clear(); return end
  local parsed, reason = parse_hold(value)
  if parsed ~= nil and gone_index(parsed.pid) ~= nil then parsed, reason = nil, "holder-gone pid=" .. parsed.pid end
  if parsed == nil then
    log:warning("hold refused: reason=" .. reason)
    clear()
    return
  end
  for serial, entry in pairs(held) do
    if entry.pid ~= parsed.pid or parsed.released[serial] or (entry.origin == "shell" and not parsed.streams[serial]) then release(serial) end
  end
  hold = parsed
  adopt_exact()
end

local function finish_readiness(state)
  readiness = state
  if metadata_ready then
    metadata:set(0, "status", "Spa:String", state)
    -- Version means admission is ready, not merely that metadata activated.
    metadata:set(0, "version", "Spa:String", state == "ready" and tostring(version) or nil)
  end
  local pending = waiting
  waiting = {}
  for _, transition in ipairs(pending) do transition:advance() end
end

local function start()
  if not metadata_ready then return end
  if store == nil then
    clear()
    finish_readiness("hold-store-absent")
    return
  end
  -- Read the daemon's existing value before deciding any queued node.
  read_hold(store ~= nil and store:find(0, "hold") or nil)
  finish_readiness("ready")
end

local function bind_store()
  local found = stores:lookup { Constraint { "metadata.name", "=", HOLD_NAME } }
  if found ~= store then
    store = found
    if store ~= nil then
      store:connect("changed", function(object, subject, key, _, value)
        if object == store and readiness == "ready" and subject == 0 and key == "hold" then read_hold(value) end
      end)
    end
  end
  start()
end

stores:connect("object-added", bind_store)
stores:connect("object-removed", bind_store)
bind_store()
metadata:activate(Features.ALL, function(_, error)
  if error then
    log:warning("metadata=failed " .. tostring(error))
    finish_readiness("metadata-failed")
    return
  end
  metadata_ready = true
  start()
end)
