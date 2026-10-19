-- Своё дерево файлов (вместо snacks explorer): вид — из settings.jsonc, раздел "explorer".
--   "engine": "own" | "snacks"; "side": "left" | "right"; "width": 32
--   "hidden": false — скрытые файлы (H — на время); "ignore": [".git", "node_modules", ".DS_Store"]
--   "git": true — цвет и значок изменённых, новых, удалённых; "diagnostics": true — ошибки у файлов и папок
--   "indent": "│ " — отступ ("  " — без линий); "folder_icons": { "open": "…", "closed": "…" }
--   "follow": true — подсвечивать открытый файл; "compact": true — папка с одной папкой — одной строкой (a/b/c)
-- Клавиши в дереве: enter/l/клик — открыть или развернуть, h — свернуть, a — создать (конец на / — папка),
-- r — переименовать, d — удалить, y — копировать путь, c/x/p — копировать/вырезать/вставить, s — открыть справа,
-- H — скрытые, R — обновить, - — на папку выше, . — сделать корнем, ? — подсказка, q — закрыть.
local settings = require("own.settings")

local M = {}

local state = {
  root = nil,
  open = {}, -- путь папки → развёрнута
  lines = {}, -- строка → { path, dir, depth }
  buf = nil,
  win = nil,
  git = {}, -- путь → "M" / "A" / "D" / "?" / "R"
  clipboard = nil, -- { path, cut }
  show_hidden = nil,
}

local ns = vim.api.nvim_create_namespace("own.tree")

local function o() return (settings.current or {}).explorer or {} end

local function hidden()
  if state.show_hidden ~= nil then return state.show_hidden end
  return o().hidden == true
end

local function ignored(name)
  for _, pat in ipairs(o().ignore or { ".git", ".DS_Store", "node_modules" }) do
    if name == pat then return true end
  end
  return false
end

local function list_dir(dir)
  local entries = {}
  for name, kind in vim.fs.dir(dir) do
    if not ignored(name) and (hidden() or name:sub(1, 1) ~= ".") then
      if kind == "link" then
        local st = vim.uv.fs_stat(dir .. "/" .. name)
        kind = st and st.type or "file"
      end
      entries[#entries + 1] = { name = name, dir = kind == "directory", path = dir .. "/" .. name }
    end
  end
  table.sort(entries, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

-- git status → путь → буква; папка получает «изменено», если внутри что-то изменено
local function refresh_git(done)
  if o().git == false then return done and done() end
  -- корень репозитория — до вызова: в колбэке vim.fn нельзя
  local top = vim.fs.root(state.root, ".git")
  if not top then return done and done() end
  vim.system({ "git", "-C", state.root, "status", "--porcelain=v1", "-uall", "--ignored=no" }, { text = true }, function(r)
    local git = {}
    if r.code == 0 then
      for line in (r.stdout or ""):gmatch("[^\n]+") do
        local x, y, path = line:sub(1, 1), line:sub(2, 2), line:sub(4)
        path = path:match("-> (.+)$") or path
        local mark = (x == "?" and "?") or ((x == "A" or y == "A") and "A") or ((x == "D" or y == "D") and "D")
          or ((x == "R") and "R") or "M"
        local full = top .. "/" .. path
        git[full] = mark
        local parent = vim.fs.dirname(full)
        while parent and #parent >= #state.root do
          git[parent] = git[parent] or "M"
          local up = vim.fs.dirname(parent)
          if up == parent then break end
          parent = up
        end
      end
    end
    vim.schedule(function()
      state.git = git
      if done then done() end
    end)
  end)
end

-- ошибки: путь → худшая (1 — ошибка), и по папкам вверх
local function diagnostics()
  if o().diagnostics == false then return {} end
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(nil, { severity = { min = vim.diagnostic.severity.WARN } })) do
    local path = vim.api.nvim_buf_get_name(d.bufnr)
    while path and #path >= #state.root do
      if not out[path] or d.severity < out[path] then out[path] = d.severity end
      local up = vim.fs.dirname(path)
      if up == path then break end
      path = up
    end
  end
  return out
end

local GIT_HL = { M = "OwnTreeGitModified", A = "OwnTreeGitAdded", ["?"] = "OwnTreeGitAdded", D = "OwnTreeGitDeleted", R = "OwnTreeGitModified" }
local GIT_SIGN = { M = "M", A = "A", ["?"] = "U", D = "D", R = "R" }

function M.render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local opts = o()
  local indent = opts.indent or "│ "
  local fo = opts.folder_icons or {}
  local icons_ok, icons = pcall(require, "mini.icons")
  local diag = diagnostics()
  local current = vim.api.nvim_buf_get_name(vim.fn.bufnr("#") ~= -1 and vim.fn.bufnr("#") or 0)
  local lines, marks, meta = {}, {}, {}

  local root_name = vim.fn.fnamemodify(state.root, ":t")
  lines[1] = " " .. root_name:upper()
  marks[1] = { { 0, #lines[1], "OwnTreeRoot" } }
  meta[1] = { path = state.root, dir = true, depth = -1 }

  local function walk(dir, depth)
    for _, e in ipairs(list_dir(dir)) do
      local label, path = e.name, e.path
      -- компактные папки: a/b/c, пока в папке ровно одна папка
      if e.dir and opts.compact ~= false then
        while true do
          local inner = list_dir(path)
          if #inner == 1 and inner[1].dir then
            label = label .. "/" .. inner[1].name
            path = inner[1].path
          else
            break
          end
        end
      end
      local prefix = string.rep(indent, depth)
      local icon, icon_hl
      if e.dir then
        icon = state.open[path] and (fo.open or "\u{f07c}") or (fo.closed or "\u{f07b}")
        icon_hl = "OwnTreeFolder"
      elseif icons_ok then
        icon, icon_hl = icons.get("file", path)
      else
        icon, icon_hl = "•", "Comment"
      end
      local g = state.git[path]
      local line = " " .. prefix .. icon .. " " .. label
      local row = #lines + 1
      local m = {}
      m[#m + 1] = { 0, #prefix + 1, "OwnTreeIndent" }
      m[#m + 1] = { #prefix + 1, #prefix + 1 + #icon, icon_hl }
      local name_hl = (path == current and "OwnTreeCurrent") or (g and GIT_HL[g]) or (e.dir and "OwnTreeDir") or "OwnTreeFile"
      m[#m + 1] = { #prefix + 2 + #icon, #line, name_hl }
      local right = {}
      if diag[path] then
        right[#right + 1] = { diag[path] == 1 and "●" or "●", diag[path] == 1 and "DiagnosticError" or "DiagnosticWarn" }
      end
      if g and GIT_SIGN[g] and not e.dir then right[#right + 1] = { " " .. GIT_SIGN[g], GIT_HL[g] } end
      lines[row] = line
      marks[row] = m
      meta[row] = { path = path, dir = e.dir, depth = depth, right = right }
      if e.dir and state.open[path] then walk(path, depth + 1) end
    end
  end
  walk(state.root, 0)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for row, m in ipairs(marks) do
    for _, x in ipairs(m) do
      pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, row - 1, x[1], { end_col = x[2], hl_group = x[3] })
    end
    local r = meta[row].right
    if r and #r > 0 then
      vim.api.nvim_buf_set_extmark(state.buf, ns, row - 1, 0, { virt_text = r, virt_text_pos = "right_align" })
    end
  end
  state.lines = meta
end

local function define()
  local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end
  vim.api.nvim_set_hl(0, "OwnTreeRoot", { fg = c("Title") or c("Normal"), bold = true })
  vim.api.nvim_set_hl(0, "OwnTreeFolder", { fg = c("Directory") or c("Function") })
  vim.api.nvim_set_hl(0, "OwnTreeDir", { fg = c("Normal") })
  vim.api.nvim_set_hl(0, "OwnTreeFile", { fg = c("Normal") })
  vim.api.nvim_set_hl(0, "OwnTreeIndent", { fg = c("NonText") or c("Comment") })
  vim.api.nvim_set_hl(0, "OwnTreeCurrent", { fg = c("Title") or c("Normal"), bold = true })
  vim.api.nvim_set_hl(0, "OwnTreeGitModified", { fg = c("DiagnosticWarn") })
  vim.api.nvim_set_hl(0, "OwnTreeGitAdded", { fg = c("DiagnosticOk") or c("String") })
  vim.api.nvim_set_hl(0, "OwnTreeGitDeleted", { fg = c("DiagnosticError"), strikethrough = true })
end

local function at_cursor()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return nil end
  return state.lines[vim.api.nvim_win_get_cursor(state.win)[1]]
end

-- окно с кодом рядом с деревом: последнее, где был курсор
local function code_win()
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev ~= 0 and prev ~= state.win and vim.api.nvim_win_get_config(prev).relative == "" then return prev end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= state.win and vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
      return w
    end
  end
end

local function open_file(path, split)
  local w = code_win()
  if not w then
    vim.cmd((o().side == "right" and "topleft" or "botright") .. " vsplit")
    w = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(w)
  vim.cmd((split and "vsplit " or "edit ") .. vim.fn.fnameescape(path))
end

local function act(fn) return function() local e = at_cursor() if e then fn(e) end end end

-- раскрыть папки до пути и поставить на него курсор (после создания, переименования, вставки)
local function reveal(path)
  local d = vim.fs.dirname(path)
  while d and #d > #state.root do
    state.open[d] = true
    d = vim.fs.dirname(d)
  end
  M.render()
  for row, l in ipairs(state.lines) do
    if l.path == path and M.is_open() then return pcall(vim.api.nvim_win_set_cursor, state.win, { row, 0 }) end
  end
end

local function refresh(path)
  refresh_git(function()
    M.render()
    if path then reveal(path) end
  end)
end

local actions = {
  open = act(function(e)
    if e.depth < 0 then return end
    if e.dir then
      state.open[e.path] = not state.open[e.path]
      M.render()
    else
      open_file(e.path)
    end
  end),
  split = act(function(e) if not e.dir then open_file(e.path, true) end end),
  close = act(function(e)
    if e.dir and state.open[e.path] then
      state.open[e.path] = nil
    else
      -- свернуть родителя и встать на него
      local parent = vim.fs.dirname(e.path)
      state.open[parent] = nil
      M.render()
      for row, l in ipairs(state.lines) do
        if l.path == parent then return vim.api.nvim_win_set_cursor(state.win, { row, 0 }) end
      end
    end
    M.render()
  end),
  add = act(function(e)
    local base = e.dir and e.path or vim.fs.dirname(e.path)
    vim.ui.input({ prompt = "Новый (папка — / в конце): " .. vim.fn.fnamemodify(base, ":~:.") .. "/" }, function(name)
      if not name or name == "" then return end
      local path = base .. "/" .. name
      if name:sub(-1) == "/" then
        vim.fn.mkdir(path, "p")
      else
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        local f = io.open(path, "a")
        if f then f:close() end
      end
      state.open[base] = true
      reveal(path:gsub("/$", ""))
      refresh(path:gsub("/$", ""))
      if name:sub(-1) ~= "/" then open_file(path) end
    end)
  end),
  rename = act(function(e)
    if e.depth < 0 then return end
    vim.ui.input({ prompt = "Переименовать: ", default = vim.fn.fnamemodify(e.path, ":t") }, function(name)
      if not name or name == "" then return end
      local to = vim.fs.dirname(e.path) .. "/" .. name
      local ok, err = os.rename(e.path, to)
      if not ok then return vim.notify(err, vim.log.levels.ERROR) end
      -- открытые буферы — на новое имя (и LSP переименует импорты, если умеет)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local n = vim.api.nvim_buf_get_name(b)
        if n == e.path or vim.startswith(n, e.path .. "/") then vim.api.nvim_buf_set_name(b, to .. n:sub(#e.path + 1)) end
      end
      refresh(to)
    end)
  end),
  delete = act(function(e)
    if e.depth < 0 then return end
    if vim.fn.confirm(("Удалить %s?"):format(vim.fn.fnamemodify(e.path, ":~:.")), "&Да\n&Нет", 2) ~= 1 then return end
    -- в корзину macOS, если есть trash; иначе — насовсем
    if vim.fn.executable("trash") == 1 then vim.fn.system({ "trash", e.path }) else vim.fn.delete(e.path, "rf") end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local n = vim.api.nvim_buf_get_name(b)
      if n == e.path or vim.startswith(n, e.path .. "/") then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
    end
    refresh()
  end),
  yank_path = act(function(e)
    local rel = vim.fn.fnamemodify(e.path, ":~:.")
    vim.fn.setreg("+", rel)
    vim.notify("скопирован путь: " .. rel)
  end),
  copy = act(function(e) state.clipboard = { path = e.path, cut = false } vim.notify("копировать: " .. vim.fn.fnamemodify(e.path, ":t") .. " — p, чтобы вставить") end),
  cut = act(function(e) state.clipboard = { path = e.path, cut = true } vim.notify("вырезать: " .. vim.fn.fnamemodify(e.path, ":t") .. " — p, чтобы вставить") end),
  paste = act(function(e)
    local cb = state.clipboard
    if not cb then return vim.notify("сначала c или x на файле") end
    local dest = (e.dir and e.path or vim.fs.dirname(e.path)) .. "/" .. vim.fn.fnamemodify(cb.path, ":t")
    if cb.cut then
      os.rename(cb.path, dest)
      state.clipboard = nil
    else
      vim.fn.system({ "cp", "-R", cb.path, dest })
    end
    refresh(dest)
  end),
  toggle_hidden = function()
    state.show_hidden = not hidden()
    M.render()
  end,
  refresh = refresh,
  up = function()
    state.root = vim.fs.dirname(state.root)
    refresh()
  end,
  set_root = act(function(e) if e.dir then state.root = e.path; refresh() end end),
  help = function()
    vim.notify(table.concat({
      "enter/l — открыть · h — свернуть · a — создать (/ — папка) · r — переименовать · d — удалить",
      "y — копировать путь · c/x/p — копировать/вырезать/вставить · s — открыть справа",
      "H — скрытые · R — обновить · - — папка выше · . — сделать корнем · q — закрыть",
    }, "\n"))
  end,
  quit = function() M.close() end,
}

local KEYS = {
  ["<cr>"] = "open", l = "open", ["<2-LeftMouse>"] = "open", o = "open", h = "close", s = "split", a = "add",
  r = "rename", d = "delete", y = "yank_path", c = "copy", x = "cut", p = "paste", H = "toggle_hidden",
  R = "refresh", ["-"] = "up", ["."] = "set_root", ["?"] = "help", q = "quit",
}

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "own_tree"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  for lhs, name in pairs(KEYS) do
    vim.keymap.set("n", lhs, actions[name], { buffer = buf, nowait = true, silent = true, desc = "Дерево: " .. name })
  end
  -- одиночный клик мышью по папке — развернуть
  vim.keymap.set("n", "<LeftRelease>", function()
    local e = at_cursor()
    if e and e.dir then actions.open() end
  end, { buffer = buf, silent = true })
  return buf
end

function M.is_open() return state.win and vim.api.nvim_win_is_valid(state.win) end

function M.open(root)
  state.root = root or state.root or require("own.root").get()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then state.buf = make_buf() end
  if not M.is_open() then
    local side = o().side == "right" and "botright" or "topleft"
    -- слева есть полоса значков (модуль panels) — дерево встаёт сразу за ней
    local bar
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "own_activity_bar" then bar = w end
    end
    vim.cmd(side .. " vertical " .. (o().width or 32) .. "split")
    local tree_win = vim.api.nvim_get_current_win()
    if bar and o().side ~= "right" then
      -- полосу — обратно на самый край, дерево — сразу за ней, ширина — как в настройках
      vim.api.nvim_set_current_win(bar)
      vim.cmd("wincmd H")
      vim.api.nvim_win_set_width(bar, 3)
      vim.api.nvim_set_current_win(tree_win)
    end
    vim.api.nvim_win_set_width(tree_win, o().width or 32)
    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    local wo = vim.wo[state.win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, "no", "0"
    wo.cursorline, wo.wrap, wo.winfixwidth, wo.list, wo.spell = true, false, true, false, false
    wo.statuscolumn, wo.winbar = "", ""
  else
    vim.api.nvim_set_current_win(state.win)
  end
  define()
  -- развернуть путь до открытого файла
  local cur = vim.api.nvim_buf_get_name(vim.fn.bufnr("#"))
  if cur ~= "" and vim.startswith(cur, state.root) then
    local d = vim.fs.dirname(cur)
    while #d > #state.root do state.open[d] = true; d = vim.fs.dirname(d) end
  end
  M.render()
  refresh_git(function()
    M.render()
    for row, l in ipairs(state.lines) do
      if l.path == cur then return pcall(vim.api.nvim_win_set_cursor, state.win, { row, 0 }) end
    end
  end)
end

function M.close()
  if M.is_open() then vim.api.nvim_win_close(state.win, true) end
  state.win = nil
end

function M.toggle(root)
  if M.is_open() then M.close() else M.open(root) end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.tree", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() define(); M.render() end })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "DirChanged" }, {
    group = group,
    callback = function() if M.is_open() then refresh() end end,
  })
  vim.api.nvim_create_autocmd({ "DiagnosticChanged", "BufEnter" }, {
    group = group,
    callback = function() if M.is_open() and o().follow ~= false then vim.schedule(M.render) end end,
  })
  -- последнее окно — дерево: закрыть ownvim, а не оставлять одно дерево
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local wins = vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end, vim.api.nvim_tabpage_list_wins(0))
      if #wins == 2 and M.is_open() and vim.api.nvim_get_current_win() ~= state.win then M.close() end
    end,
  })
end

return M
