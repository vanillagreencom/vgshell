-- The vgs theme for WezTerm, run by the line vgshell theme apply keeps first in
-- wezterm.lua. WezTerm has no include directive, so the theme wraps
-- wezterm.config_builder: a config it builds starts on the vgs colour
-- scheme, and every setting wezterm.lua makes on it afterwards overrides it.
-- WezTerm watches the file it loaded, so the hook touches it; a reload needs automatically_reload_config on, its default.
local wezterm = require 'wezterm'
local build = wezterm.config_builder
if build then
  function wezterm.config_builder()
    local config = build()
    config.color_schemes = {
      vgs = {
        foreground = '#@{palette.foreground}',
        background = '#@{palette.background}',
        cursor_bg = '#@{palette.foreground}',
        cursor_fg = '#@{palette.background}',
        cursor_border = '#@{palette.foreground}',
        selection_fg = '#@{palette.foreground}',
        selection_bg = '#@{color.borderStrong}',
        copy_mode_active_highlight_bg = { Color = '#@{color.accent}' },
        copy_mode_active_highlight_fg = { Color = '#@{color.onAccent}' },
        copy_mode_inactive_highlight_bg = { Color = '#@{color.info}' },
        copy_mode_inactive_highlight_fg = { Color = '#@{color.onInfo}' },
        quick_select_label_bg = { Color = '#@{color.accent}' },
        quick_select_label_fg = { Color = '#@{color.onAccent}' },
        quick_select_match_bg = { Color = '#@{color.info}' },
        quick_select_match_fg = { Color = '#@{color.onInfo}' },
        ansi = { '#@{terminal.color0}', '#@{terminal.color1}', '#@{terminal.color2}', '#@{terminal.color3}', '#@{terminal.color4}', '#@{terminal.color5}', '#@{terminal.color6}', '#@{terminal.color7}' },
        brights = { '#@{terminal.color8}', '#@{terminal.color9}', '#@{terminal.color10}', '#@{terminal.color11}', '#@{terminal.color12}', '#@{terminal.color13}', '#@{terminal.color14}', '#@{terminal.color15}' },
      },
    }
    config.color_scheme = 'vgs'
    -- WezTerm reads tab styling from config.colors:
    -- https://wezterm.org/config/appearance.html#tab-bar-appearance
    config.colors = {
      tab_bar = {
        background = '#@{color.background}',
        active_tab = { bg_color = '#@{color.accent}', fg_color = '#@{color.onAccent}' },
        inactive_tab = { bg_color = '#@{color.background}', fg_color = '#@{color.textMuted}' },
        inactive_tab_hover = { bg_color = '#@{color.surfaceRaised}', fg_color = '#@{color.text}' },
        new_tab = { bg_color = '#@{color.background}', fg_color = '#@{color.textMuted}' },
        new_tab_hover = { bg_color = '#@{color.surfaceRaised}', fg_color = '#@{color.text}' },
        inactive_tab_edge = '#@{color.textMuted}',
        inactive_tab_edge_hover = '#@{color.text}',
      },
    }
    -- The default fancy tab bar reads its strip from window_frame:
    -- https://wezterm.org/config/appearance.html#native-fancy-tab-bar-appearance
    config.window_frame = {
      active_titlebar_bg = '#@{color.background}', inactive_titlebar_bg = '#@{color.background}',
      active_titlebar_fg = '#@{color.text}', inactive_titlebar_fg = '#@{color.textMuted}',
    }
    return config
  end
end
