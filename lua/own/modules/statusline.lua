-- Своя статусная строка (вместо lualine): блоки из settings.jsonc, как элементы status bar в VS Code.
-- Раздел "statusline":
--   "style": "bubbles" | "arrows" | "slant" | "flat" | "plain" — форма крайних блоков;
--     "zed" — как status bar в Zed: без плашек, всё приглушённым текстом, режим — цветной надписью
--     "frame" — рамкой, как промпт dotfiles: ╰─( ОБЫЧНЫЙ )─[ main ]─[ main.go ]────[ 12:4 ]─╯
--   "left": ["mode", "branch", "diagnostics", "file"], "right": ["search", "macro", "lsp", "position", "time"]
--     блоки: mode, branch, diagnostics, file, filetype, encoding, indent, lsp, diff, position, progress, time,
--     search (найдено 3/12), macro (пишется @q), tests (✓ 42 / ✗ 1 — фоновые тесты), rest (пора отдохнуть / ☕ перерыв),
--     quiet (тихий режим включён), ram (занято памяти), uptime (сколько работает Mac), wpm (скорость печати),
--     music (что играет: Яндекс Музыка и др., клик — пауза; раздел "music" — lua/own/music.lua),
--     panels (кнопки панелей, как в Zed: проект, структура, тесты, база | терминал, проблемы | Claude; клик — вкл/выкл),
--     problems (ошибки и предупреждения всего проекта, нули тоже — как в Zed; клик — панель «Проблемы»),
--     language (язык файла словом: Go, Rust, Plain Text),
--     а также свои из "custom"
--   "custom": { "k8s": { "shell": "kubectl config current-context", "every_ms": 10000, "icon": "…" },
--               "hi":  { "text": "привет", "color": "pink" } } — свой текст или вывод команды (не блокирует)
--   "mode_names": { "n": "ОБЫЧНЫЙ", "i": "ВСТАВКА", … } — подписи режимов (буква — первая буква режима)
--   "time_format": "%H:%M", "path": "relative" | "name" | "full"
-- Цвета — из текущей темы (любой, не только JSON). Всё применяется на лету.
local settings = require("own.settings")

local M = {}

local function o() return (settings.current or {}).statusline or {} end

local MODES = {
  n = "ОБЫЧНЫЙ", i = "ВСТАВКА", v = "ВЫДЕЛЕНИЕ", V = "СТРОКИ", ["\22"] = "БЛОК", s = "ВЫБОР", S = "ВЫБОР",
  ["\19"] = "ВЫБОР", R = "ЗАМЕНА", c = "КОМАНДА", t = "ТЕРМИНАЛ", r = "ПОДТВЕРДИ", ["!"] = "КОМАНДА",
}
local MODE_KIND = { n = "Normal", i = "Insert", v = "Visual", V = "Visual", ["\22"] = "Visual", s = "Visual", S = "Visual",
  ["\19"] = "Visual", R = "Replace", c = "Command", t = "Terminal", r = "Command", ["!"] = "Command" }

local STYLES = {
  bubbles = { lo = "\u{e0b6}", lc = "\u{e0b4}", ro = "\u{e0b6}", rc = "\u{e0b4}" },
  arrows = { lo = "", lc = "\u{e0b0}", ro = "\u{e0b2}", rc = "" },
  slant = { lo = "", lc = "\u{e0bc}", ro = "\u{e0ba}", rc = "" },
  flat = { lo = "", lc = "", ro = "", rc = "" },
}

-- цвета из темы → свои группы (пересчитываются при смене темы)
local function color(group, attr)
  local h = vim.api.nvim_get_hl(0, { name = group, link = false })
  return h[attr or "fg"]
end

local function define()
  local base_bg = color("StatusLine", "bg") or color("Normal", "bg") or 0x1e1e1e
  local base_fg = color("StatusLine") or color("Normal") or 0xcccccc
  local dark = color("Normal", "bg") or 0x000000
  local block_bg = color("CursorLine", "bg") or base_bg
  local kinds = require("own.modes").colors() -- те же цвета, что у курсора
  vim.api.nvim_set_hl(0, "OwnSL", { fg = base_fg, bg = base_bg })
  vim.api.nvim_set_hl(0, "OwnSLMuted", { fg = color("Comment") or base_fg, bg = base_bg })
  vim.api.nvim_set_hl(0, "OwnSLActive", { fg = color("OwnIconAccent") or color("Title") or base_fg, bg = base_bg })
  -- линии рамки (стиль frame) — приглушённым цветом темы
  vim.api.nvim_set_hl(0, "OwnSLFrame", { fg = color("Comment") or base_fg, bg = base_bg })
  vim.api.nvim_set_hl(0, "OwnSLBlock", { fg = color("Normal") or base_fg, bg = block_bg })
  vim.api.nvim_set_hl(0, "OwnSLBlockEdge", { fg = block_bg, bg = base_bg })
  for kind, c in pairs(kinds) do
    vim.api.nvim_set_hl(0, "OwnSLMode" .. kind, { fg = dark, bg = c, bold = true })
    vim.api.nvim_set_hl(0, "OwnSLMode" .. kind .. "Edge", { fg = c, bg = base_bg })
    vim.api.nvim_set_hl(0, "OwnSLMode" .. kind .. "ToBlock", { fg = c, bg = block_bg })
    vim.api.nvim_set_hl(0, "OwnSLMode" .. kind .. "Text", { fg = c, bg = base_bg, bold = true })
  end
  for _, name in ipairs({ "Error", "Warn", "Info", "Hint" }) do
    vim.api.nvim_set_hl(0, "OwnSLDiag" .. name, { fg = color("Diagnostic" .. name), bg = base_bg })
  end
  for _, name in ipairs({ "Added", "Changed", "Removed" }) do
    vim.api.nvim_set_hl(0, "OwnSL" .. name, { fg = color(name), bg = base_bg })
  end
  for _, name in ipairs({ "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "grey" }) do
    local src = ({ red = "DiagnosticError", orange = "Number", yellow = "DiagnosticWarn", green = "String",
      cyan = "Special", blue = "Function", purple = "Statement", pink = "OwnIconPink", grey = "Comment" })[name]
    vim.api.nvim_set_hl(0, "OwnSLColor_" .. name, { fg = color(src), bg = base_bg })
  end
end

local function esc(s) return (tostring(s):gsub("%%", "%%%%")) end
local function hl(group, text) return "%#" .. group .. "#" .. text end

-- ветка git: кэш по папке, обновляется в фоне
local branch_cache = {}
local pending = {}
local function refresh_branch(dir)
  if not dir or pending[dir] then return end
  pending[dir] = true
  vim.system({ "git", "-C", dir, "branch", "--show-current" }, { text = true }, function(r)
    branch_cache[dir] = r.code == 0 and vim.trim(r.stdout) or ""
    pending[dir] = nil
    vim.schedule(function() vim.cmd("redrawstatus") end)
  end)
end

-- свои блоки с командой: вывод кэшируется, команда идёт в фоне раз в every_ms
local custom_out, custom_at = {}, {}
local function custom_shell(name, spec)
  local now = vim.uv.now()
  if not custom_at[name] or now - custom_at[name] > (spec.every_ms or 10000) then
    custom_at[name] = now
    vim.system({ "sh", "-c", spec.shell }, { text = true }, function(r)
      custom_out[name] = r.code == 0 and vim.trim((r.stdout or ""):match("[^\n]*")) or ""
      vim.schedule(function() vim.cmd("redrawstatus") end)
    end)
  end
  return custom_out[name] or ""
end

local function buf() return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0) end

local C = {}

-- сколько коммитов не запушено (↑) и не подтянуто (↓), сколько файлов изменено (●) — git status в фоне,
-- только по событиям: открыл, сохранил, вернулся в окно, сменил папку (а не на каждую перерисовку)
local git_cache, git_at = {}, {}
local function refresh_git(dir)
  if git_at[dir] then return end
  git_at[dir] = vim.uv.now()
  vim.system({ "git", "-C", dir, "status", "--porcelain=v1", "--branch" }, { text = true }, function(r)
    if r.code ~= 0 then return end
    local lines = vim.split(r.stdout or "", "\n", { trimempty = true })
    local head = lines[1] or ""
    git_cache[dir] = { ahead = tonumber(head:match("ahead (%d+)")), behind = tonumber(head:match("behind (%d+)")), dirty = #lines - 1 }
    vim.schedule(function() vim.cmd("redrawstatus") end)
  end)
end
function M.git_changed() git_at = {} end

function C.branch()
  local dir = vim.fs.root(buf(), ".git")
  local b = vim.b[buf()].gitsigns_head
  if not b then
    if dir and branch_cache[dir] == nil then refresh_branch(dir) end
    b = dir and branch_cache[dir] or nil
  end
  if not b or b == "" then return nil end
  local out = "\u{e725} " .. esc(b)
  if dir and o().git_status ~= false then
    refresh_git(dir)
    local g = git_cache[dir]
    if g then
      if g.ahead then out = out .. " " .. hl("OwnSLColor_yellow", "↑" .. g.ahead) .. hl("OwnSL", "") end
      if g.behind then out = out .. " " .. hl("OwnSLColor_blue", "↓" .. g.behind) .. hl("OwnSL", "") end
      if g.dirty > 0 then out = out .. " " .. hl("OwnSLColor_orange", "●" .. g.dirty) .. hl("OwnSL", "") end
    end
  end
  return out
end

function C.diagnostics()
  local signs = ((vim.diagnostic.config() or {}).signs or {}).text or {}
  local out = {}
  for sev, name in ipairs({ "Error", "Warn", "Info", "Hint" }) do
    local n = #vim.diagnostic.get(buf(), { severity = sev })
    if n > 0 then out[#out + 1] = hl("OwnSLDiag" .. name, (signs[sev] or name:sub(1, 1) .. " ") .. n) end
  end
  return #out > 0 and table.concat(out, " ") .. hl("OwnSL", "") or nil
end

function C.file()
  local b = buf()
  local name = vim.api.nvim_buf_get_name(b)
  -- служебные окна — понятным словом, а не «[без имени]»
  local SPECIAL = { own_tree = "\u{f0645} Дерево файлов", snacks_dashboard = "Старт", lazy = "Плагины", mason = "Mason",
    qf = "Список", help = "Справка", own_problems = "Проблемы", own_image = "Картинка" }
  local ft = vim.bo[b].filetype
  if SPECIAL[ft] then return SPECIAL[ft] end
  if vim.bo[b].buftype == "terminal" then return "\u{f489} Терминал" end
  if name == "" then return "[без имени]" end
  local mode = o().path or "relative"
  local shown = mode == "name" and vim.fn.fnamemodify(name, ":t") or mode == "full" and vim.fn.fnamemodify(name, ":~")
    or vim.fn.fnamemodify(name, ":~:.")
  local icon = ""
  local ok, icons = pcall(require, "mini.icons")
  if ok then
    local glyph, group = icons.get("file", name)
    icon = hl(group, glyph .. " ") .. hl("OwnSL", "")
  end
  local flags = (vim.bo[b].modified and " ●" or "") .. ((vim.bo[b].readonly or not vim.bo[b].modifiable) and " \u{f023}" or "")
  return icon .. esc(shown) .. flags
end

function C.filetype() local ft = vim.bo[buf()].filetype return ft ~= "" and ft or nil end
function C.encoding() return vim.bo[buf()].fileencoding ~= "" and vim.bo[buf()].fileencoding or vim.o.encoding end
function C.indent() return (vim.bo[buf()].expandtab and "пробелы: " or "табы: ") .. vim.bo[buf()].shiftwidth end

function C.lsp()
  local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = buf() }))
  return #names > 0 and hl("OwnSLMuted", "\u{f085} " .. table.concat(names, " ")) .. hl("OwnSL", "") or nil
end

function C.diff()
  local d = vim.b[buf()].gitsigns_status_dict
  if not d then return nil end
  local out = {}
  if (d.added or 0) > 0 then out[#out + 1] = hl("OwnSLAdded", "+" .. d.added) end
  if (d.changed or 0) > 0 then out[#out + 1] = hl("OwnSLChanged", "~" .. d.changed) end
  if (d.removed or 0) > 0 then out[#out + 1] = hl("OwnSLRemoved", "-" .. d.removed) end
  return #out > 0 and table.concat(out, " ") .. hl("OwnSL", "") or nil
end

-- тесты в фоне — надпись Go-расширения autotest (старое имя блока; новое — ext, там все расширения)
function C.tests()
  local e = package.loaded["own.ext"]
  local s = e and e.status.autotest
  if not s or (#s.filetypes > 0 and not vim.tbl_contains(s.filetypes, vim.bo[buf()].filetype)) then return nil end
  return s.color ~= "" and hl("OwnSLColor_" .. s.color, esc(s.text)) .. hl("OwnSL", "") or esc(s.text)
end

-- отдых: «⏱ пора отдохнуть», во время перерыва — ☕ и отсчёт (модуль rest)
function C.rest()
  local r = package.loaded["own.modules.rest"]
  if not r then return nil end
  local text, color = r.status()
  if not text then return nil end
  return color and hl("OwnSLColor_" .. color, esc(text)) .. hl("OwnSL", "") or esc(text)
end

-- надписи Go-расширений (c.SetStatus): тесты в фоне и любые свои
function C.ext()
  local e = package.loaded["own.ext"]
  if not e then return nil end
  local out = {}
  for _, s in ipairs(e.status_for(buf())) do
    out[#out + 1] = s.color ~= "" and hl("OwnSLColor_" .. s.color, esc(s.text)) .. hl("OwnSL", "") or esc(s.text)
  end
  return #out > 0 and table.concat(out, "  ") or nil
end

-- тихий режим включён (пробел uq) — чтобы не забыть, что украшения спрятаны
function C.quiet()
  if not vim.g.own_quiet then return nil end
  return "\u{f0a91} тихо"
end

-- колонка экранная (%v): с табами в Go и на пустой строке — как в VS Code, а не номер байта
function C.position() return "%l:%v" end
function C.progress() return "%P" end
function C.time() return "\u{f43a} " .. os.date(o().time_format or "%H:%M") end

-- память и время работы Mac — как сегменты Kali-промпта; считаются в самом nvim (libuv), без внешних команд,
-- память — не чаще раза в 5 с. Занято > 85% — красным: на 8 ГБ это уже своп
local ram_at, ram_pct = 0, nil
function C.ram()
  local now = vim.uv.now()
  if now - ram_at > 5000 then
    ram_at = now
    local total, avail = vim.uv.get_total_memory(), vim.uv.get_available_memory and vim.uv.get_available_memory()
    ram_pct = total > 0 and avail and math.floor((1 - avail / total) * 100 + 0.5) or nil
  end
  if not ram_pct then return nil end
  local text = ("\u{f035b} %d%%%%"):format(ram_pct)
  return ram_pct > 85 and hl("OwnSLColor_red", text) .. hl("OwnSL", "") or text
end

-- скорость печати: символы за последние 30 с → слова в минуту (слово — 5 знаков); не печатаешь — блока нет
local typed = {}
function M.on_char()
  local now = vim.uv.now()
  typed[#typed + 1] = now
  while typed[1] and now - typed[1] > 30000 do table.remove(typed, 1) end
end
function C.wpm()
  local now = vim.uv.now()
  while typed[1] and now - typed[1] > 30000 do table.remove(typed, 1) end
  if #typed < 10 then return nil end
  local span = math.max(now - typed[1], 5000) / 60000 -- минуты; не меньше 5 с, чтобы первые буквы не давали 300 wpm
  return ("\u{f030c} %d wpm"):format(math.floor(#typed / 5 / span + 0.5))
end

function C.uptime()
  local s = math.floor(vim.uv.uptime())
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  return "\u{f0425} " .. (d > 0 and ("%dд %dч"):format(d, h) or ("%dч %dм"):format(h, m))
end

-- музыка: что играет в Яндекс Музыке (или другом плеере) — lua/own/music.lua; клик — пауза, правый — дальше
function C.music()
  local text, playing = require("own.music").text()
  if not text then return nil end
  text = "%@v:lua.OwnMusicClick@" .. esc(text) .. "%X"
  return playing and hl("OwnSLColor_pink", text) .. hl("OwnSL", "") or hl("OwnSLMuted", text) .. hl("OwnSL", "")
end

function C.search()
  if vim.v.hlsearch == 0 then return nil end
  local ok, s = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 50 })
  if not ok or not s.total or s.total == 0 then return nil end
  return ("\u{f002} %d/%d"):format(s.current, s.total)
end

function C.macro()
  local r = vim.fn.reg_recording()
  return r ~= "" and hl("OwnSLColor_red", "\u{f111} @" .. r) .. hl("OwnSL", "") or nil
end

-- кнопки панелей, как в углах status bar Zed: открытая — акцентом, клик — открыть / спрятать
local PANELS = { "tree", "outline", "tests", "db", "|", "terminal", "problems", "|", "ai" }
_G.OwnSLPanel = function(i)
  local name = PANELS[i]
  if name == "ai" then
    local rhs = require("own.actions").get("ai.toggle")
    if type(rhs) == "function" then rhs() end
  elseif name then
    require("own.modules.workspace").toggle(name)
  end
  vim.cmd("redrawstatus")
end
function C.panels()
  local ws = package.loaded["own.modules.workspace"]
  if not ws then return nil end
  local out = {}
  for i, name in ipairs(PANELS) do
    if name == "|" then
      out[#out + 1] = hl("OwnSLFrame", "│")
    else
      local icon = name == "ai" and "\u{2726}" or (ws.views[name] or {}).icon
      if icon then
        local on = name ~= "ai" and ws.is_open(name)
        out[#out + 1] = ("%%%d@v:lua.OwnSLPanel@"):format(i) .. hl(on and "OwnSLActive" or "OwnSLMuted", icon) .. "%X"
      end
    end
  end
  return table.concat(out, hl("OwnSL", " ")) .. hl("OwnSL", "")
end

-- ошибки всего проекта, нули тоже — как в Zed; клик — панель «Проблемы»
_G.OwnSLProblems = function() require("own.modules.workspace").toggle("problems") end
function C.problems()
  local signs = ((vim.diagnostic.config() or {}).signs or {}).text or {}
  local out = {}
  for sev, name in ipairs({ "Error", "Warn" }) do
    local n = #vim.diagnostic.get(nil, { severity = sev })
    local icon = vim.trim(signs[sev] or name:sub(1, 1))
    out[#out + 1] = hl(n > 0 and "OwnSLDiag" .. name or "OwnSLMuted", icon .. " " .. n)
  end
  return "%@v:lua.OwnSLProblems@" .. table.concat(out, hl("OwnSL", " ")) .. "%X" .. hl("OwnSL", "")
end

-- язык словом, как кнопка языка в Zed
local LANGS = { go = "Go", gomod = "Go Mod", gosum = "Go Sum", rust = "Rust", python = "Python", lua = "Lua", sql = "SQL",
  javascript = "JavaScript", typescript = "TypeScript", typescriptreact = "TSX", javascriptreact = "JSX", json = "JSON",
  jsonc = "JSONC", yaml = "YAML", toml = "TOML", markdown = "Markdown", sh = "Shell Script", bash = "Shell Script",
  zsh = "Shell Script", dockerfile = "Dockerfile", html = "HTML", css = "CSS", c = "C", cpp = "C++", make = "Makefile",
  cmake = "CMake", http = "HTTP", proto = "Proto", gitcommit = "Git Commit", text = "Plain Text", [""] = "Plain Text" }
function C.language()
  if vim.bo[buf()].buftype ~= "" then return nil end
  local ft = vim.bo[buf()].filetype
  -- Python — с окружением проекта: «Python .venv»
  local py = ft == "python" and package.loaded["own.modules.python"]
  local venv = py and py.venv_name()
  if venv then return "Python " .. venv end
  return LANGS[ft] or (ft:sub(1, 1):upper() .. ft:sub(2))
end

local function mode_info()
  local m = vim.api.nvim_get_mode().mode:sub(1, 1)
  local names = vim.tbl_extend("force", MODES, o().mode_names or {})
  return names[m] or m, MODE_KIND[m] or "Normal"
end

local function component(name)
  if C[name] then return C[name]() end
  local spec = (o().custom or {})[name]
  if not spec then return nil end
  local text = spec.shell and custom_shell(name, spec) or spec.text
  if not text or text == "" then return nil end
  text = (spec.icon and spec.icon .. " " or "") .. esc(text)
  return spec.color and hl("OwnSLColor_" .. spec.color, text) .. hl("OwnSL", "") or text
end

-- стиль zed: без плашек и рамок, блоки — приглушённым текстом через пробелы, режим — цветной надписью
local function render_zed(opts, text, kind)
  local function side(list)
    local out = {}
    for _, name in ipairs(list) do
      local v = name == "mode" and hl("OwnSLMode" .. kind .. "Text", text) .. hl("OwnSL", "") or component(name)
      if v then out[#out + 1] = v end
    end
    return table.concat(out, hl("OwnSL", "   "))
  end
  local left = side(opts.left or { "panels", "problems", "branch" })
  local right = side(opts.right or { "mode", "position", "language" })
  return hl("OwnSL", "  ") .. left .. hl("OwnSL", "%=") .. right .. hl("OwnSL", "  ")
end

-- крайний блок: режим слева, последний блок справа — цветом режима, в форме стиля
local function edge_block(text, kind, side, style)
  local sep = STYLES[style]
  local mode_hl = "OwnSLMode" .. kind
  if style == "plain" or not sep then return hl("OwnSLMode" .. kind .. "Text", " " .. text .. " ") .. hl("OwnSL", "") end
  local left = side == "left" and sep.lo or sep.ro
  local right = side == "left" and sep.lc or sep.rc
  local out = ""
  if left ~= "" then out = out .. hl(mode_hl .. "Edge", left) end
  out = out .. hl(mode_hl, " " .. text .. " ")
  if right ~= "" then out = out .. hl(mode_hl .. "Edge", right) end
  return out .. hl("OwnSL", "")
end

-- стиль frame: ╰─( РЕЖИМ )─[ блок ]─[ блок ]──── … ────[ блок ]─[ блок ]─╯
-- середину заполняет сам nvim знаком из fillchars (stl = "─", ставит set_fill)
local function render_frame(opts, text, kind)
  local function F(s) return hl("OwnSLFrame", s) end
  local function side(list)
    local out = {}
    for _, name in ipairs(list) do
      if name == "mode" then
        out[#out + 1] = F("─(") .. hl("OwnSLMode" .. kind .. "Text", " " .. text .. " ") .. F(")")
      else
        local v = component(name)
        if v then out[#out + 1] = F("─[ ") .. v .. F(" ]") end
      end
    end
    return table.concat(out)
  end
  local left = side(opts.left or { "mode", "branch", "diagnostics", "file" })
  local right = side(opts.right or { "search", "macro", "lsp", "position", "time" })
  return F(" ╰") .. left .. F("─%=") .. right .. F("─╯ ")
end

-- знак заполнения статусной строки: «─» для рамки, пробел для остальных стилей
local function set_fill(style)
  local ch = style == "frame" and "─" or " "
  vim.opt.fillchars:append({ stl = ch, stlnc = ch })
end

function M.render()
  local opts = o()
  local style = opts.style or "bubbles"
  local text, kind = mode_info()
  if style == "frame" then return render_frame(opts, text, kind) end
  if style == "zed" then return render_zed(opts, text, kind) end
  local function side(list, is_left)
    local parts = {}
    for i, name in ipairs(list) do
      local is_edge = (is_left and i == 1) or (not is_left and i == #list)
      local value = name == "mode" and text or component(name)
      if value then
        if name == "mode" or is_edge then
          parts[#parts + 1] = edge_block(value, kind, is_left and "left" or "right", style)
        else
          parts[#parts + 1] = value
        end
      end
    end
    return table.concat(parts, hl("OwnSL", "  "))
  end
  local left = side(opts.left or { "mode", "branch", "diagnostics", "file" }, true)
  local right = side(opts.right or { "search", "macro", "lsp", "position", "time" }, false)
  return hl("OwnSL", " ") .. left .. hl("OwnSL", "%=") .. right .. hl("OwnSL", " ")
end

function M.setup()
  define()
  set_fill(o().style)
  vim.o.statusline = "%!v:lua.require'own.modules.statusline'.render()"
  local group = vim.api.nvim_create_augroup("own.statusline", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define })
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "DirChanged" }, {
    group = group,
    callback = function(ev)
      local dir = vim.fs.root(ev.buf, ".git")
      if dir then refresh_branch(dir) end
    end,
  })
  vim.api.nvim_create_autocmd("InsertCharPre", { group = group, callback = function() M.on_char() end })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "DirChanged", "ShellCmdPost", "TermLeave" }, {
    group = group, callback = function() M.git_changed() end,
  })
  vim.api.nvim_create_autocmd({ "ModeChanged", "DiagnosticChanged", "LspAttach", "LspDetach", "RecordingEnter", "RecordingLeave" }, {
    group = group,
    callback = function() vim.schedule(function() vim.cmd("redrawstatus") end) end,
  })
  -- часы: раз в минуту
  local timer = vim.uv.new_timer()
  if timer then timer:start(60000 - (os.time() % 60) * 1000, 60000, vim.schedule_wrap(function() vim.cmd("redrawstatus") end)) end
end

function M.reload()
  custom_at = {}
  set_fill(o().style)
  vim.cmd("redrawstatus")
end

return M
