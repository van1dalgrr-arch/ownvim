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

function M.get(buf)
  buf = buf or 0
  local o = opts()
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

--- Корень git-репозитория (для lazygit и истории)
function M.git(buf)
  return vim.fs.root(buf or 0, { ".git" }) or vim.uv.cwd()
end

return M
