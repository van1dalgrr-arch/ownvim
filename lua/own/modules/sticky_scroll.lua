-- Липкая шапка, как Sticky Scroll в VS Code: заголовок функции/типа/блока прилипает сверху, пока ты внутри.
-- Настройки модуля: { "max_lines": 3, "mode": "cursor" | "topline" } — сколько строк шапки и от чего считать.
local M = {}

function M.plugins(opts)
  return {
    {
      "nvim-treesitter/nvim-treesitter-context",
      event = { "BufReadPost", "BufNewFile" },
      -- trim_scope inner: не влезает — отбрасываются внутренние уровни, имя функции видно всегда (как в VS Code)
      opts = { max_lines = opts.max_lines or 3, mode = opts.mode or "cursor", multiline_threshold = 1, trim_scope = "inner" },
    },
  }
end

return M
