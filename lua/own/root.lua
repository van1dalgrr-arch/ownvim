-- Корень проекта для поиска, дерева и терминала — как LazyVim.root, только короче:
-- папка, которую выбрал языковой сервер (у gopls — go.mod / go.work), иначе ближайший .git, иначе папка запуска.
local M = {}

function M.get(buf)
  buf = buf or 0
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.root_dir and client.name ~= "copilot" then return client.root_dir end
  end
  return vim.fs.root(buf, { ".git" }) or vim.uv.cwd()
end

--- Корень git-репозитория (для lazygit и истории)
function M.git(buf)
  return vim.fs.root(buf or 0, { ".git" }) or vim.uv.cwd()
end

return M
