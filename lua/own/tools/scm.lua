-- «Изменения» — как Source Control в VS Code: слева список файлов «в индексе» и «изменения», всё с клавиатуры.
--   enter — открыть файл        d — что изменилось (diff)        s — в индекс / из индекса
--   S — всё в индекс            U — всё из индекса               x — отменить правки в файле (спросит)
--   c — коммит (спросит текст; индекс пуст — предложит взять все изменения)        r — обновить
--   b — ветки        p — pull (только перемотка)        P — push (спросит)
-- Открыть: ctrl-shift-g, пробел g e или значок над левой панелью. Список сам обновляется после записи файла.
local root = require("own.root")

local M = {}

local ns = vim.api.nvim_create_namespace("own.scm")
local state = { buf = nil, dir = nil, items = {}, branch = "" }

local KIND = {
  M = { "M", "DiagnosticWarn" }, A = { "A", "DiagnosticOk" }, D = { "D", "DiagnosticError" },
  R = { "R", "DiagnosticInfo" }, C = { "C", "DiagnosticInfo" }, U = { "!", "DiagnosticError" }, ["?"] = { "U", "DiagnosticOk" },
}

local function git(args, done)
  local cmd = { "git", "-C", state.dir }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(r)
    if r.code ~= 0 and (r.stderr or "") ~= "" then vim.notify(vim.trim(r.stderr), vim.log.levels.WARN, { title = "git" }) end
    if done then done(r) end
  end))
end

-- git status --porcelain=v1 -b -z → ветка и два списка
local function parse(out)
  local staged, changes, branch = {}, {}, ""
  local fields = vim.split(out, "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #fields do
    local f = fields[i]
    if f:sub(1, 2) == "##" then
      branch = f:sub(4):gsub("%.%.%.%S+", "")
    else
      local x, y, path = f:sub(1, 1), f:sub(2, 2), f:sub(4)
      if x == "R" or x == "C" then i = i + 1 end -- следом идёт старое имя
      if x == "?" then
        changes[#changes + 1] = { path = path, kind = "?", untracked = true }
      else
        if x ~= " " then staged[#staged + 1] = { path = path, kind = x, staged = true } end
        if y ~= " " then changes[#changes + 1] = { path = path, kind = y } end
      end
    end
    i = i + 1
  end
  return staged, changes, branch
end

local function render(staged, changes)
  local buf = state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local lines, items, marks = {}, {}, {}
  local function add(text, hl, item)
    lines[#lines + 1] = text
    if item then items[#lines] = item end
    if hl then marks[#marks + 1] = { #lines - 1, hl } end
  end
  add(" \u{e725} " .. (state.branch ~= "" and state.branch or "нет ветки"), "Title")
  add(" c коммит · s индекс · d diff · p/P pull/push", "Comment")
  if #staged + #changes == 0 then
    add("")
    add(" \u{eab2}  Изменений нет", "Comment")
  end
  local function section(title, list)
    if #list == 0 then return end
    add("")
    add((" %s  %d"):format(title, #list), "OwnSideTitle")
    for _, it in ipairs(list) do
      local k = KIND[it.kind] or { it.kind, "Comment" }
      local name, dirname = vim.fs.basename(it.path:gsub("/$", "")), vim.fs.dirname(it.path)
      add(("  %s %s%s"):format(k[1], name, dirname ~= "." and ("  " .. dirname) or ""), nil, it)
      marks[#marks + 1] = { #lines - 1, k[2], 2, 3 }
      if dirname ~= "." then marks[#marks + 1] = { #lines - 1, "Comment", 4 + #name, -1 } end
    end
  end
  section("В ИНДЕКСЕ", staged)
  section("ИЗМЕНЕНИЯ", changes)
  local row = vim.api.nvim_buf_line_count(buf) > 1 and M.win() and vim.api.nvim_win_get_cursor(M.win())[1] or nil
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  state.items = items
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #lines[m[1] + 1]
    local from, to = m[3] or 0, m[4] or -1
    if to < 0 or to > len then to = len end
    if from < to then vim.api.nvim_buf_set_extmark(buf, ns, m[1], from, { end_col = to, hl_group = m[2] }) end
  end
  local w = M.win()
  if w then
    -- курсор — на первом файле (или там, где стоял)
    local first = next(items) and math.min(unpack(vim.tbl_keys(items))) or 1
    pcall(vim.api.nvim_win_set_cursor, w, { math.min(row and row > 2 and row or first, #lines), 0 })
  end
end

function M.win()
  if not state.buf then return nil end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(w) == state.buf then return w end
  end
end

function M.refresh()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) or not state.dir then return end
  git({ "status", "--porcelain=v1", "-b", "-z", "--untracked-files=all" }, function(r)
    if r.code ~= 0 then
      state.branch = ""
      return render({}, {})
    end
    local staged, changes, branch = parse(r.stdout or "")
    state.branch = branch
    render(staged, changes)
  end)
end

local function item()
  local w = M.win()
  return w and state.items[vim.api.nvim_win_get_cursor(w)[1]] or nil
end

local function code_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then return w end
  end
end

local function open(it, diff)
  local path = state.dir .. "/" .. it.path
  if vim.fn.filereadable(path) == 0 then return vim.notify("файла уже нет: " .. it.path) end
  local w = code_win()
  if w then vim.api.nvim_set_current_win(w) else vim.cmd("rightbelow vsplit") end
  vim.cmd.edit(vim.fn.fnameescape(path))
  if diff and not it.untracked then
    -- в индексе — против последнего коммита, иначе — против индекса
    -- gitsigns подключается к только что открытому файлу не сразу — подождать его (до секунды)
    local buf, tries = vim.api.nvim_get_current_buf(), 0
    local function go()
      if vim.api.nvim_get_current_buf() ~= buf then return end
      local ok, gs = pcall(require, "gitsigns")
      if not ok then return end
      if vim.b[buf].gitsigns_status_dict or tries >= 10 then return gs.diffthis(it.staged and "HEAD" or nil) end
      tries = tries + 1
      vim.defer_fn(go, 100)
    end
    go()
  end
end

local function commit()
  local function ask()
    vim.ui.input({ prompt = "Коммит: " }, function(msg)
      if not msg or vim.trim(msg) == "" then return end
      git({ "commit", "-m", msg }, function(r)
        if r.code == 0 then vim.notify(vim.trim((r.stdout or ""):match("[^\n]*") or "готово"), nil, { title = "git" }) end
        M.refresh()
      end)
    end)
  end
  git({ "diff", "--cached", "--quiet" }, function(r)
    if r.code ~= 0 then return ask() end -- в индексе что-то есть
    if not next(state.items) then return vim.notify("коммитить нечего") end
    if vim.fn.confirm("Индекс пуст. Взять в коммит все изменения?", "&Да\n&Нет", 2) ~= 1 then return end
    git({ "add", "-A" }, function() M.refresh(); ask() end)
  end)
end

local function discard(it)
  if it.staged then return vim.notify("сначала убери из индекса (s)") end
  local what = it.untracked and "Удалить новый файл" or "Отменить правки в"
  if vim.fn.confirm(("%s %s? Вернуть будет нельзя."):format(what, it.path), "&Да\n&Нет", 2) ~= 1 then return end
  git(it.untracked and { "clean", "-f", "--", it.path } or { "restore", "--", it.path }, function()
    vim.cmd("silent! checktime")
    M.refresh()
  end)
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "own_git"
  vim.bo[buf].bufhidden = "hide"
  local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc }) end
  local function on_item(fn) return function() local it = item(); if it then fn(it) end end end
  map("<cr>", on_item(function(it) open(it) end), "Открыть файл")
  map("o", on_item(function(it) open(it) end), "Открыть файл")
  map("<2-LeftMouse>", on_item(function(it) open(it) end), "Открыть файл")
  map("d", on_item(function(it) open(it, true) end), "Что изменилось")
  map("s", on_item(function(it)
    git(it.staged and { "restore", "--staged", "--", it.path } or { "add", "--", it.path }, M.refresh)
  end), "В индекс / из индекса")
  map("S", function() git({ "add", "-A" }, M.refresh) end, "Всё в индекс")
  map("U", function() git({ "reset", "-q" }, M.refresh) end, "Всё из индекса")
  map("x", on_item(discard), "Отменить правки")
  map("c", commit, "Коммит")
  map("r", M.refresh, "Обновить")
  map("b", function() require("own.actions").get("git.branches")() end, "Ветки")
  map("p", function()
    vim.notify("git pull…")
    git({ "pull", "--ff-only" }, function(r)
      if r.code == 0 then vim.notify(vim.trim(r.stdout or ""):match("[^\n]*$") or "готово", nil, { title = "git pull" }) end
      vim.cmd("silent! checktime")
      M.refresh()
    end)
  end, "Pull (только перемотка)")
  map("P", function()
    if vim.fn.confirm(("Отправить ветку %s на сервер (git push)?"):format(state.branch), "&Да\n&Нет", 2) ~= 1 then return end
    vim.notify("git push…")
    git({ "push" }, function(r)
      if r.code == 0 then vim.notify("отправлено", nil, { title = "git push" }) end
      M.refresh()
    end)
  end, "Push (спросит)")
  return buf
end

--- Открыть панель (рабочее место ставит её слева)
function M.open()
  state.dir = root.git()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then state.buf = make_buf() end
  local width = (require("own.settings").module_opts(require("own.settings").current or {}, "workspace") or {}).left_width or 32
  vim.cmd("topleft " .. width .. "vsplit")
  vim.api.nvim_win_set_buf(0, state.buf)
  local wo = vim.wo[0]
  wo.number, wo.relativenumber, wo.statuscolumn, wo.cursorline, wo.wrap, wo.list = false, false, "", true, false, false
  M.refresh()
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "ShellCmdPost", "TermLeave", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("own.scm", { clear = true }),
    callback = function()
      if M.win() then vim.schedule(M.refresh) end
    end,
  })
end

return M
