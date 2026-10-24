-- Из темы (палитра + синтаксис) — все группы подсветки: редактор, синтаксис (старый, treesitter, LSP),
-- плагины (snacks, blink, which-key, gitsigns, neotest, dap, flash…). Чего нет в теме — выводится из палитры.
local color = require("own.theme.color")

local M = {}

--- Палитра с выведенными значениями. Обязательны только bg и fg.
function M.palette(t)
  local p = vim.deepcopy(t.palette or {})
  local bg, fg = p.bg or "#1a1b26", p.fg or "#c0caf5"
  p.bg, p.fg = bg, fg
  local light = t.type == "light" or (t.type == nil and color.luminance(bg) > 0.5)
  p.red = p.red or (light and "#d20f39" or "#f7768e")
  p.orange = p.orange or (light and "#fe640b" or "#ff9e64")
  p.yellow = p.yellow or (light and "#df8e1d" or "#e0af68")
  p.green = p.green or (light and "#40a02b" or "#9ece6a")
  p.cyan = p.cyan or (light and "#179299" or "#7dcfff")
  p.blue = p.blue or (light and "#1e66f5" or "#7aa2f7")
  p.purple = p.purple or (light and "#8839ef" or "#bb9af7")
  p.pink = p.pink or (light and "#ea76cb" or "#f5a8d0")
  p.accent = p.accent or p.purple
  p.bg_alt = p.bg_alt or color.blend(fg, bg, 0.04)
  p.bg_highlight = p.bg_highlight or color.blend(fg, bg, 0.07)
  p.bg_visual = p.bg_visual or color.blend(p.accent, bg, 0.25)
  p.border = p.border or color.blend(fg, bg, 0.22)
  p.fg_dim = p.fg_dim or color.blend(fg, bg, 0.78)
  p.fg_muted = p.fg_muted or color.blend(fg, bg, 0.45)
  p.diff_add = p.diff_add or color.blend(p.green, bg, 0.15)
  p.diff_delete = p.diff_delete or color.blend(p.red, bg, 0.15)
  p.diff_change = p.diff_change or color.blend(p.blue, bg, 0.12)
  p.diff_text = p.diff_text or color.blend(p.blue, bg, 0.3)
  return p, light
end

-- роли синтаксиса по умолчанию (значение — имя цвета палитры или {fg, bold, italic…})
local SYNTAX = {
  comment = { fg = "fg_muted", italic = true },
  keyword = "purple",
  keyword_return = nil, -- как keyword
  storage = nil, -- func, var, type — как keyword
  ["function"] = "blue",
  method = nil, -- как function
  builtin = "cyan", -- len, make, fmt.Println у встроенных
  string = "green",
  escape = "pink",
  regex = "yellow",
  number = "orange",
  boolean = "orange",
  constant = "orange",
  type = "cyan",
  interface = nil, -- как type
  variable = "fg",
  parameter = "fg_dim",
  property = "fg_dim",
  namespace = "fg_dim",
  operator = "fg_dim",
  punctuation = "fg_dim",
  tag = "red",
  attribute = "yellow",
  label = "blue",
  macro = "purple",
}

--- Строки синтаксиса темы → спецификации групп ({fg=…, italic=…}), ссылки на палитру раскрыты
function M.syntax(t, p)
  local s = vim.tbl_extend("force", SYNTAX, t.syntax or {})
  s.keyword_return = s.keyword_return or s.keyword
  s.storage = s.storage or s.keyword
  s.method = s.method or s["function"]
  s.interface = s.interface or s.type
  local out = {}
  for role, v in pairs(s) do out[role] = M.spec(v, p) end
  return out
end

--- "purple" | "#hex" | { fg, bg, sp, bold, italic, underline, undercurl, strikethrough, reverse, link } → спецификация
function M.spec(v, p)
  if v == nil then return {} end
  if type(v) == "string" then v = { fg = v } end
  local out = {}
  for k, x in pairs(v) do
    if k == "fg" or k == "bg" or k == "sp" then
      if x == "none" or x == "NONE" then out[k] = "NONE"
      else out[k] = color.normalize(p[x] or x, p.bg) end
    else
      out[k] = x
    end
  end
  return out
end

local function with(base, extra) return vim.tbl_extend("force", base, extra) end

function M.build(t, opts)
  opts = opts or {}
  local p, light = M.palette(t)
  local s = M.syntax(t, p)
  local blend = color.blend
  local bg = opts.transparent and "NONE" or p.bg
  local float_bg = opts.transparent and "NONE" or p.bg_alt
  local g = {}

  -- редактор
  g.Normal = { fg = p.fg, bg = bg }
  -- неактивное окно чуть темнее (на светлой — чуть серее): сразу видно, где курсор; разница — пара процентов
  local inactive = opts.transparent and "NONE" or color.shade(p.bg, light and -0.03 or -0.25)
  g.NormalNC = { fg = p.fg, bg = inactive }
  g.NormalFloat = { fg = p.fg, bg = float_bg }
  g.FloatBorder = { fg = p.border, bg = float_bg }
  -- заголовок всплывающего окна — плашкой акцента (с прозрачным фоном — просто цветом)
  g.FloatTitle = opts.transparent and { fg = p.accent, bold = true } or { fg = p.bg, bg = p.accent, bold = true }
  g.FloatFooter = { fg = p.fg_muted, bg = float_bg }
  g.Cursor = { fg = p.bg, bg = p.accent }
  g.lCursor = { link = "Cursor" }
  g.CursorIM = { link = "Cursor" }
  g.TermCursor = { link = "Cursor" }
  g.CursorLine = { bg = p.bg_highlight }
  g.CursorColumn = { bg = p.bg_highlight }
  g.ColorColumn = { bg = p.bg_highlight }
  g.CursorLineNr = { fg = p.accent, bold = true }
  g.LineNr = { fg = p.fg_muted }
  -- поля и разделители без своего фона — берут фон окна (активного или притушенного)
  g.SignColumn = { bg = "NONE" }
  g.FoldColumn = { fg = p.fg_muted, bg = "NONE" }
  g.Folded = { fg = p.fg_dim, bg = p.bg_alt }
  g.WinSeparator = { fg = p.border, bg = "NONE" }
  g.VertSplit = { link = "WinSeparator" }
  g.EndOfBuffer = { fg = p.bg }
  g.Visual = { bg = p.bg_visual }
  g.VisualNOS = { link = "Visual" }
  g.Search = { fg = p.fg, bg = blend(p.yellow, p.bg, 0.3) }
  g.IncSearch = { fg = p.bg, bg = p.orange, bold = true }
  g.CurSearch = { link = "IncSearch" }
  g.Substitute = { fg = p.bg, bg = p.red }
  g.MatchParen = { fg = p.accent, bold = true } -- парная скобка — цветом, без заливки
  g.Pmenu = { fg = p.fg, bg = p.bg_alt }
  g.PmenuSel = { bg = p.bg_visual, bold = true }
  g.PmenuSbar = { bg = p.bg_alt }
  g.PmenuThumb = { bg = p.border }
  g.PmenuKind = { fg = p.fg_dim, bg = p.bg_alt }
  g.PmenuExtra = { fg = p.fg_muted, bg = p.bg_alt }
  g.PmenuMatch = { fg = p.accent, bold = true }
  g.WildMenu = { link = "PmenuSel" }
  g.StatusLine = { fg = p.fg_dim, bg = p.bg_alt }
  g.StatusLineNC = { fg = p.fg_muted, bg = p.bg_alt }
  g.TabLine = { fg = p.fg_muted, bg = p.bg_alt }
  g.TabLineSel = { fg = p.fg, bg = p.bg, bold = true }
  g.TabLineFill = { bg = p.bg_alt }
  g.WinBar = { fg = p.fg_dim, bg = bg }
  g.WinBarNC = { fg = p.fg_muted, bg = inactive }
  g.Title = { fg = p.accent, bold = true }
  g.Directory = { fg = p.blue }
  g.ErrorMsg = { fg = p.red }
  g.WarningMsg = { fg = p.yellow }
  g.MoreMsg = { fg = p.green }
  g.ModeMsg = { fg = p.fg_dim, bold = true }
  g.Question = { fg = p.blue }
  g.MsgArea = { fg = p.fg }
  g.NonText = { fg = p.border }
  g.Whitespace = { fg = p.border }
  g.SpecialKey = { fg = p.border }
  g.Conceal = { fg = p.fg_muted }
  g.QuickFixLine = { bg = p.bg_visual }
  g.SpellBad = { sp = p.red, undercurl = true }
  g.SpellCap = { sp = p.yellow, undercurl = true }
  g.SpellRare = { sp = p.purple, undercurl = true }
  g.SpellLocal = { sp = p.cyan, undercurl = true }

  -- изменения
  g.DiffAdd = { bg = p.diff_add }
  g.DiffDelete = { fg = blend(p.red, p.bg, 0.5), bg = p.diff_delete }
  g.DiffChange = { bg = p.diff_change }
  g.DiffText = { bg = p.diff_text }
  g.Added = { fg = p.green }
  g.Changed = { fg = p.blue }
  g.Removed = { fg = p.red }
  g.diffAdded = { link = "Added" }
  g.diffChanged = { link = "Changed" }
  g.diffRemoved = { link = "Removed" }

  -- ошибки
  for name, c in pairs({ Error = p.red, Warn = p.yellow, Info = p.blue, Hint = p.cyan, Ok = p.green }) do
    g["Diagnostic" .. name] = { fg = c }
    g["DiagnosticVirtualText" .. name] = { fg = c, bg = blend(c, p.bg, 0.1) }
    g["DiagnosticUnderline" .. name] = { sp = c, undercurl = true }
    g["DiagnosticSign" .. name] = { fg = c, bg = "NONE" }
    g["DiagnosticFloating" .. name] = { fg = c, bg = float_bg }
  end
  g.DiagnosticUnnecessary = { fg = p.fg_muted }
  g.DiagnosticDeprecated = { strikethrough = true }
  g.LspReferenceText = { bg = blend(p.fg, p.bg, 0.12) }
  g.LspReferenceRead = { link = "LspReferenceText" }
  g.LspReferenceWrite = { bg = blend(p.fg, p.bg, 0.12), underline = true }
  g.LspInlayHint = { fg = p.fg_muted, italic = true }
  g.LspCodeLens = { fg = p.fg_muted, italic = true }
  g.LspSignatureActiveParameter = { fg = p.accent, bold = true, underline = true }

  -- синтаксис (старые группы)
  g.Comment = s.comment
  g.Constant = s.constant
  g.String = s.string
  g.Character = s.string
  g.Number = s.number
  g.Float = s.number
  g.Boolean = s.boolean
  g.Identifier = s.variable
  g.Function = s["function"]
  g.Statement = s.keyword
  g.Conditional = s.keyword
  g.Repeat = s.keyword
  g.Label = s.label
  g.Operator = s.operator
  g.Keyword = s.keyword
  g.Exception = s.keyword
  g.PreProc = s.macro
  g.Include = s.keyword
  g.Define = s.macro
  g.Macro = s.macro
  g.PreCondit = s.macro
  g.Type = s.type
  g.StorageClass = s.storage
  g.Structure = s.type
  g.Typedef = s.type
  g.Special = s.builtin
  g.SpecialChar = s.escape
  g.Tag = s.tag
  g.Delimiter = s.punctuation
  g.SpecialComment = s.comment
  g.Debug = { fg = p.orange }
  g.Underlined = { underline = true }
  g.Ignore = { fg = p.fg_muted }
  g.Error = { fg = p.red }
  g.Todo = { fg = p.bg, bg = p.yellow, bold = true }

  -- treesitter
  local ts = {
    ["@variable"] = s.variable,
    ["@variable.builtin"] = s.builtin,
    ["@variable.parameter"] = s.parameter,
    ["@variable.parameter.builtin"] = s.builtin,
    ["@variable.member"] = s.property,
    ["@constant"] = s.constant,
    ["@constant.builtin"] = s.constant,
    ["@constant.macro"] = s.macro,
    ["@module"] = s.namespace,
    ["@module.builtin"] = s.builtin,
    ["@label"] = s.label,
    ["@string"] = s.string,
    ["@string.documentation"] = s.comment,
    ["@string.escape"] = s.escape,
    ["@string.regexp"] = s.regex,
    ["@string.special"] = s.escape,
    ["@string.special.url"] = with(s.string, { underline = true }),
    ["@character"] = s.string,
    ["@character.special"] = s.escape,
    ["@number"] = s.number,
    ["@number.float"] = s.number,
    ["@boolean"] = s.boolean,
    ["@type"] = s.type,
    ["@type.builtin"] = s.type,
    ["@type.definition"] = s.type,
    ["@attribute"] = s.attribute,
    ["@attribute.builtin"] = s.attribute,
    ["@property"] = s.property,
    ["@function"] = s["function"],
    ["@function.builtin"] = s.builtin,
    ["@function.call"] = s["function"],
    ["@function.macro"] = s.macro,
    ["@function.method"] = s.method,
    ["@function.method.call"] = s.method,
    ["@constructor"] = s.type,
    ["@operator"] = s.operator,
    ["@keyword"] = s.keyword,
    ["@keyword.function"] = s.storage,
    ["@keyword.type"] = s.storage,
    ["@keyword.modifier"] = s.storage,
    ["@keyword.return"] = s.keyword_return,
    ["@keyword.import"] = s.keyword,
    ["@keyword.conditional"] = s.keyword,
    ["@keyword.repeat"] = s.keyword,
    ["@keyword.exception"] = s.keyword,
    ["@keyword.operator"] = s.keyword,
    ["@keyword.coroutine"] = s.keyword,
    ["@keyword.directive"] = s.macro,
    ["@punctuation.delimiter"] = s.punctuation,
    ["@punctuation.bracket"] = s.punctuation,
    ["@punctuation.special"] = s.escape,
    ["@comment"] = s.comment,
    ["@comment.documentation"] = s.comment,
    ["@comment.todo"] = { fg = p.bg, bg = p.blue, bold = true },
    ["@comment.note"] = { fg = p.bg, bg = p.cyan, bold = true },
    ["@comment.warning"] = { fg = p.bg, bg = p.yellow, bold = true },
    ["@comment.error"] = { fg = p.bg, bg = p.red, bold = true },
    ["@tag"] = s.tag,
    ["@tag.builtin"] = s.tag,
    ["@tag.attribute"] = s.attribute,
    ["@tag.delimiter"] = s.punctuation,
    ["@markup.heading"] = { fg = p.accent, bold = true },
    ["@markup.strong"] = { bold = true },
    ["@markup.italic"] = { italic = true },
    ["@markup.strikethrough"] = { strikethrough = true },
    ["@markup.underline"] = { underline = true },
    ["@markup.link"] = { fg = p.blue },
    ["@markup.link.url"] = { fg = p.cyan, underline = true },
    ["@markup.raw"] = s.string,
    ["@markup.list"] = { fg = p.accent },
    ["@markup.quote"] = { fg = p.fg_dim, italic = true },
    ["@diff.plus"] = { fg = p.green },
    ["@diff.minus"] = { fg = p.red },
    ["@diff.delta"] = { fg = p.blue },
    -- LSP: семантика поверх treesitter
    ["@lsp.type.namespace"] = s.namespace,
    ["@lsp.type.type"] = s.type,
    ["@lsp.type.class"] = s.type,
    ["@lsp.type.struct"] = s.type,
    ["@lsp.type.interface"] = s.interface,
    ["@lsp.type.enum"] = s.type,
    ["@lsp.type.enumMember"] = s.constant,
    ["@lsp.type.typeParameter"] = s.type,
    ["@lsp.type.parameter"] = s.parameter,
    ["@lsp.type.property"] = s.property,
    ["@lsp.type.variable"] = {}, -- не перебивать treesitter (встроенные, константы)
    ["@lsp.type.function"] = s["function"],
    ["@lsp.type.method"] = s.method,
    ["@lsp.type.macro"] = s.macro,
    ["@lsp.type.keyword"] = s.keyword,
    ["@lsp.type.string"] = s.string,
    ["@lsp.type.number"] = s.number,
    ["@lsp.type.comment"] = {},
    ["@lsp.typemod.variable.readonly"] = s.constant,
    ["@lsp.typemod.variable.defaultLibrary"] = s.builtin,
    ["@lsp.typemod.function.defaultLibrary"] = s.builtin,
    ["@lsp.mod.deprecated"] = { strikethrough = true },
  }
  for k, v in pairs(ts) do g[k] = v end

  -- плагины
  g.SnacksDashboardHeader = { fg = p.accent }
  g.SnacksDashboardKey = { fg = p.accent, bold = true }
  g.SnacksDashboardIcon = { fg = p.accent }
  g.SnacksDashboardDesc = { fg = p.fg }
  g.SnacksDashboardFooter = { fg = p.fg_muted, italic = true }
  g.SnacksDashboardTitle = { fg = p.fg, bold = true }
  g.SnacksDashboardSpecial = { fg = p.accent }
  g.SnacksDashboardFile = { fg = p.fg }
  g.SnacksDashboardDir = { fg = p.fg_muted }
  -- поиск: заголовки плашками, строка ввода — рамкой акцента, выбранная строка — мягкой подсветкой
  g.SnacksPickerMatch = { fg = p.accent, bold = true }
  g.SnacksPickerDir = { fg = p.fg_muted }
  g.SnacksPickerTitle = { fg = float_bg == "NONE" and p.accent or p.bg, bg = float_bg == "NONE" and "NONE" or p.accent, bold = true }
  g.SnacksPickerPreviewTitle = { fg = float_bg == "NONE" and p.blue or p.bg, bg = float_bg == "NONE" and "NONE" or p.blue, bold = true }
  g.SnacksPickerListTitle = { link = "SnacksPickerTitle" }
  g.SnacksPickerInputBorder = { fg = blend(p.accent, float_bg == "NONE" and p.bg or p.bg_alt, 0.55), bg = float_bg }
  g.SnacksPickerInputTitle = { link = "SnacksPickerTitle" }
  g.SnacksPickerPrompt = { fg = p.accent, bold = true }
  g.SnacksPickerListCursorLine = { bg = blend(p.accent, p.bg_alt, 0.14) }
  g.SnacksPickerCursorLine = { bg = blend(p.accent, p.bg_alt, 0.14) }
  g.SnacksPickerTotals = { fg = p.fg_muted }
  g.SnacksPickerSelected = { fg = p.green }
  g.SnacksPickerToggle = { fg = p.accent, bg = blend(p.accent, p.bg_alt, 0.18), italic = true }
  g.SnacksPickerSpinner = { fg = p.accent }
  g.SnacksInputNormal = { link = "NormalFloat" }
  g.SnacksInputBorder = { fg = blend(p.accent, float_bg == "NONE" and p.bg or p.bg_alt, 0.55), bg = float_bg }
  g.SnacksInputTitle = { link = "FloatTitle" }
  g.SnacksInputIcon = { fg = p.accent }
  g.SnacksIndent = { fg = blend(p.fg, p.bg, 0.08) }
  g.SnacksIndentScope = { fg = blend(p.accent, p.bg, 0.45) }
  -- уведомления: рамка, значок и заголовок — цветом уровня
  for lvl, c in pairs({ Info = p.blue, Warn = p.yellow, Error = p.red, Debug = p.fg_muted, Trace = p.purple }) do
    g["SnacksNotifierBorder" .. lvl] = { fg = blend(c, p.bg, 0.55), bg = float_bg }
    g["SnacksNotifierIcon" .. lvl] = { fg = c }
    g["SnacksNotifierTitle" .. lvl] = { fg = c, bold = true }
    g["SnacksNotifier" .. lvl] = { link = "NormalFloat" }
  end
  g.SnacksNotifierHistory = { link = "NormalFloat" }
  g.SnacksNotifierHistoryTitle = { link = "FloatTitle" }
  g.BlinkCmpMenu = { link = "Pmenu" }
  g.BlinkCmpMenuBorder = { fg = p.border, bg = p.bg_alt }
  g.BlinkCmpMenuSelection = { link = "PmenuSel" }
  g.BlinkCmpLabelMatch = { fg = p.accent, bold = true }
  g.BlinkCmpLabelDescription = { fg = p.fg_muted }
  g.BlinkCmpLabelDetail = { fg = p.fg_muted }
  g.BlinkCmpKind = { fg = p.fg_muted }
  g.BlinkCmpLabelDeprecated = { fg = p.fg_muted, strikethrough = true }
  g.BlinkCmpGhostText = { fg = p.fg_muted, italic = true }
  g.BlinkCmpDoc = { link = "NormalFloat" }
  g.BlinkCmpDocBorder = { link = "FloatBorder" }
  g.BlinkCmpSignatureHelp = { link = "NormalFloat" }
  g.BlinkCmpSignatureHelpBorder = { link = "FloatBorder" }
  for kind, c in pairs({ Function = p.blue, Method = p.blue, Constructor = p.cyan, Variable = p.fg, Field = p.cyan,
    Property = p.cyan, Keyword = p.purple, Snippet = p.green, Struct = p.cyan, Class = p.cyan, Interface = p.cyan,
    Constant = p.orange, Enum = p.orange, EnumMember = p.orange, Module = p.fg_dim, Text = p.fg_muted, File = p.blue,
    Folder = p.blue, TypeParameter = p.cyan, Value = p.orange, Operator = p.fg_dim, Unit = p.orange }) do
    g["BlinkCmpKind" .. kind] = { fg = c }
  end
  g.WhichKey = { fg = p.accent }
  g.WhichKeyGroup = { fg = p.blue }
  g.WhichKeyDesc = { fg = p.fg }
  g.WhichKeySeparator = { fg = p.fg_muted }
  g.WhichKeyNormal = { link = "NormalFloat" }
  g.WhichKeyBorder = { link = "FloatBorder" }
  g.WhichKeyTitle = { link = "FloatTitle" }
  g.GitSignsAdd = { fg = p.green }
  g.GitSignsChange = { fg = p.blue }
  g.GitSignsDelete = { fg = p.red }
  g.NeotestPassed = { fg = p.green }
  g.NeotestFailed = { fg = p.red }
  g.NeotestRunning = { fg = p.yellow }
  g.NeotestSkipped = { fg = p.fg_muted }
  g.NeotestNamespace = { fg = p.purple }
  g.NeotestFile = { fg = p.blue }
  g.NeotestDir = { fg = p.blue }
  g.NeotestAdapterName = { fg = p.accent, bold = true }
  g.DapStoppedLine = { bg = blend(p.yellow, p.bg, 0.15) }
  g.FlashLabel = { fg = p.bg, bg = p.pink, bold = true }
  g.FlashMatch = { fg = p.fg, bg = blend(p.blue, p.bg, 0.3) }
  g.FlashCurrent = { fg = p.bg, bg = p.green }
  g.FlashBackdrop = { fg = p.fg_muted }
  g.LazyNormal = { link = "NormalFloat" }
  g.MasonNormal = { link = "NormalFloat" }
  g.TreesitterContext = { bg = p.bg_alt }
  g.TreesitterContextBottom = { sp = p.border, underline = true }
  g.TreesitterContextLineNumber = { fg = p.accent, bg = p.bg_alt }
  g.MiniIconsAzure = { fg = p.cyan }
  g.MiniIconsBlue = { fg = p.blue }
  g.MiniIconsCyan = { fg = p.cyan }
  g.MiniIconsGreen = { fg = p.green }
  g.MiniIconsGrey = { fg = p.fg_muted }
  g.MiniIconsOrange = { fg = p.orange }
  g.MiniIconsPurple = { fg = p.purple }
  g.MiniIconsRed = { fg = p.red }
  g.MiniIconsYellow = { fg = p.yellow }
  -- цветные скобки (rainbow-delimiters)
  g.RainbowDelimiterRed = { fg = p.red }
  g.RainbowDelimiterOrange = { fg = p.orange }
  g.RainbowDelimiterYellow = { fg = p.yellow }
  g.RainbowDelimiterGreen = { fg = p.green }
  g.RainbowDelimiterCyan = { fg = p.cyan }
  g.RainbowDelimiterBlue = { fg = p.blue }
  g.RainbowDelimiterViolet = { fg = p.purple }
  g.OwnIconPink = { fg = p.pink }
  g.OwnIconAccent = { fg = p.accent }
  g.DotfilesRunMain = { fg = p.green }
  g.DotfilesRunTest = { fg = p.cyan }
  g.Goplements = { fg = p.purple, italic = true }
  g.GitSignsCurrentLineBlame = { fg = p.fg_muted, italic = true }
  g.GitSignsAddInline = { bg = blend(p.green, p.bg, 0.3) }
  g.GitSignsDeleteInline = { bg = blend(p.red, p.bg, 0.3) }
  g.GitSignsChangeInline = { bg = blend(p.blue, p.bg, 0.3) }
  g.GitSignsStagedAdd = { fg = blend(p.green, p.bg, 0.5) }
  g.GitSignsStagedChange = { fg = blend(p.blue, p.bg, 0.5) }
  g.GitSignsStagedDelete = { fg = blend(p.red, p.bg, 0.5) }
  -- значки в подсказке клавиш — цветами палитры
  for name, c in pairs({ Azure = p.cyan, Blue = p.blue, Cyan = p.cyan, Green = p.green, Grey = p.fg_muted,
    Orange = p.orange, Purple = p.purple, Red = p.red, Yellow = p.yellow }) do
    g["WhichKeyIcon" .. name] = { fg = c }
  end
  g.WhichKeyIcon = { fg = p.accent }
  g.WhichKeyValue = { fg = p.fg_muted }
  -- markdown (render-markdown): заголовки — цветной полосой во всю строку, код — подложкой
  for i, c in ipairs({ p.accent, p.blue, p.cyan, p.green, p.yellow, p.orange }) do
    g["RenderMarkdownH" .. i] = { fg = c, bold = true }
    g["RenderMarkdownH" .. i .. "Bg"] = { fg = c, bg = blend(c, p.bg, 0.12), bold = true }
    g["@markup.heading." .. i .. ".markdown"] = { fg = c, bold = true }
  end
  g.RenderMarkdownCode = { bg = p.bg_alt }
  g.RenderMarkdownCodeInline = { fg = p.fg, bg = p.bg_highlight }
  g.RenderMarkdownBullet = { fg = p.accent }
  g.RenderMarkdownDash = { fg = p.border }
  g.RenderMarkdownTableHead = { fg = p.border }
  g.RenderMarkdownTableRow = { fg = p.border }
  g.RenderMarkdownQuote = { fg = p.fg_muted }
  g.RenderMarkdownChecked = { fg = p.green }
  g.RenderMarkdownUnchecked = { fg = p.fg_muted }
  -- Lazy и Mason — в тон редактору
  g.LazyH1 = { fg = p.bg, bg = p.accent, bold = true }
  g.LazyButton = { fg = p.fg_dim, bg = p.bg_highlight }
  g.LazyButtonActive = { fg = p.bg, bg = p.accent, bold = true }
  g.LazySpecial = { fg = p.accent }
  g.LazyProgressDone = { fg = p.accent, bold = true }
  g.LazyProgressTodo = { fg = p.border }
  g.MasonHeader = { fg = p.bg, bg = p.accent, bold = true }
  g.MasonHighlight = { fg = p.accent }
  g.MasonHighlightBlockBold = { fg = p.bg, bg = p.accent, bold = true }
  g.MasonMutedBlock = { fg = p.fg_dim, bg = p.bg_highlight }

  -- правки самой темы — поверх всего
  for name, v in pairs(t.groups or {}) do g[name] = M.spec(v, p) end

  local term = {
    blend(p.fg, p.bg, 0.15), p.red, p.green, p.yellow, p.blue, p.purple, p.cyan, p.fg_dim,
    p.fg_muted, color.shade(p.red, 0.15), color.shade(p.green, 0.15), color.shade(p.yellow, 0.15),
    color.shade(p.blue, 0.15), color.shade(p.purple, 0.15), color.shade(p.cyan, 0.15), p.fg,
  }
  return g, p, light, term
end

return M
