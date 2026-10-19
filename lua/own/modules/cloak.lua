-- Секреты в .env — под звёздочками (на демо и скриншотах), строка под курсором — видна. пробел u e — показать все.
local M = {}

function M.plugins()
  return {
    {
      "laytan/cloak.nvim",
      event = { "BufReadPre .env*", "BufReadPre *.env" },
      cmd = { "CloakToggle", "CloakPreviewLine" },
      opts = { cloak_telescope = false, patterns = { { file_pattern = { ".env*", "*.env" }, cloak_pattern = "=.+" } } },
      config = function(_, opts)
        require("cloak").setup(opts)
        vim.api.nvim_create_autocmd("CursorMoved", {
          group = vim.api.nvim_create_augroup("own.cloak", { clear = true }),
          pattern = { ".env*", "*.env" },
          callback = function() pcall(vim.cmd, "CloakPreviewLine") end,
        })
      end,
    },
  }
end

return M
