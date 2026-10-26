-- Рамки в духе промпта dotfiles и Kali: ╰─( РЕЖИМ )─[ блок ]─ у статусной строки, и так же — всё остальное.
--   окна поверх кода (поиск, K, which-key, уведомления, плагины) — заголовок в скобках: ╭──[ Найти файл ]──╮
--   панели слева — линией: ─[ ПРОЕКТ ]──────── ; строка файла над кодом — ─[ main.go › main ]────────
--   номер текущей строки — со стрелкой, как курсор промпта: ❯ 10
--   рамка живёт режимом: в ВСТАВКЕ все линии разом — цветом режима, в ВЫДЕЛЕНИИ — своим, в ОБЫЧНОМ — тихие
--   сохранил — рамка на миг вспыхивает акцентом; линия отступа блока под курсором — полутоном акцента
-- "appearance": { "frames": false } — как было; "frames_by_mode": false — линии всегда тихие; "save_flash": false.
-- Цвета — из темы: линии цветом комментариев, стрелка и режимы — цветами режимов статусной строки.
local settings = require("own.settings")

local M = {}

function M.on() return ((settings.current or {}).appearance or {}).frames ~= false end

-- ── цвета ────────────────────────────────────────────────────────────────────

local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end

-- линии рамки, которые живут режимом и вспыхивают при сохранении
local LINES = { "OwnFrame", "OwnFrameSide", "OwnSLFrame" } -- строка файла, панели, статусная строка

function M.define()
  local frame = c("Comment") or c("NonText")
  local accent = c("OwnIconAccent") or c("Title") or c("Statement")
  vim.api.nvim_set_hl(0, "OwnFrame", { fg = frame, bg = c("Normal", "bg") })
  vim.api.nvim_set_hl(0, "OwnFrameCursor", { fg = accent, bg = c("CursorLineNr", "bg") or c("CursorLine", "bg"), bold = true })
  -- линия отступа блока, где стоит курсор (snacks scope), — полутоном акцента: видно, где кончается функция или if
  if M.enabled and accent then
    local color = require("own.theme.color")
    local hex = function(v) return ("#%06x"):format(v) end
    vim.api.nvim_set_hl(0, "SnacksIndentScope", { fg = color.blend(hex(accent), hex(c("Normal", "bg") or 0), 0.6) })
  end
  M.paint()
end

-- вспышка при сохранении: все линии рамки на миг — акцентом, потом обратно цветом режима
function M.flash()
  if not M.enabled or ((settings.current or {}).appearance or {}).save_flash == false then return end
  local accent = c("OwnIconAccent") or c("Title") or c("Statement")
  for _, g in ipairs(LINES) do
    local h = vim.api.nvim_get_hl(0, { name = g, link = false })
    if next(h) then h.fg = accent; vim.api.nvim_set_hl(0, g, h) end
  end
  M.painted = nil
  vim.cmd("redrawstatus!")
  vim.defer_fn(function() M.paint(); vim.cmd("redrawstatus!") end, 200)
end

-- ── рамка цветом режима ─────────────────────────────────────────────────────

-- те же виды, что у статусной строки (её группы OwnSLMode<вид> — источник цвета); командную строку не трогаем:
-- «:» и «/» на миг — рамка мигала бы на каждом поиске
local KIND = { i = "Insert", v = "Visual", V = "Visual", ["\22"] = "Visual", s = "Visual", S = "Visual", ["\19"] = "Visual",
  R = "Replace", t = "Terminal" }

function M.paint()
  local m = vim.api.nvim_get_mode().mode:sub(1, 1)
  if m == "c" or m == "r" then return end
  local by_mode = ((settings.current or {}).appearance or {}).frames_by_mode ~= false
  local kind = M.enabled and by_mode and KIND[m]
  local fg = kind and c("OwnSLMode" .. kind, "bg") or c("Comment") or c("NonText")
  if fg == M.painted then return end
  M.painted = fg
  for _, g in ipairs(LINES) do
    local h = vim.api.nvim_get_hl(0, { name = g, link = false })
    if next(h) then h.fg = fg; vim.api.nvim_set_hl(0, g, h) end
  end
  -- стрелка ❯ у номера строки — тоже цветом режима, в обычном — акцентом
  local arrow = vim.api.nvim_get_hl(0, { name = "OwnFrameCursor", link = false })
  arrow.fg = kind and fg or c("OwnIconAccent") or c("Title") or c("Statement")
  vim.api.nvim_set_hl(0, "OwnFrameCursor", arrow)
end

-- ── заголовки окон поверх кода: [ заголовок ] ─────────────────────────────────

-- строка или куски { {текст, группа}, … } → { {"[ ", FloatBorder}, …, {" ]", FloatBorder} }.
-- Скобки — группой FloatBorder: у уведомлений она своя у каждого уровня (ошибка — красная), скобки красятся так же
local function wrap(title)
  local chunks
  if type(title) == "string" then
    chunks = { { title, "FloatTitle" } }
  elseif type(title) == "table" and #title > 0 then
    if type(title[1]) == "table" and title[1][1] == "[ " then return title end -- уже в скобках
    chunks = vim.deepcopy(title)
  else
    return title
  end
  for i, ch in ipairs(chunks) do
    if type(ch) == "string" then chunks[i] = { ch, "FloatTitle" } end
  end
  chunks[1][1] = chunks[1][1]:gsub("^%s+", "")
  chunks[#chunks][1] = chunks[#chunks][1]:gsub("%s+$", "")
  local text = table.concat(vim.tbl_map(function(ch) return ch[1] end, chunks))
  if text == "" or text:match("^%[") then return title end
  table.insert(chunks, 1, { "[ ", "FloatBorder" })
  chunks[#chunks + 1] = { " ]", "FloatBorder" }
  return chunks
end

local function fix(cfg)
  if not M.enabled or type(cfg) ~= "table" or cfg.title == nil or cfg.border == "none" then return cfg end
  cfg = vim.deepcopy(cfg)
  cfg.title = wrap(cfg.title)
  return cfg
end

-- все окна открываются через эти две функции — и свои, и любого плагина: подменить их один раз
local function hook()
  if M.hooked then return end
  M.hooked = true
  local open, set = vim.api.nvim_open_win, vim.api.nvim_win_set_config
  vim.api.nvim_open_win = function(buf, enter, cfg) return open(buf, enter, fix(cfg)) end
  vim.api.nvim_win_set_config = function(win, cfg) return set(win, fix(cfg)) end
end

-- ── линии: панели и строка файла ─────────────────────────────────────────────

--- заголовок панели слева: ─[ ПРОЕКТ ]──── (середину дорисовывает nvim знаком wbr из fillchars)
function M.panel(title)
  return "%#OwnFrameSide#─[ %#OwnSideTitle#" .. title .. "%#OwnFrameSide# ]─%="
end

--- строка над кодом: ─[ main.go › main ]────
function M.crumbs(inner)
  return "%#OwnFrame#─[ " .. inner .. "%#OwnFrame# ]─%=─"
end

-- ── номер текущей строки: ❯ 10 ───────────────────────────────────────────────

function M.statuscolumn()
  local s = require("snacks.statuscolumn").get()
  if M.enabled and vim.v.relnum == 0 and vim.v.virtnum == 0 then
    s = s:gsub("%%=(%d+) ", "%%=%%#OwnFrameCursor#❯ %%#CursorLineNr#%1 ", 1)
  end
  return s
end

local SNACKS_COL = [[%!v:lua.require'snacks.statuscolumn'.get()]]
local OWN_COL = [[%!v:lua.require'own.frames'.statuscolumn()]]

local function apply()
  M.enabled = M.on()
  if M.enabled then
    hook()
    vim.opt.fillchars:append({ wbr = "─" })
    if vim.o.statuscolumn == SNACKS_COL then vim.o.statuscolumn = OWN_COL end
  else
    vim.opt.fillchars:append({ wbr = " " })
    if vim.o.statuscolumn == OWN_COL then vim.o.statuscolumn = SNACKS_COL end
  end
  M.painted = nil
  M.define()
  vim.cmd("redraw!")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.frames", { clear = true })
  -- после темы группы линий пересоздаются тихими — запомненный цвет сбросить и покрасить заново
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() M.painted = nil; vim.schedule(M.define) end })
  vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = M.paint })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, callback = function() M.flash() end })
  apply()
end

M.reload = apply

return M
