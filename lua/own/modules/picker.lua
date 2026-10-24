-- Поиск файлов, текста, команд и дерево файлов — Snacks picker и explorer (как в LazyVim).
-- Клавиши — в разделе keys (пробел пробел, пробел /, пробел f …, пробел s …, пробел e).
return {
  plugins = {
    {
      "folke/snacks.nvim",
      opts = {
        picker = {
          -- «палитра», как ctrl-p в VS Code: узкое окно сверху по центру, без превью на пол-экрана (alt-p — показать).
          -- Для файлов, буферов, недавних, проектов и команд; поиск по тексту — с превью, там оно нужно
          layouts = {
            palette = {
              hidden = { "preview" },
              layout = {
                backdrop = false,
                row = 2,
                width = 0.45,
                min_width = 72,
                max_width = 110,
                height = 0.4,
                min_height = 10,
                max_height = 22,
                box = "vertical",
                border = "rounded",
                title = "{title} {live} {flags}",
                title_pos = "center",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
                { win = "preview", title = "{preview}", height = 0.5, border = "top" },
              },
            },
          },
          -- скрытые файлы (.env.example, .github) видны, .git и игнорируемое — нет
          sources = {
            files = { hidden = true, layout = "palette" },
            git_files = { layout = "palette" },
            buffers = { layout = "palette" },
            recent = { layout = "palette" },
            projects = { layout = "palette" },
            smart = { layout = "palette" },
            commands = { layout = "palette" },
            grep = { hidden = true },
            explorer = { hidden = true },
          },
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
