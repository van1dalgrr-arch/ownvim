-- Подсветка, отступы и складки по дереву разбора (nvim-treesitter, ветка main — для nvim 0.12).
-- Языки — "languages" в настройках модуля; недостающие ставятся сами в фоне (нужен tree-sitter из brew).
local M = {}

local function start(buf, opts)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang or not pcall(vim.treesitter.start, buf, lang) then return end
  if opts.indent ~= false then vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
  if opts.folds ~= false then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win][0].foldmethod = "expr"
      vim.wo[win][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    end
  end
end

function M.plugins(opts)
  return {
    {
      "nvim-treesitter/nvim-treesitter",
      branch = "main",
      lazy = false, -- ветка main не любит ленивую загрузку; сама по себе почти ничего не стоит
      build = ":TSUpdate",
      config = function()
        local ts = require("nvim-treesitter")
        local have = {}
        for _, l in ipairs(ts.get_installed()) do have[l] = true end
        local missing = vim.tbl_filter(function(l) return not have[l] end, opts.languages or {})
        if #missing > 0 then ts.install(missing) end
        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("own.treesitter", { clear = true }),
          callback = function(ev) start(ev.buf, opts) end,
        })
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then start(buf, opts) end
        end
      end,
    },
  }
end

return M
