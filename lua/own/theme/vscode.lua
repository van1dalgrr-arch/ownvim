-- Тема VS Code (colors + tokenColors + semanticTokenColors) → тема ownvim (palette + syntax).
-- Цвета интерфейса берутся из colors (editor.background, editorCursor.foreground…), цвета кода — из правил
-- tokenColors по областям TextMate (keyword.control, entity.name.function…): у каждой роли — список областей,
-- побеждает самое точное правило, как в самом VS Code.
local color = require("own.theme.color")

local M = {}

-- роль ownvim → области TextMate по убыванию важности
local SCOPES = {
  comment = { "comment.line", "comment" },
  keyword = { "keyword.control", "keyword" },
  storage = { "storage.type", "storage" },
  keyword_return = { "keyword.control.flow", "keyword.control" },
  ["function"] = { "entity.name.function", "support.function", "meta.function-call" },
  method = { "entity.name.function.member", "entity.name.function" },
  builtin = { "support.function.builtin", "support.function", "variable.language" },
  string = { "string.quoted", "string" },
  escape = { "constant.character.escape" },
  regex = { "string.regexp" },
  number = { "constant.numeric" },
  boolean = { "constant.language.boolean", "constant.language" },
  constant = { "variable.other.constant", "constant.other", "constant" },
  type = { "entity.name.type", "support.type", "storage.type" },
  interface = { "entity.name.type.interface", "entity.name.type" },
  variable = { "variable.other.readwrite", "variable.other", "variable" },
  parameter = { "variable.parameter" },
  property = { "variable.other.property", "variable.other.member", "support.variable.property", "meta.property-name" },
  namespace = { "entity.name.namespace", "entity.name.package", "entity.name.type.module" },
  operator = { "keyword.operator" },
  punctuation = { "punctuation.separator", "punctuation" },
  tag = { "entity.name.tag" },
  attribute = { "entity.other.attribute-name" },
  label = { "entity.name.label" },
  macro = { "entity.name.function.preprocessor", "meta.preprocessor" },
}

-- семантические токены VS Code → роль
local SEMANTIC = {
  parameter = "parameter", property = "property", variable = "variable", ["function"] = "function",
  method = "method", type = "type", class = "type", interface = "interface", namespace = "namespace",
  keyword = "keyword", string = "string", number = "number", comment = "comment", macro = "macro",
}

local function rules(theme)
  local out = {}
  for _, r in ipairs(theme.tokenColors or {}) do
    local st = r.settings or {}
    if st.foreground or st.fontStyle then
      local scopes = r.scope
      if type(scopes) == "string" then scopes = vim.split(scopes, ",") end
      for _, sc in ipairs(scopes or {}) do
        sc = vim.trim(sc)
        -- «потомки» (a b) и исключения (a - b) не разбираем — берём только простые области
        if sc ~= "" and not sc:find(" ") then
          out[#out + 1] = { scope = sc, fg = st.foreground, style = st.fontStyle }
        end
      end
    end
  end
  return out
end

-- самое точное правило для области: правило «keyword» подходит к «keyword.control.go», длиннее — точнее
local function match(list, scope)
  local best, len
  for _, r in ipairs(list) do
    if scope == r.scope or vim.startswith(scope, r.scope .. ".") then
      if not len or #r.scope >= len then best, len = r, #r.scope end
    end
  end
  return best
end

local function style(spec, font)
  if not font then return spec end
  for word in font:gmatch("%a+") do
    if word == "italic" or word == "bold" or word == "underline" or word == "strikethrough" then spec[word] = true end
  end
  return spec
end

--- Конвертировать разобранный JSON темы VS Code; kind — "dark"/"light" (uiTheme из package.json)
function M.convert(theme, name, kind)
  local c = theme.colors or {}
  local bg = color.normalize(c["editor.background"] or c["editorPane.background"], "#000000")
    or (kind == "light" and "#ffffff" or "#1e1e1e")
  local function get(...)
    for _, key in ipairs({ ... }) do
      local v = color.normalize(c[key], bg)
      if v then return v end
    end
  end
  local fg = get("editor.foreground", "foreground") or (kind == "light" and "#333333" or "#d4d4d4")
  kind = kind or (color.luminance(bg) > 0.5 and "light" or "dark")

  local list = rules(theme)
  local syntax = {}
  for role, scopes in pairs(SCOPES) do
    for _, sc in ipairs(scopes) do
      local r = match(list, sc)
      if r then
        local spec = { fg = color.normalize(r.fg, bg) }
        syntax[role] = style(spec, r.style)
        if not spec.fg then syntax[role].fg = nil end
        break
      end
    end
  end
  for token, v in pairs(theme.semanticTokenColors or {}) do
    local role = SEMANTIC[token]
    if role then
      local fgc = type(v) == "string" and v or (type(v) == "table" and v.foreground)
      fgc = color.normalize(fgc, bg)
      if fgc then syntax[role] = style({ fg = fgc }, type(v) == "table" and v.fontStyle or nil) end
    end
  end
  for role, v in pairs(syntax) do
    if not v.fg and not next(v) then syntax[role] = nil end
  end

  local palette = {
    bg = bg,
    fg = fg,
    bg_alt = get("sideBar.background", "editorWidget.background", "panel.background"),
    bg_highlight = get("editor.lineHighlightBackground"),
    bg_visual = get("editor.selectionBackground"),
    border = get("editorGroup.border", "panel.border", "sideBar.border", "editorWidget.border", "focusBorder"),
    fg_dim = get("sideBar.foreground", "descriptionForeground"),
    fg_muted = get("editorLineNumber.foreground"),
    accent = get("editorCursor.foreground", "focusBorder", "button.background"),
    red = get("terminal.ansiRed", "editorError.foreground", "errorForeground"),
    green = get("terminal.ansiGreen", "gitDecoration.addedResourceForeground"),
    yellow = get("terminal.ansiYellow", "editorWarning.foreground"),
    blue = get("terminal.ansiBlue", "editorInfo.foreground"),
    purple = get("terminal.ansiMagenta"),
    cyan = get("terminal.ansiCyan"),
    pink = get("terminal.ansiBrightMagenta"),
    diff_add = get("diffEditor.insertedLineBackground", "diffEditor.insertedTextBackground"),
    diff_delete = get("diffEditor.removedLineBackground", "diffEditor.removedTextBackground"),
  }
  -- оранжевого в терминальных цветах нет — берём у чисел
  palette.orange = (syntax.number and syntax.number.fg) or get("terminal.ansiBrightYellow")
  -- брать линию текущей строки, только если она отличается от фона
  if palette.bg_highlight == bg then palette.bg_highlight = nil end
  -- курсор цвета текста — не акцент; тогда акцент — ключевые слова
  if palette.accent == fg then palette.accent = syntax.keyword and syntax.keyword.fg or nil end

  local groups = {}
  local lnr_active = get("editorLineNumber.activeForeground")
  if lnr_active then groups.CursorLineNr = { fg = lnr_active, bold = true } end
  local guide = get("editorIndentGuide.background1", "editorIndentGuide.background")
  if guide then groups.SnacksIndent = { fg = guide } end

  return {
    name = theme.name or name,
    type = kind,
    palette = palette,
    syntax = syntax,
    groups = groups,
  }
end

return M
