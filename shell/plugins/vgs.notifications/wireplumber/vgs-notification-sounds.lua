-- VGS notifications: an app's own notification sound held silent from its
-- first sample while Do Not Disturb is on or Sound is off.
--
-- The notifications plugin loads this into WirePlumber through its own
-- configuration fragment (SoundRule.qml) and drives it through the
-- metadata object this script owns, `vgs-notification-sounds`:
--   subject 0, `version`: the version this script was loaded with, its
--     component argument, which the shell compares with its own.
--   subject 0, `hold`: written by the shell while mute is on (AppSounds.qml),
--     JSON { "pid": N, "apps": [names], "roles": [media.role values] },
--     names and roles in lower case.
-- The hold counts only while a PipeWire client whose pipewire.sec.pid is
-- N exists: the shell's persistent pw-cli writer, which dies with the
-- shell's mute. When that client goes, the hold is cleared and every
-- stream this script still holds is lifted. A hold that lands after its
-- client went, from a write still under way, is refused until a client
-- with that pid comes again. With no counted hold this script changes
-- nothing.
--
-- A new output stream that the hold matches gets softMute before
-- WirePlumber links it, so not one sample reaches a sink. softMute, not
-- mute: WirePlumber's stream state stores a stream's mute and volumes for
-- the app's later streams and never its softMute (state-stream.lua). The
-- hook runs after node/restore-stream, since any write of a stream's mute
-- or volumes lifts its softMute, and before node/create-item, which makes
-- the item the linking policy links.

local args = ...
args = args and args:parse(1) or {}
local version = args["version"]

log = Log.open_topic("s-vgs-notification-sounds")

local cutils = require("common-utils")

local NAME = "vgs-notification-sounds"

-- The counted hold's pid as PipeWire prints it, and its apps and roles
-- as sets, or nil.
local hold = nil
-- node id -> { node, pid }: the streams this script holds, and the pid of
-- the hold that held each.
local held = {}
-- The pids of clients that went, newest last, at most GONE_MAX: a hold
-- naming one is refused. A hold write lands within milliseconds of its
-- holder's end, while GONE_MAX clients would have to end in between.
local gone = {}
local GONE_MAX = 64

local function gone_index(pid)
  for i, p in ipairs(gone) do
    if p == pid then
      return i
    end
  end
  return nil
end

local function set_of(list)
  local set = {}
  if type(list) ~= "table" then
    return nil
  end
  for _, item in ipairs(list) do
    if type(item) ~= "string" then
      return nil
    end
    set[item] = true
  end
  return set
end

-- The hold VALUE names, or nil with the reason it is refused.
local function parse_hold(value)
  local json = Json.Raw(value)
  if not json:is_object() then
    return nil, "not-object"
  end
  local parsed = json:parse(2)
  local pid = math.tointeger(parsed.pid)
  if pid == nil or pid <= 0 then
    return nil, "pid"
  end
  local apps, roles = set_of(parsed.apps), set_of(parsed.roles)
  if apps == nil then
    return nil, "apps"
  end
  if roles == nil then
    return nil, "roles"
  end
  return { pid = tostring(pid), apps = apps, roles = roles }
end

clients_om = ObjectManager { Interest { type = "client" } }
-- ObjectManager includes pre-existing nodes (WirePlumber 0.5.18 Lua API,
-- lua_object_manager_api.html); mute can turn on after a stream opens.
nodes_om = ObjectManager {
  Interest {
    type = "node",
    Constraint { "media.class", "=", "Stream/Output/Audio", type = "pw-global" },
  },
}

local function holder_present(pid)
  for client in clients_om:iterate() do
    if client.properties["pipewire.sec.pid"] == pid then
      return true
    end
  end
  return false
end

-- Whether a stream with PROPS is one the hold names. The same match as
-- NotificationLogic.holdMatches in the plugin, which judges which streams
-- this script held: media.role, or application.name or
-- application.process.binary, each in lower case.
local function matches(props)
  local role = props["media.role"]
  if role ~= nil and hold.roles[role:lower()] then
    return true
  end
  for _, key in ipairs({ "application.name", "application.process.binary" }) do
    local name = props[key]
    if name ~= nil and hold.apps[name:lower()] then
      return true
    end
  end
  return false
end

-- The lift AppSounds.qml writes, in the same two writes: softMute false,
-- then the stream's own mute, which mixes it at its own volume and mute
-- again. softMute false alone, or both in one write, leaves it at full
-- volume whatever its own volume; the mute alone leaves softMute reading
-- true (measured on PipeWire 1.6.9 with a stream at channel volume 0.5,
-- VGS-1424).
local function lift(node)
  local mute = false
  for p in node:iterate_params("Props") do
    local props = cutils.parseParam(p, "Props")
    if props ~= nil and props.mute ~= nil then
      mute = props.mute
      break
    end
  end
  node:set_param("Props", Pod.Object { "Spa:Pod:Object:Param:Props", "Props", softMute = false })
  node:set_param("Props", Pod.Object { "Spa:Pod:Object:Param:Props", "Props", mute = mute })
end

metadata = ImplMetadata(NAME)

-- The holder with PID went: the streams held under it are lifted, and
-- the hold is cleared when it is that holder's.
local function release(pid)
  for id, entry in pairs(held) do
    if entry.pid == pid then
      lift(entry.node)
      held[id] = nil
    end
  end
  if hold ~= nil and hold.pid == pid then
    log:info("hold cleared: pid=" .. pid)
    hold = nil
    metadata:set(0, "hold", nil, nil)
  end
end

clients_om:connect("object-removed", function(_, client)
  local pid = client.properties["pipewire.sec.pid"]
  if pid ~= nil then
    release(pid)
    if gone_index(pid) == nil then
      table.insert(gone, pid)
      if #gone > GONE_MAX then
        table.remove(gone, 1)
      end
    end
  end
end)

clients_om:connect("object-added", function(_, client)
  local pid = client.properties["pipewire.sec.pid"]
  local i = pid ~= nil and gone_index(pid) or nil
  if i ~= nil then
    table.remove(gone, i)
  end
end)

SimpleEventHook {
  name = "node/vgs-notification-sounds",
  after = { "node/restore-stream" },
  before = { "node/create-item" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Stream/Output/Audio" },
    },
  },
  execute = function(event)
    if hold == nil or not holder_present(hold.pid) then
      return
    end
    local node = event:get_subject()
    if not matches(node.properties) then
      return
    end
    node:set_param("Props", Pod.Object { "Spa:Pod:Object:Param:Props", "Props", softMute = true })
    held[node.id] = { node = node, pid = hold.pid }
    log:info(node, "held: pid=" .. hold.pid)
  end,
}:register()

SimpleEventHook {
  name = "node/vgs-notification-sounds-removed",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-removed" },
      Constraint { "media.class", "=", "Stream/Output/Audio" },
    },
  },
  execute = function(event)
    held[event:get_subject().id] = nil
  end,
}:register()

metadata:activate(Features.ALL, function(m, e)
  if e then
    log:warning("metadata=failed " .. tostring(e))
    return
  end
  m:connect("changed", function(_, subject, key, _, value)
    if subject ~= 0 or key ~= "hold" then
      return
    end
    if value == nil then
      hold = nil
      return
    end
    local parsed, reason = parse_hold(value)
    if parsed ~= nil and gone_index(parsed.pid) ~= nil then
      parsed, reason = nil, "holder-gone pid=" .. parsed.pid
    end
    if parsed == nil then
      log:warning("hold refused: reason=" .. reason)
      hold = nil
      m:set(0, "hold", nil, nil)
      return
    end
    hold = parsed
    if holder_present(hold.pid) then
      for node in nodes_om:iterate() do
        -- An already-playing call is not a notification sound. A paused
        -- stream is held before its next chime, even if Notify is late.
        if node.properties["pulse.corked"] == "true" and matches(node.properties) then
          node:set_param("Props", Pod.Object { "Spa:Pod:Object:Param:Props", "Props", softMute = true })
          held[node.id] = { node = node, pid = hold.pid }
        end
      end
    end
    log:info("hold: pid=" .. parsed.pid)
  end)
  m:set(0, "version", "Spa:String", tostring(version))
end)

clients_om:activate()
nodes_om:activate()
