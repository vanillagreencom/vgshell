-- VGS notifications: an app's own notification sound held silent from its
-- first sample by routing only held streams to the private mute output.
-- The shell writes subject 0, `hold`, on `vgs-notification-sounds`:
-- { pid, apps, roles, streams, released }. All names and serials are strings.
-- apps/roles admit NEW nodes; streams is the shell's exact held set and
-- released exempts known nodes, even while their app remains in apps.
-- A new rule-held node stays held until the shell adopts or releases it.
-- The lease ends with the shell's persistent pw-cli client. No stream Props
-- or target metadata are changed, so app volume and mute memory stay intact.

local args = ...
args = args and args:parse(1) or {}
local version = args["version"]
local log = Log.open_topic("s-vgs-notification-sounds")
local lutils = require("linking-utils")
local NAME = "vgs-notification-sounds"
local SINK = "vgs-notification-mute-hold"
local hold = nil
-- object.serial -> { pid, origin, id }: bounded by live output streams.
local held = {}
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
  local result = { pid = tostring(pid) }
  for _, key in ipairs({ "apps", "roles", "streams", "released" }) do
    result[key] = set_of(parsed[key])
    if result[key] == nil then return nil, key end
  end
  for serial in pairs(result.streams) do
    if result.released[serial] then return nil, "held-and-released" end
  end
  return result
end

local clients = ObjectManager { Interest { type = "client" } }
local nodes = ObjectManager {
  Interest { type = "node", Constraint { "media.class", "=", "Stream/Output/Audio", type = "pw-global" } },
}
local metadata = ImplMetadata(NAME)

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

local function publish()
  local serials = {}
  for serial in pairs(held) do table.insert(serials, serial) end
  table.sort(serials)
  metadata:set(0, "held", "Spa:String:JSON", Json.Array(serials):to_string())
end

local function adopt_exact()
  if hold ~= nil and holder_present(hold.pid) then
    for node in nodes:iterate() do
      local serial = node.properties["object.serial"]
      if hold.streams[serial] then held[serial] = { pid = hold.pid, origin = "shell", id = node.id } end
    end
  end
  publish()
end

-- Adapter properties follow WirePlumber 0.5.18's fallback-sink.lua.
-- Node creates it in the daemon through the supported remote factory API. Keep it for the rule's life: a new stream's first
-- select-target event must find an already registered sink. The rule's
-- teardown destroys this owned node; state-stream.lua skips its Props.
local sink = Node("adapter", {
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
sink:activate(Feature.Proxy.BOUND)

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

SimpleEventHook {
  name = "node/vgs-notification-sounds",
  after = { "node/restore-stream" },
  before = { "node/create-item" },
  interests = { EventInterest {
    Constraint { "event.type", "=", "node-added" },
    Constraint { "media.class", "=", "Stream/Output/Audio" },
  } },
  execute = function(event)
    if hold == nil or not holder_present(hold.pid) then return end
    local node = event:get_subject()
    local serial = node.properties["object.serial"]
    if hold.released[serial] then return end
    if hold.streams[serial] or matches(node.properties) then
      held[serial] = { pid = hold.pid, origin = hold.streams[serial] and "shell" or "rule", id = node.id }
      publish()
    end
  end,
}:register()

SimpleEventHook {
  name = "linking/vgs-notification-sounds",
  before = { "linking/find-defined-target" },
  interests = { EventInterest { Constraint { "event.type", "=", "select-target" } } },
  execute = function(event)
    local _, om, _, props = lutils:unwrap_select_target_event(event)
    local entry = held[props["object.serial"]]
    if entry == nil or hold == nil or entry.pid ~= hold.pid or not holder_present(hold.pid) then return end
    local target = om:lookup { type = "SiLinkable", Constraint { "node.id", "=", tostring(sink["bound-id"]) } }
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
      event:set_data("target", om:lookup { type = "SiLinkable", Constraint { "node.id", "=", tostring(sink["bound-id"]) } })
    elseif target ~= nil and target.properties["node.id"] == tostring(sink["bound-id"]) then
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
      if entry.id == id then held[serial] = nil end
    end
    publish()
  end,
}:register()

local function clear()
  hold = nil
  held = {}
  publish()
end

clients:connect("object-removed", function(_, client)
  local pid = client.properties["pipewire.sec.pid"]
  if pid == nil then return end
  if hold ~= nil and hold.pid == pid then
    clear()
    metadata:set(0, "hold", nil, nil)
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
    EventInterest { Constraint { "event.type", "=", "metadata-changed" }, Constraint { "metadata.name", "=", NAME } },
    EventInterest { Constraint { "event.type", "=", "client-removed" } },
  },
  execute = function(event) event:get_source():call("schedule-rescan", "linking") end,
}:register()

metadata:activate(Features.ALL, function(m, error)
  if error then log:warning("metadata=failed " .. tostring(error)); return end
  m:connect("changed", function(_, subject, key, _, value)
    if subject ~= 0 or key ~= "hold" then return end
    if value == nil then clear(); return end
    local parsed, reason = parse_hold(value)
    if parsed ~= nil and gone_index(parsed.pid) ~= nil then parsed, reason = nil, "holder-gone pid=" .. parsed.pid end
    if parsed == nil then
      log:warning("hold refused: reason=" .. reason)
      clear()
      m:set(0, "hold", nil, nil)
      return
    end
    for serial, entry in pairs(held) do
      if entry.pid ~= parsed.pid or parsed.released[serial] or (entry.origin == "shell" and not parsed.streams[serial]) then held[serial] = nil end
    end
    hold = parsed
    adopt_exact()
  end)
  m:set(0, "version", "Spa:String", tostring(version))
  publish()
end)
clients:activate()
nodes:activate()
