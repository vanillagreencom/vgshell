-- The VGS login screen's compositor. greetd runs Hyprland with this file as
-- the greeter account, and Hyprland runs the login screen, shell/greeter.qml
-- under VGS_GREETER_ROOT, the install tree the greetd configuration names.
-- When the login screen ends, after it hands greetd a session or fails,
-- Hyprland exits, so greetd can start the session or the greeter again.
-- No logo, no splash and no animations, as Omarchy's greeter compositor.

-- The system keyboard layout, as Omarchy's default/sddm/hyprland.lua reads
-- it: the XKB keys of /etc/vconsole.conf, which `localectl
-- set-x11-keymap` writes on systemd systems, else `us`. A password is
-- typed here before any user's own configuration loads.
local function read_vconsole()
    local values = {}
    local file = io.open("/etc/vconsole.conf", "r")
    if not file then
        return values
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and value then
            value = value:gsub("%s+#.*$", "")
            value = value:gsub('^"(.*)"$', "%1")
            value = value:gsub("^'(.*)'$", "%1")
            values[key] = value
        end
    end
    file:close()
    return values
end

-- Layouts that cannot type Latin letters, Omarchy's list: a greeter on one
-- of them puts `us` first, Left Alt + Right Alt switching between the two,
-- since an account name and most passwords need Latin letters.
local non_latin_layouts =
    " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "

local vconsole = read_vconsole()
local function value_of(key)
    local value = vconsole[key]
    if value == nil or value == "" then
        return nil
    end
    return value
end
local kb_layout = value_of("XKBLAYOUT") or "us"
local kb_variant = value_of("XKBVARIANT") or ""
local kb_model = value_of("XKBMODEL") or ""
local kb_options = value_of("XKBOPTIONS") or ""

if non_latin_layouts:find(" " .. kb_layout:match("^[^,]*") .. " ", 1, true) then
    kb_layout = "us," .. kb_layout
    kb_variant = "," .. kb_variant
    kb_options = kb_options == "" and "grp:alts_toggle" or kb_options .. ",grp:alts_toggle"
end

hl.config({
    input = { kb_layout = kb_layout, kb_variant = kb_variant, kb_model = kb_model, kb_options = kb_options },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0 },
    animations = { enabled = false },
})
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -p \"$VGS_GREETER_ROOT/shell/greeter.qml\"; hyprctl dispatch 'hl.dsp.exit()'")
end)
