-- Поиск файлов, текста, команд и дерево файлов — Snacks picker и explorer (как в LazyVim).
-- Клавиши — в разделе keys (пробел пробел, пробел /, пробел f …, пробел s …, пробел e).
return {
  plugins = {
    {
      "folke/snacks.nvim",
      opts = {
        picker = {
          -- скрытые файлы (.env.example, .github) видны, .git и игнорируемое — нет
          sources = { files = { hidden = true }, grep = { hidden = true }, explorer = { hidden = true } },
          win = { input = { keys = { ["<a-c>"] = { "toggle_cwd", mode = { "n", "i" } } } } },
          actions = {
            -- alt-c в поиске: искать в проекте ↔ в папке запуска
            toggle_cwd = function(p)
              local root = require("own.root").get(p.input.filter.current_buf)
              local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
              local current = p:cwd()
              p:set_cwd(current == root and cwd or root)
              p:find()
            end,
          },
        },
        explorer = { replace_netrw = true },
      },
    },
  },
}
