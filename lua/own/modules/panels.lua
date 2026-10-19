-- Панели, как в VS Code.
-- Полоса значков слева (Activity Bar): клик или пробел b 1…9 — открыть вид: файлы, поиск, git, тесты, отладка, плагины,
-- настройки. Нижняя панель (Panel): вкладки «Терминал · Проблемы · Задачи», клик по вкладке — переключить;
-- пробел j — показать/спрятать, пробел j t/p/o — сразу на вкладку. Настройки модуля:
--   "activity_bar": { "enabled": true, "items": ["files", "search", "git", "tests", "debug", "plugins", "settings"] }
--   "bottom": { "height": 12, "tabs": ["terminal", "problems", "tasks"] }
local settings = require("own.settings")

local M = {}

local function o() return settings.module_opts(settings.current or {}, "panels") end

-- ── полоса значков ───────────────────────────────────────────────────────────

local ITEMS = {
  files = { icon = "\u{f07b}", desc = "Файлы", run = function() require("own.actions").list.explorer[1]() end },
  search = { icon = "\u{f002}", desc = "Поиск по проекту", run = function() require("own.actions").list.grep[1]() end },
  git = { icon = "\u{e725}", desc = "Git (lazygit)", run = function() require("own.actions").list.lazygit[1]() end },
  tests = { icon = "\u{f0668}", desc = "Тесты", run = function() require("neotest").summary.toggle() end },
  debug = { icon = "\u{f188}", desc = "Отладка", run = function() require("own.actions").list["debug.ui"][1]() end },
  plugins = { icon = "\u{f12e}", desc = "Плагины", run = function() require("own.store").open() end },
  database = { icon = "\u{f1c0}", desc = "База данных", run = function() vim.cmd("DBUIToggle") end },
  claude = { icon = "\u{f06a9}", desc = "Claude", run = function() require("own.modules.ai").toggle() end },
  settings = { icon = "\u{f013}", desc = "Настройки", run = function() require("own.settings").open() end },
}

local bar = { buf = nil, win = nil, rows = {} }

local function bar_items()
  local list = {}
  for _, name in ipairs((o().activity_bar or {}).items or { "files", "search", "git", "tests", "debug", "plugins", "settings" }) do
    if ITEMS[name] then list[#list + 1] = name end
  end
  return list
end

local function bar_render()
  if not (bar.buf and vim.api.nvim_buf_is_valid(bar.buf)) then return end
  local lines, rows = { "" }, {}
  local items = bar_items()
  for i, name in ipairs(items) do
    if name == "settings" then
      -- настройки — внизу, как шестерёнка в VS Code
      local h = bar.win and vim.api.nvim_win_is_valid(bar.win) and vim.api.nvim_win_get_height(bar.win) or 30
      while #lines < h - 2 do lines[#lines + 1] = "" end
    end
    lines[#lines + 1] = " " .. ITEMS[name].icon
    rows[#lines] = name
    if i < #items then lines[#lines + 1] = "" end
  end
  vim.bo[bar.buf].modifiable = true
  vim.api.nvim_buf_set_lines(bar.buf, 0, -1, false, lines)
  vim.bo[bar.buf].modifiable = false
  bar.rows = rows
  local ns = vim.api.nvim_create_namespace("own.activity_bar")
  vim.api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
  local tree_open = package.loaded["own.tree"] and require("own.tree").is_open()
  for row, name in pairs(rows) do
    local active = name == "files" and tree_open
    vim.api.nvim_buf_set_extmark(bar.buf, ns, row - 1, 0, { line_hl_group = active and "OwnBarActive" or "OwnBar" })
  end
end

local function bar_click()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local name = bar.rows[row]
  if not name then return end
  -- действие — в окне с кодом, а не в самой полосе
  vim.cmd("wincmd p")
  ITEMS[name].run()
  vim.schedule(bar_render)
end

local function bar_open()
  if bar.win and vim.api.nvim_win_is_valid(bar.win) then return end
  if not (bar.buf and vim.api.nvim_buf_is_valid(bar.buf)) then
    bar.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[bar.buf].filetype = "own_activity_bar"
    vim.bo[bar.buf].bufhidden = "hide"
    for _, lhs in ipairs({ "<LeftRelease>", "<cr>" }) do
      vim.keymap.set("n", lhs, bar_click, { buffer = bar.buf, silent = true, nowait = true })
    end
  end
  local cur = vim.api.nvim_get_current_win()
  vim.cmd("topleft vertical 3split")
  bar.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(bar.win, bar.buf)
  local wo = vim.wo[bar.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn, wo.foldcolumn = false, false, "no", "", "0"
  wo.cursorline, wo.winfixwidth, wo.winbar, wo.list, wo.wrap = false, true, "", false, false
  wo.winhighlight = "Normal:OwnBar,EndOfBuffer:OwnBar,WinSeparator:OwnBarSep"
  bar_render()
  if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
end

local function bar_close()
  if bar.win and vim.api.nvim_win_is_valid(bar.win) then pcall(vim.api.nvim_win_close, bar.win, true) end
  bar.win = nil
end

function M.activity(i)
  local name = bar_items()[i]
  if name then ITEMS[name].run() end
  vim.schedule(bar_render)
end

-- ── нижняя панель ────────────────────────────────────────────────────────────

local TABS = { terminal = "Терминал", problems = "Проблемы", tasks = "Задачи" }
local panel = { win = nil, tab = "terminal", bufs = {} }

local function problems_buf()
  local buf = panel.bufs.problems
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "own_panel"
    vim.bo[buf].bufhidden = "hide"
    panel.bufs.problems = buf
    vim.keymap.set("n", "<cr>", function()
      local item = (vim.b[buf].own_items or {})[vim.api.nvim_win_get_cursor(0)[1]]
      if not item then return end
      vim.cmd("wincmd k")
      vim.cmd.edit(vim.fn.fnameescape(item.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, item.col })
    end, { buffer = buf, silent = true })
  end
  -- перерисовать: файл, строка, сообщение — ошибки сначала
  -- одна и та же ошибка от разных источников (gopls пишет её дважды) — одной строкой
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
  local ICON = { "\u{f057}", "\u{f071}", "\u{f05a}", "\u{f0eb}" }
  for _, d in ipairs(ds) do
    local file = vim.api.nvim_buf_get_name(d.bufnr)
    lines[#lines + 1] = (" %s %s:%d  %s"):format(ICON[d.severity] or "•", vim.fn.fnamemodify(file, ":~:."), d.lnum + 1,
      (d.message:gsub("\n", " ")))
    items[#lines] = { file = file, lnum = d.lnum + 1, col = d.col, severity = d.severity }
  end
  if #lines == 0 then lines = { " \u{f00c} Проблем нет" } end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].own_items = items
  local ns = vim.api.nvim_create_namespace("own.panel")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local HL = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }
  for row, it in pairs(items) do
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { end_col = 4, hl_group = HL[it.severity] })
  end
  return buf
end

local function terminal_buf()
  local buf = panel.bufs.terminal
  if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
  buf = vim.api.nvim_create_buf(false, true)
  panel.bufs.terminal = buf
  vim.api.nvim_buf_call(buf, function()
    vim.fn.jobstart(vim.o.shell, { term = true, cwd = require("own.root").get() })
  end)
  return buf
end

local function tasks_buf()
  local ok, overseer = pcall(require, "overseer")
  local task = ok and overseer.list_tasks({ recent_first = true })[1]
  local buf = task and task:get_bufnr()
  if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
  local empty = panel.bufs.tasks_empty
  if not (empty and vim.api.nvim_buf_is_valid(empty)) then
    empty = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(empty, 0, -1, false, { " Задач ещё не запускали — пробел r r" })
    vim.bo[empty].modifiable = false
    panel.bufs.tasks_empty = empty
  end
  return empty
end

local BUFS = { terminal = terminal_buf, problems = problems_buf, tasks = tasks_buf }

_G.OwnPanelTab = function(minwid) M.show(({ "terminal", "problems", "tasks" })[minwid]) end

local function winbar()
  local parts = {}
  local count = #vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR })
  for i, name in ipairs((o().bottom or {}).tabs or { "terminal", "problems", "tasks" }) do
    local idx = ({ terminal = 1, problems = 2, tasks = 3 })[name]
    if idx then
      local label = TABS[name] .. (name == "problems" and count > 0 and (" " .. count) or "")
      local hl = name == panel.tab and "%#OwnPanelTabActive#" or "%#OwnPanelTab#"
      parts[#parts + 1] = ("%%%d@v:lua.OwnPanelTab@%s %s %%X"):format(idx, hl, label)
    end
    local _ = i
  end
  return table.concat(parts, "%#OwnPanelTab#  ") .. "%#OwnPanelTab#"
end

function M.is_open() return panel.win and vim.api.nvim_win_is_valid(panel.win) end

function M.show(tab)
  panel.tab = tab or panel.tab
  local buf = BUFS[panel.tab]()
  if not M.is_open() then
    vim.cmd("botright " .. ((o().bottom or {}).height or 12) .. "split")
    panel.win = vim.api.nvim_get_current_win()
    local wo = vim.wo[panel.win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn, wo.winfixheight = false, false, "no", "", true
  else
    vim.api.nvim_set_current_win(panel.win)
  end
  vim.api.nvim_win_set_buf(panel.win, buf)
  vim.wo[panel.win].winbar = "%{%v:lua.require'own.modules.panels'.winbar()%}"
  if panel.tab == "terminal" then vim.cmd("startinsert") end
end

M.winbar = winbar

function M.hide()
  if M.is_open() then pcall(vim.api.nvim_win_close, panel.win, true) end
  panel.win = nil
end

function M.toggle() if M.is_open() then M.hide() else M.show() end end

-- ── общее ────────────────────────────────────────────────────────────────────

local function define()
  local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end
  local bg = c("StatusLine", "bg") or c("Normal", "bg")
  vim.api.nvim_set_hl(0, "OwnBar", { fg = c("Comment"), bg = bg })
  vim.api.nvim_set_hl(0, "OwnBarActive", { fg = c("Title") or c("Normal"), bg = bg, bold = true })
  vim.api.nvim_set_hl(0, "OwnBarSep", { fg = bg, bg = bg })
  vim.api.nvim_set_hl(0, "OwnPanelTab", { fg = c("Comment"), bg = c("Normal", "bg") })
  vim.api.nvim_set_hl(0, "OwnPanelTabActive", { fg = c("Normal"), bg = c("Normal", "bg"), bold = true, underline = true, sp = c("Title") })
end

function M.setup()
  define()
  local group = vim.api.nvim_create_augroup("own.panels", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() define(); bar_render() end })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function() if M.is_open() and panel.tab == "problems" then vim.schedule(problems_buf) end end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "BufWinEnter", "WinClosed" }, { group = group, callback = function() vim.schedule(bar_render) end })
  if (o().activity_bar or {}).enabled ~= false then
    -- полоса — когда открыт обычный файл (на стартовом экране её нет)
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function(ev)
        if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then vim.schedule(bar_open) end
      end,
    })
    -- остались только служебные окна — выйти
    vim.api.nvim_create_autocmd("QuitPre", {
      group = group,
      callback = function()
        local normal = vim.tbl_filter(function(w)
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == ""
        end, vim.api.nvim_tabpage_list_wins(0))
        if #normal <= 1 then bar_close() end
      end,
    })
  end
end

function M.reload()
  if (o().activity_bar or {}).enabled == false then bar_close() else bar_render() end
end

return M
