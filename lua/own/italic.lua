-- Курсив поверх любой темы (JSON и плагины вроде tokyonight): "appearance": { "italic": [...] }.
-- Роли: comment, keyword, function, type, string, parameter, builtin. [] — как задумано темой.
-- Тему не трогает: после каждой смены темы добавляет italic нужным группам, остальное оставляет.
local settings = require("own.settings")

local M = {}

-- роль → группы подсветки (обычные, treesitter, семантические токены LSP)
M.roles = {
  comment = { "Comment", "@comment", "@comment.documentation", "@lsp.type.comment" },
  keyword = { "Keyword", "Statement", "Conditional", "Repeat", "Exception", "Include", "StorageClass",
    "@keyword", "@keyword.function", "@keyword.return", "@keyword.conditional", "@keyword.repeat",
    "@keyword.operator", "@keyword.import", "@keyword.type", "@keyword.modifier", "@keyword.exception",
    "@keyword.coroutine", "@lsp.type.keyword" },
  ["function"] = { "Function", "@function", "@function.call", "@function.method", "@function.method.call",
    "@lsp.type.function", "@lsp.type.method" },
  type = { "Type", "@type", "@type.definition", "@lsp.type.type", "@lsp.type.struct", "@lsp.type.interface" },
  string = { "String", "@string" },
  parameter = { "@variable.parameter", "@lsp.type.parameter" },
  builtin = { "@variable.builtin", "@constant.builtin", "@function.builtin", "@type.builtin" },
}

function M.list() return ((settings.current or {}).appearance or {}).italic or {} end

function M.apply()
  for _, role in ipairs(M.list()) do
    local names = M.roles[role]
    if not names then
      settings.warn("appearance", "italic: нет роли «" .. tostring(role) .. "» (есть: comment, keyword, function, type, string, parameter, builtin)")
    else
      for _, name in ipairs(names) do
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
        if next(hl) and not hl.italic then
          hl.italic = true
          vim.api.nvim_set_hl(0, name, hl)
        end
      end
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.italic", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.apply })
  M.apply()
end

-- список поменялся: убрать курсив можно только перекрасив тему заново — она снова зовёт apply
function M.reload(new, old)
  local function get(s) return ((s or {}).appearance or {}).italic or {} end
  if vim.deep_equal(get(new), get(old)) then return end
  if vim.g.colors_name then pcall(vim.cmd.colorscheme, vim.g.colors_name) else M.apply() end
end

return M
