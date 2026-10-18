-- Внешний вид: стартовый экран, уведомления, подсказка клавиш (which-key), линии отступов, номера и значки слева (snacks statuscolumn).
-- Snacks грузится сразу: на нём поиск, дерево, терминал и переключатели из раздела keys.
local M = {}


local header = [[
 ██████╗ ██╗    ██╗███╗   ██╗
██╔═══██╗██║    ██║████╗  ██║
██║   ██║██║ █╗ ██║██╔██╗ ██║
██║   ██║██║███╗██║██║╚██╗██║
╚██████╔╝╚███╔███╔╝██║ ╚████║
 ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═══╝
своя сборка · настройки в settings.jsonc]]

M.plugins = {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      notifier = { enabled = true },
      input = { enabled = true },
      indent = { enabled = true, animate = { enabled = false } },
      scope = { enabled = true },
      words = { enabled = true },
      statuscolumn = { enabled = true },
      dim = { animate = { enabled = false } },
      dashboard = {
        preset = {
          header = header,
          keys = {
            { icon = "\u{f002} ", key = "f", desc = "Найти файл", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = "\u{f1da} ", key = "r", desc = "Недавние файлы", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = "\u{f422} ", key = "g", desc = "Поиск по проекту", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = "\u{f013} ", key = "c", desc = "Мои настройки", action = ":Settings" },
            { icon = "\u{f11c} ", key = "k", desc = "Все клавиши", action = function() Snacks.picker.keymaps() end },
            { icon = "󰒲 ", key = "l", desc = "Плагины", action = ":Lazy" },
            { icon = "\u{f426} ", key = "q", desc = "Выйти", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      vim.o.statuscolumn = [[%!v:lua.require'snacks.statuscolumn'.get()]]
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      spec = {
        {
          mode = { "n", "x" },
          { "<leader><tab>", group = "вкладки" },
          { "<leader>b", group = "буферы" },
          { "<leader>c", group = "код" },
          { "<leader>d", group = "отладка" },
          { "<leader>t", group = "тесты" },
          { "<leader>f", group = "файлы" },
          { "<leader>g", group = "git" },
          { "<leader>q", group = "выход" },
          { "<leader>s", group = "поиск" },
          { "<leader>u", group = "переключатели" },
          { "<leader>w", group = "окна", proxy = "<c-w>" },
          { "<leader>x", group = "ошибки и списки" },
          { "[", group = "назад" },
          { "]", group = "вперёд" },
          { "g", group = "переход" },
          { "gs", group = "обрамление" },
          { "z", group = "складки" },
        },
      },
    },
  },
}

return M
