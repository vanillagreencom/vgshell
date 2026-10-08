-- The vgs theme for Neovim, rendered by vgshell theme apply. Neovim sources
-- nvim/plugin/vgs-theme.lua at startup; the colours are set once Neovim has
-- started, after any colorscheme a plugin loads at startup.
-- Neovim's terminal background detection can reset highlights. Set the
-- declared mode first (Neovim runtime/doc/options.txt, 'background').
vim.o.background = "@{scheme.mode}"

local function apply()
  vim.cmd("highlight clear")
  vim.g.colors_name = "vgs"
  local hl = function(group, spec) vim.api.nvim_set_hl(0, group, spec) end
  hl("Normal", { fg = "#@{color.text}", bg = "#@{color.background}" })
  -- Inactive windows use NormalNC, so they must take the same fill as
  -- Normal (Neovim runtime/doc/syntax.txt, NormalNC).
  hl("NormalNC", { fg = "#@{color.text}", bg = "#@{color.background}" })
  hl("NormalFloat", { fg = "#@{color.text}", bg = "#@{color.surfaceRaised}" })
  hl("FloatBorder", { fg = "#@{color.borderStrong}", bg = "#@{color.surfaceRaised}" })
  hl("WinSeparator", { fg = "#@{color.border}" })
  hl("Cursor", { fg = "#@{color.onAccent}", bg = "#@{color.accent}" })
  hl("CursorLine", { bg = "#@{color.surfaceRaised}" })
  hl("ColorColumn", { bg = "#@{color.surface}" })
  hl("LineNr", { fg = "#@{color.textFaint}" })
  hl("CursorLineNr", { fg = "#@{color.text}", bold = true })
  hl("SignColumn", { bg = "#@{color.background}" })
  hl("Visual", { bg = "#@{color.borderStrong}" })
  hl("Search", { fg = "#@{contrast(mix({color.background}, {palette.warning}, 0.18))}", bg = "#@{mix({color.background}, {palette.warning}, 0.18)}" })
  hl("CurSearch", { fg = "#@{contrast({color.info})}", bg = "#@{color.info}", bold = true, underline = true })
  hl("IncSearch", { link = "CurSearch" })
  hl("MatchParen", { fg = "#@{color.accent}", bold = true })
  hl("StatusLine", { fg = "#@{color.text}", bg = "#@{color.surfaceRaised}" })
  hl("StatusLineNC", { fg = "#@{color.textMuted}", bg = "#@{color.surface}" })
  hl("TabLine", { fg = "#@{color.textMuted}", bg = "#@{color.surface}" })
  hl("TabLineSel", { fg = "#@{color.text}", bg = "#@{color.background}" })
  hl("TabLineFill", { bg = "#@{color.surface}" })
  hl("Pmenu", { fg = "#@{color.text}", bg = "#@{color.surfaceRaised}" })
  hl("PmenuSel", { fg = "#@{color.onAccent}", bg = "#@{color.accent}" })
  hl("NonText", { fg = "#@{color.textDisabled}" })
  hl("Comment", { fg = "#@{color.textFaint}", italic = true })
  hl("Constant", { fg = "#@{terminal.color6}" })
  hl("String", { fg = "#@{terminal.color2}" })
  hl("Identifier", { fg = "#@{color.text}" })
  hl("Function", { fg = "#@{terminal.color4}" })
  hl("Statement", { fg = "#@{terminal.color5}" })
  hl("Type", { fg = "#@{terminal.color3}" })
  hl("PreProc", { fg = "#@{terminal.color1}" })
  hl("Special", { fg = "#@{color.accent}" })
  hl("Error", { fg = "#@{color.danger}" })
  hl("ErrorMsg", { fg = "#@{color.danger}" })
  hl("WarningMsg", { fg = "#@{color.warning}" })
  hl("DiagnosticError", { fg = "#@{color.danger}" })
  hl("DiagnosticWarn", { fg = "#@{color.warning}" })
  hl("DiagnosticInfo", { fg = "#@{color.info}" })
  hl("DiagnosticHint", { fg = "#@{color.success}" })
  hl("DiffAdd", { fg = "#@{contrast(mix({color.background}, {palette.success}, 0.18))}", bg = "#@{mix({color.background}, {palette.success}, 0.18)}" })
  hl("DiffChange", { fg = "#@{contrast(mix({color.background}, {palette.warning}, 0.22))}", bg = "#@{mix({color.background}, {palette.warning}, 0.22)}", italic = true })
  hl("DiffDelete", { fg = "#@{contrast(mix({color.background}, {palette.danger}, 0.18))}", bg = "#@{mix({color.background}, {palette.danger}, 0.18)}", bold = true })
  hl("DiffText", { fg = "#@{contrast(mix({color.background}, {palette.warning}, 0.35))}", bg = "#@{mix({color.background}, {palette.warning}, 0.35)}", bold = true, underline = true })
  hl("Directory", { fg = "#@{color.info}" })
  hl("Title", { fg = "#@{color.success}", bold = true })
  hl("Folded", { fg = "#@{color.textMuted}", bg = "#@{color.surface}", italic = true })
  hl("FoldColumn", { fg = "#@{color.textMuted}", bg = "#@{color.background}" })
  hl("Todo", { fg = "#@{color.warning}", bold = true })
  hl("MoreMsg", { fg = "#@{color.info}" })
  hl("Question", { fg = "#@{color.info}", bold = true })
  hl("ModeMsg", { fg = "#@{color.success}", bold = true })
  hl("OkMsg", { fg = "#@{color.success}" })
  hl("PmenuSbar", { bg = "#@{color.surface}" })
  hl("PmenuThumb", { bg = "#@{color.textMuted}" })
  hl("QuickFixLine", { fg = "#@{contrast(mix({color.background}, {palette.info}, 0.18))}", bg = "#@{mix({color.background}, {palette.info}, 0.18)}", bold = true })
  hl("WinBar", { fg = "#@{color.text}", bg = "#@{color.surface}", bold = true })
  hl("WinBarNC", { fg = "#@{color.textMuted}", bg = "#@{color.surface}" })
  hl("Conceal", { fg = "#@{color.textMuted}" })
  hl("Operator", { fg = "#@{color.text}" })
  hl("Delimiter", { fg = "#@{color.text}" })
  hl("Underlined", { fg = "#@{color.info}", underline = true })
  hl("Bold", { fg = "#@{color.text}", bold = true })
  hl("Italic", { fg = "#@{color.text}", italic = true })
  hl("BoldItalic", { fg = "#@{color.text}", bold = true, italic = true })
  hl("Strikethrough", { fg = "#@{color.text}", strikethrough = true })
  hl("Ignore", { fg = "#@{color.background}" })
  hl("FloatShadow", { bg = "#@{color.surfaceSunken}", blend = 80 })
  hl("FloatShadowThrough", { bg = "#@{color.surfaceSunken}", blend = 100 })
  hl("PmenuMatch", { fg = "#@{color.text}", bg = "#@{color.surfaceRaised}", bold = true })
  hl("PmenuMatchSel", { fg = "#@{color.onAccent}", bg = "#@{color.accent}", bold = true })
  hl("DiagnosticOk", { fg = "#@{color.success}" })
  hl("DiagnosticDeprecated", { fg = "#@{color.textMuted}", strikethrough = true })
  for _, role in ipairs({
    { "Error", "#@{color.danger}" }, { "Warn", "#@{color.warning}" },
    { "Info", "#@{color.info}" }, { "Hint", "#@{color.success}" }, { "Ok", "#@{color.success}" },
  }) do
    hl("DiagnosticUnderline" .. role[1], { sp = role[2], underline = true })
  end
  hl("SpellBad", { sp = "#@{color.danger}", undercurl = true })
  hl("SpellCap", { sp = "#@{color.warning}", undercurl = true })
  hl("SpellLocal", { sp = "#@{color.success}", undercurl = true })
  hl("SpellRare", { sp = "#@{color.info}", undercurl = true })
  -- highlight clear restores builtin links and colours. Link every audited
  -- family to a theme-owned group (Neovim runtime/doc/syntax.txt, hi-link).
  local links = {
    Cursor = { "CursorIM", "lCursor", "TermCursor" },
    CursorLine = { "CursorColumn" }, FoldColumn = { "CursorLineFold" },
    SignColumn = { "CursorLineSign" }, CurSearch = { "MCursor" }, Visual = { "MCursorVisual", "VisualNOS", "SnippetTabstop", "SnippetTabstopActive" },
    Search = { "Substitute" }, DiffText = { "DiffTextAdd" },
    Title = { "FloatTitle", "FloatFooter", "@markup.heading", "@markup.heading.1", "@markup.heading.2", "@markup.heading.3", "@markup.heading.4", "@markup.heading.5", "@markup.heading.6" },
    StatusLine = { "MsgSeparator", "StatusLineTerm", "User1", "User9" }, StatusLineNC = { "StatusLineTermNC" },
    Normal = { "MsgArea", "StdoutMsg", "ComplMatchIns", "@variable", "@variable.member", "@variable.parameter" },
    Pmenu = { "PmenuExtra", "PmenuKind", "Menu", "Tooltip" }, PmenuSel = { "PmenuExtraSel", "PmenuKindSel", "WildMenu" },
    FloatBorder = { "PmenuBorder" }, FloatShadow = { "PmenuShadow" }, FloatShadowThrough = { "PmenuShadowThrough" },
    PmenuThumb = { "Scrollbar" }, NonText = { "EndOfBuffer", "Whitespace", "ComplHint" }, MoreMsg = { "ComplHintMore" },
    ErrorMsg = { "StderrMsg" }, LineNr = { "LineNrAbove", "LineNrBelow" }, Conceal = { "conceal" },
    Constant = { "Boolean", "Character", "Number", "Float", "@boolean", "@character", "@number", "@number.float", "@constant" },
    Statement = { "Conditional", "Repeat", "Label", "Keyword", "Exception", "@keyword", "@keyword.conditional", "@keyword.conditional.ternary", "@keyword.coroutine", "@keyword.debug", "@keyword.exception", "@keyword.function", "@keyword.modifier", "@keyword.operator", "@keyword.repeat", "@keyword.return", "@keyword.type", "@label" },
    PreProc = { "Include", "Define", "Macro", "PreCondit", "@attribute", "@constant.macro", "@function.macro", "@keyword.directive", "@keyword.directive.define", "@keyword.import" },
    Type = { "StorageClass", "Structure", "Typedef", "@module", "@type", "@type.definition" },
    Special = { "Tag", "SpecialChar", "SpecialComment", "SpecialKey", "Debug", "@attribute.builtin", "@character.special", "@constant.builtin", "@constructor", "@function.builtin", "@module.builtin", "@punctuation.special", "@string.escape", "@string.regexp", "@string.special", "@string.special.path", "@string.special.symbol", "@tag", "@tag.builtin", "@type.builtin", "@variable.builtin", "@variable.parameter.builtin", "@markup.list", "@markup.math" },
    String = { "Regexp", "@string", "@string.documentation", "@markup.raw", "@markup.raw.block" },
    Identifier = { "@property", "@tag.attribute" }, Function = { "@function", "@function.call", "@function.method", "@function.method.call" },
    Operator = { "@operator" }, Delimiter = { "@punctuation.bracket", "@punctuation.delimiter", "@tag.delimiter" },
    Comment = { "Dimmed", "DiagnosticUnnecessary", "@comment", "@comment.documentation", "@markup.quote" },
    DiagnosticError = { "@comment.error" }, DiagnosticWarn = { "@comment.warning" }, DiagnosticInfo = { "@comment.note" }, Todo = { "@comment.todo", "@markup.list.unchecked" },
    Bold = { "@markup.strong" }, Italic = { "@markup.italic" }, Strikethrough = { "@markup.strikethrough" },
    Underlined = { "@markup.link", "@markup.link.label", "@markup.link.url", "@markup.underline", "@string.special.url" },
    DiagnosticOk = { "@markup.list.checked" }, DiagnosticHint = { "PreInsert" },
    DiffAdd = { "@diff.plus" }, DiffDelete = { "@diff.minus" }, DiffChange = { "@diff.delta" },
  }
  for target, groups in pairs(links) do
    for _, group in ipairs(groups) do hl(group, { link = target }) end
  end
  for _, role in ipairs({ "Error", "Warn", "Info", "Hint", "Ok" }) do
    for _, family in ipairs({ "Floating", "Sign", "VirtualText", "VirtualLines" }) do
      hl("Diagnostic" .. family .. role, { link = "Diagnostic" .. role })
    end
  end
  local slots = {
    "#@{terminal.color0}", "#@{terminal.color1}", "#@{terminal.color2}", "#@{terminal.color3}",
    "#@{terminal.color4}", "#@{terminal.color5}", "#@{terminal.color6}", "#@{terminal.color7}",
    "#@{terminal.color8}", "#@{terminal.color9}", "#@{terminal.color10}", "#@{terminal.color11}",
    "#@{terminal.color12}", "#@{terminal.color13}", "#@{terminal.color14}", "#@{terminal.color15}",
  }
  for i, slot in ipairs(slots) do vim.g["terminal_color_" .. (i - 1)] = slot end
end

if vim.v.vim_did_enter == 1 then
  apply()
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = apply })
end
return {}
