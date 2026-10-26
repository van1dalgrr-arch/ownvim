-- Рабочее место, как в IDE: у каждого окна своё место, раскладка не разваливается и помнится для каждого проекта.
--   слева  — один вид за раз: Проект (дерево) · Структура · Тесты · База; переключатель — над ним, в строке вкладок
--   снизу  — один вид за раз: Терминал · Запуск · Проблемы · Задачи · Вывод тестов; вкладки — в шапке панели
--   режимы — пробел 1…5: Код · Тесты · Отладка · Git · База — экран раскладывается под дело одной клавишей
-- Окна держит edgy.nvim: размеры фиксированы, служебные окна не лезут в середину, закрыл последний файл — вышел.
-- Раздел "modules.workspace":
--   "restore": true — открыть проект как оставил (вид слева, снизу, режим); "default": { "left": "tree" } — новый проект
--   "left_width": 32, "bottom_height": 12
local settings = require("own.settings")
local root = require("own.root")

local M = {}

local function o() return settings.module_opts(settings.current or {}, "workspace") end

-- ── виды ─────────────────────────────────────────────────────────────────────

local function find_win(match)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local b = vim.api.nvim_win_get_buf(w)
      if match(b, w) then return w end
    end
  end
end

local function by_ft(ft) return function(b) return vim.bo[b].filetype == ft end end

local function is_run_term(b) return vim.bo[b].filetype == "snacks_terminal" and vim.b[b].own_run ~= nil end
local function is_shell_term(b) return vim.bo[b].filetype == "snacks_terminal" and vim.b[b].own_run == nil end

local problems -- буфер «Проблемы», ниже

M.views = {
  -- слева
  tree = { pos = "left", icon = "\u{f024b}", title = "Проект", match = by_ft("own_tree"),
    open = function() require("own.tree").open(root.get()) end },
  outline = { pos = "left", icon = "\u{f0645}", title = "Структура", match = by_ft("Outline"),
    open = function() vim.cmd("Outline!") end },
  tests = { pos = "left", icon = "\u{f0668}", title = "Тесты", match = by_ft("neotest-summary"),
    open = function() require("neotest").summary.open() end },
  db = { pos = "left", icon = "\u{f01bc}", title = "База", match = by_ft("dbui"),
    open = function() vim.cmd("DBUI") end },
  -- снизу
  terminal = { pos = "bottom", icon = "\u{ea85}", title = "Терминал", match = is_shell_term,
    open = function(focus)
      local term, created = Snacks.terminal.get(nil, { cwd = root.get(), win = { position = "bottom" } })
      if term and not created then term:show() end
      if term and focus then term:focus() end
    end },
  run = { pos = "bottom", icon = "\u{f040a}", title = "Запуск", match = is_run_term,
    available = function() return require("own.tools.launch").buf() ~= nil end,
    open = function() require("own.tools.launch").show() end },
  problems = { pos = "bottom", icon = "\u{ea6c}", title = "Проблемы", match = by_ft("own_problems"),
    open = function() problems.open() end },
  -- Find Usages из GoLand: использования / кто вызывает / реализации — списком по файлам, живёт внизу, а не всплывает
  usages = { pos = "bottom", icon = "\u{eb36}", title = "Использования", match = by_ft("trouble"),
    available = function() return M.usages_mode ~= nil end,
    open = function(focus) require("trouble").open({ mode = M.usages_mode or "lsp_references", focus = focus }) end },
  tasks = { pos = "bottom", icon = "\u{eab3}", title = "Задачи", match = by_ft("OverseerList"),
    open = function() require("overseer").open({ enter = false, direction = "bottom" }) end },
  test_output = { pos = "bottom", icon = "\u{f0668}", title = "Вывод тестов", match = by_ft("neotest-output-panel"),
    open = function() require("neotest").output_panel.open() end },
}
M.order = {
  left = { "tree", "outline", "tests", "db" },
  bottom = { "terminal", "run", "problems", "usages", "tasks", "test_output" },
}

function M.win(name) local v = M.views[name] return v and find_win(v.match) end
function M.is_open(name) return M.win(name) ~= nil end

-- какой вид сейчас открыт на месте pos
function M.current(pos)
  for _, name in ipairs(M.order[pos]) do
    if M.is_open(name) then return name end
  end
end

local function close_view(name)
  local w = M.win(name)
  if not w then return end
  if name == "tree" then return require("own.tree").close() end
  if name == "tests" then return pcall(function() require("neotest").summary.close() end) end
  if name == "outline" then return pcall(vim.cmd, "OutlineClose") end
  if name == "db" then return pcall(vim.cmd, "DBUIClose") end
  if name == "test_output" then return pcall(function() require("neotest").output_panel.close() end) end
  if name == "usages" then return pcall(function() require("trouble").close() end) end
  pcall(vim.api.nvim_win_close, w, false) -- терминал и запуск — окно прячется, процесс живёт
end

local function code_win()
  -- текущее окно с файлом — оно (символ под курсором нужен «Использованиям»), иначе первое с файлом
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(cur).relative == "" and vim.bo[vim.api.nvim_win_get_buf(cur)].buftype == "" then return cur end
  return find_win(function(b) return vim.bo[b].buftype == "" end)
end

local USAGES = { lsp_references = "Использования", lsp_incoming_calls = "Кто вызывает", lsp_implementations = "Реализации" }

--- Использования символа под курсором в нижней панели (mode — режим trouble: lsp_references, lsp_incoming_calls…)
function M.usages(mode)
  M.usages_mode = mode or "lsp_references"
  M.views.usages.title = USAGES[M.usages_mode] or "Использования"
  if M.is_open("usages") then pcall(function() require("trouble").close() end) end
  M.show("usages", true)
end

--- Показать вид: на его месте остальные прячутся (как вкладки). focus — перейти в него
function M.show(name, focus)
  local v = M.views[name]
  if not v then return end
  for _, other in ipairs(M.order[v.pos]) do
    if other ~= name then close_view(other) end
  end
  local back = vim.api.nvim_get_current_win()
  if not M.is_open(name) then
    local cw = code_win()
    if cw then vim.api.nvim_set_current_win(cw) end
    local ok, err = pcall(v.open, focus ~= false)
    if not ok then return vim.notify(("%s не открылся: %s"):format(v.title, err), vim.log.levels.WARN) end
  end
  local w = M.win(name)
  if focus ~= false and w then
    vim.api.nvim_set_current_win(w)
  elseif vim.api.nvim_win_is_valid(back) then
    vim.api.nvim_set_current_win(back)
    -- терминал сам входит во вставку — в коде она не нужна
    if vim.bo[vim.api.nvim_win_get_buf(back)].buftype ~= "terminal" then
      vim.cmd("stopinsert")
      vim.schedule(function() if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" and vim.bo.buftype ~= "terminal" then vim.cmd("stopinsert") end end)
    end
  end
  M.remember()
  vim.cmd("redrawtabline")
end

function M.hide(pos)
  for _, name in ipairs(M.order[pos]) do close_view(name) end
  M.remember()
  vim.cmd("redrawtabline")
end

--- Открыт — спрятать, иначе показать
function M.toggle(name)
  if M.is_open(name) then
    close_view(name)
    M.remember()
    vim.cmd("redrawtabline")
  else
    M.show(name)
  end
end

--- Спрятать / вернуть всё место pos (пробел j — нижняя панель)
local last = { bottom = "terminal", left = "tree" }
function M.toggle_pos(pos)
  local cur = M.current(pos)
  if cur then
    last[pos] = cur
    M.hide(pos)
  else
    M.show(last[pos] or M.order[pos][1])
  end
end

-- ── «Проблемы» ───────────────────────────────────────────────────────────────

problems = {}
local ICON = { "\u{ea87}", "\u{ea6c}", "\u{ea74}", "\u{ea61}" } -- codicons: Font Awesome Ghostty растягивает в плашки
local SEV_HL = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }

function problems.buf()
  if problems.b and vim.api.nvim_buf_is_valid(problems.b) then return problems.b end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "own_problems"
  vim.bo[buf].bufhidden = "hide"
  vim.keymap.set("n", "<cr>", function()
    local item = (vim.b[buf].own_items or {})[vim.api.nvim_win_get_cursor(0)[1]]
    if not item then return end
    local cw = code_win()
    if cw then vim.api.nvim_set_current_win(cw) end
    vim.cmd.edit(vim.fn.fnameescape(item.file))
    pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, item.col })
  end, { buffer = buf, silent = true, desc = "К проблеме" })
  problems.b = buf
  return buf
end

function problems.render()
  local buf = problems.buf()
  -- одна и та же ошибка от разных источников (gopls пишет её дважды) — одной строкой; ошибки сначала
  local ds, seen = {}, {}
  for _, d in ipairs(vim.diagnostic.get(nil)) do
    local key = d.bufnr .. ":" .. d.lnum .. ":" .. d.message
    if not seen[key] then seen[key] = true; ds[#ds + 1] = d end
  end
  table.sort(ds, function(a, b)
    if a.severity ~= b.severity then return a.severity < b.severity end
    return a.bufnr < b.bufnr or (a.bufnr == b.bufnr and a.lnum < b.lnum)
  end)
  local lines, items = {}, {}
  for _, d in ipairs(ds) do
    local file = vim.api.nvim_buf_get_name(d.bufnr)
    lines[#lines + 1] = (" %s  %s:%d  %s"):format(ICON[d.severity] or "•", vim.fn.fnamemodify(file, ":~:."), d.lnum + 1,
      (d.message:gsub("\n", " ")))
    items[#lines] = { file = file, lnum = d.lnum + 1, col = d.col, severity = d.severity }
  end
  if #lines == 0 then lines = { " \u{eab2}  Проблем нет" } end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].own_items = items
  local ns = vim.api.nvim_create_namespace("own.problems")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row, it in pairs(items) do
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { end_col = 4, hl_group = SEV_HL[it.severity] })
  end
end

function problems.open()
  problems.render()
  vim.cmd("botright " .. (o().bottom_height or 12) .. "split")
  vim.api.nvim_win_set_buf(0, problems.buf())
  local wo = vim.wo[0]
  wo.number, wo.relativenumber, wo.statuscolumn, wo.cursorline = false, false, "", true
end

-- ── шапки: переключатель слева (над деревом, в строке вкладок) и вкладки нижней панели ───────────────

local function errors() return #vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR }) end

_G.OwnWsClick = function(i)
  local name = M.order.left[i] or M.order.bottom[i - 100]
  if not name then return end
  if M.views[name].pos == "left" and M.is_open(name) then return M.toggle(name) end
  M.show(name)
end

--- Над левой панелью (вызывает tabline): значки видов, текущий — подсвечен; клик — переключить
function M.tabline_lead(width)
  local cur = M.current("left")
  local parts, used = {}, 1
  for i, name in ipairs(M.order.left) do
    local v = M.views[name]
    local hl = name == cur and "OwnWsLeadActive" or "OwnWsTab"
    local cell = (" %s "):format(v.icon)
    local w = vim.api.nvim_strwidth(cell)
    if used + w > width - 1 then break end
    parts[#parts + 1] = ("%%%d@v:lua.OwnWsClick@%%#%s#%s%%X"):format(i, hl, cell)
    used = used + w
  end
  return "%#OwnWsTab# " .. table.concat(parts) .. "%#OwnWsTab#" .. (" "):rep(math.max(0, width - used - 1)) .. "%#OwnTabOffset#│"
end

--- Шапка нижней панели: «Терминал · Запуск · Проблемы 3 · Задачи · Вывод тестов», текущая — подчёркнута
function M.bottom_tabs()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or 0
  local parts = {}
  local frames = package.loaded["own.frames"]
  local framed = frames and frames.enabled
  for i, name in ipairs(M.order.bottom) do
    local v = M.views[name]
    if not v.available or v.available() or v.match(buf) then
      local label = v.title
      if name == "problems" then
        local n = errors()
        if n > 0 then label = label .. " " .. n end
      elseif name == "run" then
        local l = require("own.tools.launch")
        label = (l.current_name() or label) .. (l.running() and " ●" or "")
      end
      local hl = v.match(buf) and "OwnWsPanelTabActive" or "OwnWsPanelTab"
      if framed then -- ─[  ТЕРМИНАЛ ]─[  ПРОБЛЕМЫ 3 ]──── (appearance.frames)
        parts[#parts + 1] = ("%%%d@v:lua.OwnWsClick@%%#OwnFrameSide#─[ %%#%s#%s %s%%#OwnFrameSide# ]%%X")
          :format(100 + i, hl, v.icon, vim.fn.toupper(label))
      else
        parts[#parts + 1] = ("%%%d@v:lua.OwnWsClick@%%#%s# %s %s %%X"):format(100 + i, hl, v.icon, vim.fn.toupper(label))
      end
    end
  end
  if framed then
    -- терминал snacks ставит окну свои fillchars — без wbr:─ линия после вкладок обрывалась
    if vim.api.nvim_win_is_valid(win) and not vim.wo[win].fillchars:find("wbr:─", 1, true) then
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) then return end
        local cur = vim.wo[win].fillchars
        vim.wo[win].fillchars = (cur == "" and "" or cur .. ",") .. "wbr:─"
      end)
    end
    return table.concat(parts) .. "%#OwnFrameSide#─%="
  end
  return table.concat(parts, "%#OwnWsPanelTab#  ") .. "%#OwnWsPanelTab#"
end

-- ── режимы ───────────────────────────────────────────────────────────────────

M.modes = {
  { name = "code", title = "Код", icon = "\u{f0169}" },
  { name = "test", title = "Тесты", icon = "\u{f0668}", left = "tests" },
  { name = "debug", title = "Отладка", icon = "\u{ead8}" },
  { name = "git", title = "Git", icon = "\u{e725}" },
  { name = "db", title = "База", icon = "\u{f01bc}", left = "db" },
}
local by_name = {}
for i, m in ipairs(M.modes) do by_name[m.name] = m; m.index = i end

M.mode = "code"
local code_layout -- что было открыто в «Коде» — вернуть, когда вернулся

local function leave(mode)
  if mode == "debug" then pcall(function() require("dapui").close() end) end
  if mode == "git" then pcall(vim.cmd, "DiffviewClose") end
end

--- Перейти в режим (номер или имя); в тот же ещё раз — вернуться в «Код»
function M.set_mode(which)
  local m = type(which) == "number" and M.modes[which] or by_name[which]
  if not m then return end
  if m.name == M.mode and m.name ~= "code" then m = by_name.code end
  local prev = M.mode
  if prev == "code" then code_layout = { left = M.current("left"), bottom = M.current("bottom") } end
  leave(prev)
  M.mode = m.name
  if m.name == "code" then
    local l = code_layout or { left = "tree" }
    if l.left then M.show(l.left, false) else M.hide("left") end
    if l.bottom then M.show(l.bottom, false) else M.hide("bottom") end
  elseif m.name == "debug" then
    -- у отладчика свои панели (переменные, стек, точки, консоль) — остальное убрать, чтобы не теснило
    M.hide("left"); M.hide("bottom")
    local ok, err = pcall(function()
      require("own.modules.debug").prepare()
      require("dapui").open()
    end)
    if not ok then vim.notify("панели отладчика: " .. tostring(err), vim.log.levels.WARN) end
  elseif m.name == "git" then
    M.hide("bottom")
    if not pcall(vim.cmd, "DiffviewOpen") then vim.notify("diffview не открылся", vim.log.levels.WARN) end
  else
    if m.left then M.show(m.left, false) end
    if m.bottom then M.show(m.bottom, false) end
  end
  M.remember()
  vim.cmd("redrawtabline")
  vim.cmd("redrawstatus")
end

function M.mode_info() return by_name[M.mode] end

-- ── память: проект → что было открыто ────────────────────────────────────────

local STATE = vim.fn.stdpath("state") .. "/own-workspace.json"
local restoring = false

-- в памяти: строка вкладок спрашивает конфигурацию запуска на каждой перерисовке — диск там не нужен
local state_cache
local function read_state()
  if state_cache then return state_cache end
  local f = io.open(STATE)
  local t
  if f then
    local ok, v = pcall(vim.json.decode, f:read("*a"))
    f:close()
    t = ok and type(v) == "table" and v or nil
  end
  state_cache = t or {}
  return state_cache
end

-- записать один проект: файл перечитывается — второй открытый ownvim мог записать свои проекты
local function save_entry(dir, entry)
  state_cache = nil
  local all = read_state()
  all[dir] = entry
  local f = io.open(STATE, "w")
  if not f then return end
  f:write(vim.json.encode(all))
  f:close()
end

function M.project_state(dir)
  return read_state()[dir or root.get()] or {}
end

function M.set_project(key, value)
  local dir = root.get()
  local entry = vim.deepcopy(read_state()[dir] or {})
  entry[key] = value
  save_entry(dir, entry)
end

local pending, quitting
function M.remember_now()
  if restoring or quitting then return end
  local dir = root.get()
  local s = vim.deepcopy(read_state()[dir] or {})
  s.left, s.bottom = M.current("left") or false, M.current("bottom") or false
  if s.bottom == "run" then s.bottom = "terminal" end -- запуск сам не перезапускается
  if s.bottom == "usages" then s.bottom = "problems" end -- использования — от символа под курсором, при старте его нет
  s.mode = (M.mode == "test" or M.mode == "db") and M.mode or "code"
  save_entry(dir, s)
end

function M.remember()
  if restoring or quitting then return end
  -- после переключения окна стоят не сразу — записать, когда всё улеглось
  if pending then return end
  pending = true
  vim.defer_fn(function()
    pending = false
    if vim.v.exiting ~= vim.NIL then return end
    M.remember_now()
  end, 150)
end

--- Выход: запомнить раскладку и больше её не трогать (панели закрываются по одной — это не «спрятал»)
function M.quit()
  M.remember_now()
  quitting = true
end

-- первый открытый файл проекта — разложить, как было (или как в "default")
local restored = {}
local function restore()
  if o().restore == false then return end
  local dir = root.get()
  if restored[dir] then return end
  restored[dir] = true
  local s = read_state()[dir]
  local def = o().default or { left = "tree" }
  local left = s and s.left
  local bottom = s and s.bottom
  if left == nil then left = def.left end
  if bottom == nil then bottom = def.bottom end
  restoring = true
  -- не сразу: файл, открытый со стартового экрана, приходит, пока snacks ещё убирает свой буфер (E937)
  vim.defer_fn(function()
    if s and s.mode and s.mode ~= "code" and by_name[s.mode] then
      M.mode = "code"
      M.set_mode(s.mode)
    else
      if left and M.views[left] then M.show(left, false) end
      if bottom and M.views[bottom] then M.show(bottom, false) end
    end
    restoring = false
  end, 30)
end

-- ── edgy ─────────────────────────────────────────────────────────────────────

local function define()
  local color = require("own.theme.color")
  local function c(g, a) local v = vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] return v and ("#%06x"):format(v) end
  local bg = c("Normal", "bg")
  local fg = c("Normal") or "#cccccc"
  local accent = c("OwnIconAccent") or c("Title") or "#bb9af7"
  local muted = c("Comment") or "#888888"
  -- боковые панели — на тон темнее кода (у прозрачных тем — тоже прозрачные)
  -- у почти чёрных тем (onedark_dark, oxocarbon) темнее некуда — тогда панели на тон светлее
  local side = bg and (color.luminance(bg) < 0.01 and color.blend("#ffffff", bg, 0.045) or color.blend("#000000", bg, 0.18)) or nil
  -- строка вкладок — того же цвета, что панели: каркас (вверху, слева, снизу) один, код — светлее, в фокусе
  if side then vim.api.nvim_set_hl(0, "TabLineFill", { bg = side }) end
  local fill = side or c("TabLineFill", "bg") or c("StatusLine", "bg")
  vim.api.nvim_set_hl(0, "OwnSide", { bg = side })
  vim.api.nvim_set_hl(0, "OwnSideCursor", { bg = side and color.blend(fg, side, 0.07) or nil })
  vim.api.nvim_set_hl(0, "OwnSideTitle", { fg = muted, bg = side, bold = true })
  vim.api.nvim_set_hl(0, "OwnFrameSide", { fg = muted, bg = side }) -- линии ─[ ПРОЕКТ ]── (appearance.frames)
  vim.api.nvim_set_hl(0, "OwnWsTab", { fg = muted, bg = fill })
  vim.api.nvim_set_hl(0, "OwnWsTabActive", { fg = fg, bg = fill, bold = true, underline = true, sp = accent })
  vim.api.nvim_set_hl(0, "EdgyNormal", { link = "OwnSide" })
  vim.api.nvim_set_hl(0, "EdgyWinBar", { link = "OwnSideTitle" })
  vim.api.nvim_set_hl(0, "EdgyTitle", { link = "OwnSideTitle" })
  vim.api.nvim_set_hl(0, "EdgyIcon", { fg = accent, bg = side })
  vim.api.nvim_set_hl(0, "EdgyIconActive", { fg = accent, bg = side })
  -- вкладки нижней панели — на фоне панели
  vim.api.nvim_set_hl(0, "OwnWsPanelTab", { fg = muted, bg = side })
  vim.api.nvim_set_hl(0, "OwnWsPanelTabActive", { fg = fg, bg = side, bold = true, underline = true, sp = accent })
  vim.api.nvim_set_hl(0, "OwnWsLeadActive", { fg = accent, bg = fill, underline = true, sp = accent })
  -- окна поверх кода — одним стилем с каркасом, у любой темы
  if side and ((settings.current or {}).appearance or {}).unified_floats ~= false then
    local border = color.blend(accent, side, 0.42)
    local sel = color.blend(accent, side, 0.2)
    local hl = vim.api.nvim_set_hl
    hl(0, "NormalFloat", { fg = fg, bg = side })
    hl(0, "FloatBorder", { fg = border, bg = side })
    hl(0, "FloatTitle", { fg = accent, bg = side, bold = true })
    hl(0, "FloatFooter", { fg = muted, bg = side })
    hl(0, "Pmenu", { fg = fg, bg = side })
    hl(0, "PmenuSel", { bg = sel, bold = true })
    hl(0, "PmenuKind", { fg = muted, bg = side })
    hl(0, "PmenuExtra", { fg = muted, bg = side })
    hl(0, "PmenuMatch", { fg = accent, bold = true })
    hl(0, "PmenuSbar", { bg = side })
    hl(0, "PmenuThumb", { bg = border })
    for _, g in ipairs({ "BlinkCmpMenu", "BlinkCmpDoc", "BlinkCmpSignatureHelp", "SnacksPicker", "SnacksPickerInput",
      "SnacksPickerList", "SnacksPickerPreview", "WhichKeyNormal", "SnacksNotifierHistory", "SnacksInputNormal" }) do
      hl(0, g, { link = "NormalFloat" })
    end
    for _, g in ipairs({ "BlinkCmpMenuBorder", "BlinkCmpDocBorder", "BlinkCmpSignatureHelpBorder", "SnacksPickerBorder",
      "SnacksPickerInputBorder", "SnacksPickerListBorder", "SnacksPickerPreviewBorder", "WhichKeyBorder", "SnacksInputBorder" }) do
      hl(0, g, { link = "FloatBorder" })
    end
    for _, g in ipairs({ "SnacksPickerTitle", "SnacksPickerInputTitle", "SnacksPickerPreviewTitle", "SnacksPickerListTitle",
      "WhichKeyTitle", "SnacksInputTitle" }) do
      hl(0, g, { link = "FloatTitle" })
    end
    hl(0, "BlinkCmpMenuSelection", { link = "PmenuSel" })
    hl(0, "BlinkCmpLabelMatch", { fg = accent, bold = true })
    hl(0, "BlinkCmpLabelDescription", { fg = muted })
    hl(0, "BlinkCmpKind", { fg = muted })
    hl(0, "SnacksPickerListCursorLine", { bg = sel })
    hl(0, "SnacksPickerMatch", { fg = accent, bold = true })
    hl(0, "SnacksPickerPrompt", { fg = accent })
    hl(0, "SnacksPickerDir", { fg = muted })
  end
  -- вкладки и запуск красятся от TabLineFill — перекрасить после неё
  local tl = package.loaded["own.modules.tabline"]
  if tl and tl.define then tl.define() end
  local l = package.loaded["own.tools.launch"]
  if l and l.define then l.define() end
end

local function edgy_opts()
  local opts = o()
  local tabs = "%{%v:lua.require'own.modules.workspace'.bottom_tabs()%}"
  local function left(name)
    local v = M.views[name]
    -- ─[ ПРОЕКТ ]──── рамкой (appearance.frames) или просто ПРОЕКТ; функция — чтобы переключалось на лету
    local function title()
      local t = vim.fn.toupper(v.title)
      local frames = require("own.frames")
      return frames.enabled and frames.panel(t) or t
    end
    return { title = title, filter = function(b) return v.match(b) end }
  end
  local function bottom(name)
    local v = M.views[name]
    return { title = tabs, filter = function(b) return v.match(b) end }
  end
  local spec = {
    animate = { enabled = false },
    -- выход по :q из последнего файла — свой (QuitPre ниже): edgy закрывал ownvim посреди загрузки сессии,
    -- когда на миг оставались одни панели
    exit_when_last = false,
    close_when_all_hidden = true,
    icons = { closed = " \u{eab6}", open = " \u{eab4}" },
    wo = {
      winbar = true,
      winfixwidth = true,
      winfixheight = false,
      winhighlight = "Normal:OwnSide,NormalNC:OwnSide,EndOfBuffer:OwnSide,SignColumn:OwnSide,WinBar:OwnSideTitle,WinBarNC:OwnSideTitle,CursorLine:OwnSideCursor",
      spell = false,
      signcolumn = "no",
    },
    options = {
      left = { size = opts.left_width or 32 },
      bottom = { size = opts.bottom_height or 12 },
    },
    left = {}, bottom = {},
    keys = {
      -- edgy по умолчанию занимает q и ctrl-q в панелях; q закрывает — оставить, остальное — своё
      ["<c-q>"] = false,
    },
  }
  local fts = {
    tree = "own_tree", outline = "Outline", tests = "neotest-summary", db = "dbui",
    terminal = "snacks_terminal", run = "snacks_terminal", problems = "own_problems", usages = "trouble", tasks = "OverseerList",
    test_output = "neotest-output-panel",
  }
  for _, name in ipairs(M.order.left) do
    local s = left(name); s.ft = fts[name]; spec.left[#spec.left + 1] = s
  end
  for _, name in ipairs(M.order.bottom) do
    local s = bottom(name); s.ft = fts[name]
    if fts[name] == "snacks_terminal" then
      -- только терминалы снизу, а не плавающие (lazygit, Claude)
      local match = M.views[name].match
      s.filter = function(b, w)
        local sw = vim.w[w].snacks_win
        return match(b) and sw and sw.position == "bottom" and sw.relative == "editor"
      end
    end
    spec.bottom[#spec.bottom + 1] = s
  end
  -- справка и quickfix — тоже снизу, на своём месте
  spec.bottom[#spec.bottom + 1] = { ft = "qf", title = "СПИСОК" }
  spec.bottom[#spec.bottom + 1] = { ft = "help", title = "СПРАВКА", size = { height = 20 },
    filter = function(b) return vim.bo[b].buftype == "help" end }
  return spec
end

function M.plugins()
  return {
    {
      "folke/edgy.nvim",
      event = "VeryLazy",
      opts = edgy_opts,
    },
    {
      "folke/trouble.nvim",
      cmd = "Trouble",
      opts = {
        focus = true,
        auto_preview = false,
        warn_no_results = false,
        open_no_results = true,
        win = { type = "split", position = "bottom", size = (o().bottom_height or 12) },
        -- codicons: значки Font Awesome Ghostty растягивает
        icons = { indent = { fold_open = "\u{eab4} ", fold_closed = "\u{eab6} " } },
      },
    },
  }
end

function M.setup()
  define()
  require("own.tools.launch").setup()
  local group = vim.api.nvim_create_augroup("own.workspace", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function()
      if problems.b and vim.api.nvim_buf_is_valid(problems.b) then vim.schedule(problems.render) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then return end
      if vim.bo[ev.buf].filetype == "gitcommit" or vim.bo[ev.buf].filetype == "gitrebase" then return end
      restore()
    end,
  })
  -- сессия вернулась — разложить её проект
  vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = function() restored = {}; restore() end })
  -- :q в последнем окне с файлом — выйти из ownvim, а не остаться с одними панелями
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local cur = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(cur)
      -- несохранённый файл: :q спросит или откажет — панели пусть стоят
      if vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then return end
      local panels = {}
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= cur and vim.api.nvim_win_get_config(w).relative == "" then
          if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then return end -- есть ещё файл — обычный :q
          panels[#panels + 1] = w
        end
      end
      if #panels == 0 or #vim.api.nvim_list_tabpages() > 1 then return end
      M.quit()
      for _, w in ipairs(panels) do pcall(vim.api.nvim_win_close, w, true) end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.quit })
  -- окна закрыли руками (q) — запомнить и это
  vim.api.nvim_create_autocmd("WinClosed", { group = group, callback = function() vim.schedule(M.remember) end })
  vim.api.nvim_create_user_command("Mode", function(a) M.set_mode(a.args ~= "" and a.args or "code") end, {
    nargs = "?",
    complete = function() return vim.tbl_map(function(m) return m.name end, M.modes) end,
    desc = "Режим рабочего места: code, test, debug, git, db",
  })
end

function M.reload() define() end

return M
