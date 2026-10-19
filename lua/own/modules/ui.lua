-- Внешний вид: стартовый экран, уведомления, подсказка клавиш (which-key), линии отступов, номера и значки слева (snacks statuscolumn).
-- Snacks грузится сразу: на нём поиск, дерево, терминал и переключатели из раздела keys.
local M = {}


local settings = require("own.settings")

-- стартовый экран из раздела "dashboard": header, buttons (do — действие из keys, :команда или клавиши), sections
local function dashboard()
  local d = (settings.current or {}).dashboard or {}
  local keys = {}
  for _, b in ipairs(d.buttons or {}) do
    local what = b["do"] or ""
    local action = what
    local fn = require("own.actions").get(what)
    if fn then
      action = type(fn) == "function" and fn or function() vim.api.nvim_feedkeys(vim.keycode(fn), "m", false) end
    end
    keys[#keys + 1] = { icon = (b.icon or "") .. " ", key = b.key, desc = b.desc or what, action = action }
  end
  local SECTIONS = {
    header = { section = "header" },
    buttons = { section = "keys", gap = 1, padding = 1 },
    recent = { icon = "\u{f1da} ", title = "Недавние файлы", section = "recent_files", cwd = true, indent = 2, padding = 1, limit = d.recent or 5 },
    projects = { icon = "\u{f07b} ", title = "Проекты", section = "projects", indent = 2, padding = 1, limit = d.projects or 5 },
    startup = { section = "startup" },
  }
  local sections = {}
  for _, name in ipairs(d.sections or { "header", "buttons", "startup" }) do
    sections[#sections + 1] = SECTIONS[name] or { text = name, align = "center", padding = 1 }
  end
  local header = d.header
  if type(header) == "table" then header = table.concat(header, "\n") end
  return { preset = { header = header or "ownvim", keys = keys }, sections = sections }
end

function M.plugins() return {
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
      dashboard = dashboard(),
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
          { "<leader>gh", group = "куски изменений" },
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
} end

return M
