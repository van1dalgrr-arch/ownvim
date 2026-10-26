-- Рамки в духе промпта dotfiles и Kali: ╰─( РЕЖИМ )─[ блок ]─ у статусной строки, и так же — всё остальное.
--   окна поверх кода (поиск, K, which-key, уведомления, плагины) — заголовок в скобках: ╭──[ Найти файл ]──╮
--   панели слева — линией: ─[ ПРОЕКТ ]──────── ; строка файла над кодом — ─[ main.go › main ]────────
--   номер текущей строки — со стрелкой, как курсор промпта: ❯ 10
--   рамка живёт режимом: в ВСТАВКЕ все линии разом — цветом режима, в ВЫДЕЛЕНИИ — своим, в ОБЫЧНОМ — тихие
--   сохранил — рамка на миг вспыхивает: зелёным — ошибок нет, красным — есть; линия отступа блока под курсором — полутоном акцента
--   командная строка — по центру в рамке; свёрнутый блок — ╶─[ func main() · 24 строки ]──; номера дальше от курсора —
--   бледнее; прыгнул (gd, поиск, ctrl-o) — строка на миг подсвечена акцентом
-- "appearance": { "frames": false } — как было; "frames_by_mode": false — линии всегда тихие; "save_flash": false;
--   "cmdline": "bottom" — командная строка внизу; "number_fade": false; "jump_flash": false
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
  -- номера: ступени затухания от цвета номеров к фону; вспышка прыжка — три шага от акцента к фону
  local color = require("own.theme.color")
  local hx = function(v) return v and ("#%06x"):format(v) or nil end
  local bg = hx(c("Normal", "bg")) or "#000000"
  local nr = hx(c("LineNr")) or hx(frame) or "#888888"
  vim.api.nvim_set_hl(0, "OwnLineNrNear", { fg = color.blend(hx(c("Normal")) or "#cccccc", nr, 0.45) })
  for i, k in ipairs({ 0.6, 0.35 }) do
    vim.api.nvim_set_hl(0, "OwnLineNrFade" .. i, { fg = color.blend(nr, bg, k) })
  end
  for i, k in ipairs({ 0.32, 0.2, 0.1 }) do
    vim.api.nvim_set_hl(0, "OwnJump" .. i, { bg = color.blend(hx(accent) or "#bb9af7", bg, k) })
  end
  vim.api.nvim_set_hl(0, "OwnFoldTitle", { fg = c("Normal"), bold = true })
  -- линия отступа блока, где стоит курсор (snacks scope), — полутоном акцента: видно, где кончается функция или if
  if M.enabled and accent then
    local color = require("own.theme.color")
    local hex = function(v) return ("#%06x"):format(v) end
    vim.api.nvim_set_hl(0, "SnacksIndentScope", { fg = color.blend(hex(accent), hex(c("Normal", "bg") or 0), 0.6) })
  end
  M.paint()
end

-- вспышка при сохранении: зелёная — ошибок в файле нет, красная — есть; потом обратно цветом режима.
-- Серверу нужно мгновение пересчитать ошибки после записи — вспышка чуть позже сохранения
function M.flash(buf)
  if not M.enabled or ((settings.current or {}).appearance or {}).save_flash == false then return end
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local errors = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  local accent = errors > 0 and (c("DiagnosticError") or c("Error")) or (c("DiagnosticOk") or c("String"))
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

-- номера дальше от курсора — бледнее (appearance.number_fade): ближние 3 строки как есть, потом три ступени
-- у курсора — ярче обычного, дальше — как тема, ещё дальше — бледнее (у многих тем номера и так тёмные — тускнеть некуда)
local FADE = { { 3, "OwnLineNrNear" }, { 8, nil }, { 16, "OwnLineNrFade1" }, { math.huge, "OwnLineNrFade2" } }

function M.statuscolumn()
  local s = require("snacks.statuscolumn").get()
  if not M.enabled or vim.v.virtnum ~= 0 then return s end
  local rel = vim.v.relnum
  if rel == 0 then
    return (s:gsub("%%=(%d+) ", "%%=%%#OwnFrameCursor#❯ %%#CursorLineNr#%1 ", 1))
  end
  if M.fade then
    for _, step in ipairs(FADE) do
      if rel <= step[1] then
        return step[2] and (s:gsub("%%=(%d+) ", "%%=%%#" .. step[2] .. "#%1 ", 1)) or s
      end
    end
  end
  return s
end

-- ── свёрнутый блок: ╶─[ func main() · 24 строки ]────── ──────────────────────────────

local function plural(n, one, few, many)
  local m10, m100 = n % 10, n % 100
  if m10 == 1 and m100 ~= 11 then return one end
  if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then return few end
  return many
end

function M.foldtext()
  local s, e = vim.v.foldstart, vim.v.foldend
  local line = vim.fn.getline(s):gsub("^%s+", ""):gsub("%s*[{(%[]%s*$", "")
  local n = e - s + 1
  return {
    { (" "):rep(vim.fn.indent(s)), "Folded" },
    { "╶─[ ", "OwnFrame" },
    { line, "OwnFoldTitle" },
    { (" · %d %s"):format(n, plural(n, "строка", "строки", "строк")), "Comment" },
    { " ]─", "OwnFrame" },
  }
end

-- ── вспышка после прыжка: строка, куда попал, на миг подсвечена акцентом ────────────────

local jump_ns = vim.api.nvim_create_namespace("own.frames.jump")
local last = {}

function M.jumped()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local prev = last[win]
  last[win] = { buf = buf, row = row }
  if not prev or vim.bo[buf].buftype ~= "" or vim.api.nvim_win_get_config(win).relative ~= "" then return end
  if prev.buf == buf and math.abs(prev.row - row) < (M.jump_lines or 8) then return end
  local id
  for step = 1, 4 do
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if id then pcall(vim.api.nvim_buf_del_extmark, buf, jump_ns, id) end
      if step < 4 then
        local r = math.min(row, vim.api.nvim_buf_line_count(buf)) - 1
        id = vim.api.nvim_buf_set_extmark(buf, jump_ns, r, 0, { line_hl_group = "OwnJump" .. step, priority = 300 })
      end
    end, (step - 1) * 90)
  end
end

-- ── командная строка по центру в рамке: ╭─[  команда ]──╮ (ui2 из nvim 0.12) ─────────────────────────

-- окно ui2 одно на команды и сообщения: на время ввода — в центр, после — обратно вниз как было
local CMD = { [":"] = { "\u{f120}", "команда" }, ["/"] = { "\u{f002}", "поиск ↓" }, ["?"] = { "\u{f002}", "поиск ↑" } }
local cmd_saved

local function ui2_cmd()
  local ok, ui = pcall(require, "vim._core.ui2")
  local win = ok and ui.wins and ui.wins.cmd
  return win and vim.api.nvim_win_is_valid(win) and win or nil
end

function M.cmdline_enter()
  local spec = CMD[vim.fn.getcmdtype()]
  local win = ui2_cmd()
  if not (M.enabled and spec and win) or ((settings.current or {}).appearance or {}).cmdline == "bottom" then return end
  cmd_saved = cmd_saved or vim.api.nvim_win_get_config(win)
  local W = math.min(72, vim.o.columns - 8)
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor", row = math.floor(vim.o.lines * 0.22), col = math.floor((vim.o.columns - W) / 2),
    width = W, border = "rounded", title = " " .. spec[1] .. " " .. spec[2] .. " ", title_pos = "center",
  })
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
end

function M.cmdline_leave()
  if not cmd_saved then return end
  local cfg = cmd_saved
  cmd_saved = nil
  vim.schedule(function()
    local win = ui2_cmd()
    if not win then return end
    pcall(vim.api.nvim_win_set_config, win, {
      relative = cfg.relative, row = cfg.row, col = cfg.col, width = cfg.width, anchor = cfg.anchor,
      border = "none", title = "",
    })
    vim.wo[win].winhighlight = ""
  end)
end

-- ── меню дополнения: ❯ у выбранного пункта ──────────────────────────────────────

-- blink при выборе только двигает курсор в окне меню — стрелку ставим меткой поверх левого отступа строки
function M.blink()
  local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")
  if not ok or menu.own_pointer then return end
  menu.own_pointer = true
  local ns = vim.api.nvim_create_namespace("own.frames.cmp")
  local orig = menu.set_selected_item_idx
  menu.set_selected_item_idx = function(idx)
    orig(idx)
    local buf = menu.win:get_buf()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if M.enabled and idx and idx <= vim.api.nvim_buf_line_count(buf) then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, idx - 1, 0,
        { virt_text = { { "❯", "OwnFrameCursor" } }, virt_text_pos = "overlay", priority = 300 })
    end
  end
end

local SNACKS_COL = [[%!v:lua.require'snacks.statuscolumn'.get()]]
local OWN_COL = [[%!v:lua.require'own.frames'.statuscolumn()]]

local function apply()
  M.enabled = M.on()
  local ap = (settings.current or {}).appearance or {}
  M.fade = ap.number_fade ~= false
  if M.enabled then
    hook()
    vim.opt.fillchars:append({ wbr = "─", fold = "─" })
    vim.o.foldtext = "v:lua.require'own.frames'.foldtext()"
    if vim.o.statuscolumn == SNACKS_COL then vim.o.statuscolumn = OWN_COL end
  else
    vim.opt.fillchars:append({ wbr = " ", fold = " " })
    if vim.o.foldtext == "v:lua.require'own.frames'.foldtext()" then vim.o.foldtext = "" end
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
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group, callback = function(ev) vim.defer_fn(function() M.flash(ev.buf) end, 350) end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
    group = group,
    callback = function()
      if M.enabled and ((settings.current or {}).appearance or {}).jump_flash ~= false then M.jumped() end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", { group = group, callback = function() M.cmdline_enter() end })
  vim.api.nvim_create_autocmd("CmdlineLeave", { group = group, callback = function() M.cmdline_leave() end })
  apply()
end

M.reload = apply

return M
