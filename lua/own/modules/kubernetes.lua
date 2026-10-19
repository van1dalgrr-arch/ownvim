-- Kubernetes в nvim (kubectl.nvim): пробел k — поды, деплойменты, логи, describe; включается, если есть kubectl.
local M = {}

function M.plugins()
  return {
    {
      "ramilito/kubectl.nvim",
      version = "2.*",
      cond = vim.fn.executable("kubectl") == 1,
      dependencies = { "saghen/blink.download" },
      cmd = { "Kubectl", "Kubens", "Kubectx" },
      opts = {},
    },
  }
end

return M
