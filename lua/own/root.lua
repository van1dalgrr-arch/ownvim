-- Корень проекта для поиска, дерева и терминала — как LazyVim.root, только короче.
-- "project": { "root": "launch" } (по умолчанию) — папка, откуда запустил ownvim: cd dev/sql && ownvim . — это dev/sql,
-- даже если выше лежит .git (dev — сам репозиторий). Проект поглубже (свой .git, корень языкового сервера) — его корень.
-- "root": "git" — как раньше: корень языкового сервера (у gopls — go.mod / go.work), иначе ближайший .git вверх,
-- даже выше папки запуска. markers — по каким файлам узнавать корень (по умолчанию .git).
local M = {}

local function opts() return ((require("own.settings").current or {}).project or {}) end

-- dir внутри base (или совпадает)
local function within(dir, base)
  return dir == base or vim.startswith(dir, base:gsub("/$", "") .. "/")
end

-- Корень спрашивают на каждой перерисовке (статусная строка, вкладки, виджет запуска), а поиск .git вверх по
-- папкам — это обращения к диску. Ответ запоминается на буфер и сбрасывается, когда он мог поменяться:
-- сервер подключился / отключился, файл переименован, сменилась папка, файл записан, вернулся фокус.
local gen = 0
local roots, gits = {}, {}
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufFilePost", "DirChanged", "BufWritePost", "FocusGained", "BufDelete" }, {
  group = vim.api.nvim_create_augroup("own.root", { clear = true }),
  callback = function() gen = gen + 1 end,
})

local function find(buf, o)
  local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
  local file = vim.api.nvim_buf_get_name(buf)
  file = file ~= "" and vim.fs.normalize(file) or nil
  -- файл из папки запуска (или буфер без файла): корень выше неё не берём
  local launch = o.root ~= "git" and (not file or within(file, cwd))
  local function ok(dir) return dir and (not launch or within(vim.fs.normalize(dir), cwd)) end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.name ~= "copilot" and ok(client.root_dir) then return client.root_dir end
  end
  local found = vim.fs.root(file or cwd, o.markers or { ".git" })
  if ok(found) then return found end
  return cwd
end

function M.get(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local o = opts()
  local c = roots[buf]
  if c and c.gen == gen and c.root == o.root and c.markers == o.markers and c.name == vim.api.nvim_buf_get_name(buf) then return c.dir end
  local dir = find(buf, o)
  roots[buf] = { gen = gen, root = o.root, markers = o.markers, name = vim.api.nvim_buf_get_name(buf), dir = dir }
  return dir
end

--- Папка с .git для буфера или nil (с памятью — можно звать на каждой перерисовке)
function M.git_dir(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local c = gits[buf]
  if c and c.gen == gen and c.name == vim.api.nvim_buf_get_name(buf) then return c.dir or nil end
  local dir = vim.fs.root(buf, { ".git" })
  gits[buf] = { gen = gen, name = vim.api.nvim_buf_get_name(buf), dir = dir or false }
  return dir
end

--- Корень git-репозитория (для lazygit и истории)
function M.git(buf)
  return M.git_dir(buf) or vim.uv.cwd()
end

return M
