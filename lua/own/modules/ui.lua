-- Внешний вид: стартовый экран, уведомления, подсказка клавиш (which-key), линии отступов, номера и значки слева (snacks statuscolumn).
-- Snacks грузится сразу: на нём поиск, дерево, терминал и переключатели из раздела keys.
local M = {}


local settings = require("own.settings")

-- секция «project» стартового экрана: ветка, что изменено, статус compose — того проекта, где открыт nvim
local asked = {}
local function project_section(self)
  local cwd = vim.fn.getcwd()
  local items = {}
  local st = vim.fn.systemlist({ "git", "-C", cwd, "status", "--porcelain=v1", "--branch" })
  if vim.v.shell_error == 0 and st[1] then
    local branch = st[1]:match("^## No commits yet on (%S+)") or st[1]:match("^## ([^%s%.]+)")
    local ahead, behind = st[1]:match("ahead (%d+)"), st[1]:match("behind (%d+)")
    local head = { { branch or "?", hl = "Title" } }
    if ahead then head[#head + 1] = { "  ↑" .. ahead, hl = "DiagnosticWarn" } end
    if behind then head[#head + 1] = { "  ↓" .. behind, hl = "DiagnosticWarn" } end
    head[#head + 1] = #st > 1 and { ("  · изменено: %d"):format(#st - 1), hl = "Comment" } or { "  · чисто", hl = "DiagnosticOk" }
    items[#items + 1] = { text = head }
    local HL = { M = "DiagnosticWarn", A = "DiagnosticOk", D = "DiagnosticError", R = "DiagnosticInfo", ["?"] = "Comment" }
    for i = 2, math.min(#st, 6) do
      local code, file = st[i]:sub(1, 2), st[i]:sub(4)
      items[#items + 1] = { text = { { code .. " ", hl = HL[vim.trim(code):sub(1, 1)] or "Comment" }, { file, hl = "Normal" } } }
    end
    if #st > 6 then items[#items + 1] = { text = { { ("   … ещё %d"):format(#st - 6), hl = "Comment" } } } end
  end
  -- статус compose — из Go-расширения docker: спросить в фоне, ответ придёт в ext.data — и экран перерисуется
  local data
  local has_compose = false
  for _, n in ipairs({ "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }) do
    if vim.uv.fs_stat(cwd .. "/" .. n) then has_compose = true end
  end
  local ext = package.loaded["own.ext"]
  if has_compose and ext and vim.fn.executable("docker") == 1 then
    local key = "docker.status:" .. cwd
    data = ext.data[key]
    if not data and not asked[key] then
      asked[key] = true
      vim.api.nvim_create_autocmd("User", {
        pattern = "OwnExtData",
        callback = function(ev)
          if ev.data.key ~= key then return end
          pcall(self.update, self)
          return true
        end,
      })
      ext.call("docker.status", { dir = cwd }, "docker")
    end
  end
  if data and not data.down then
    local line = { { "\u{f308} compose  ", hl = "Comment" } }
    if next(data.list) == nil then line[#line + 1] = { "не запущен", hl = "Comment" } end
    for name, c in vim.spairs(data.list) do
      local ok = c.State == "running" and c.Health ~= "unhealthy"
      line[#line + 1] = { (ok and "● " or "○ ") .. name .. "  ", hl = ok and "DiagnosticOk" or "DiagnosticError" }
    end
    items[#items + 1] = { text = line }
  end
  if #items == 0 then return nil end
  items.title = vim.fs.basename(cwd)
  items.icon = "\u{e702} "
  items.indent = 2
  items.padding = 1
  return items
end

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
    project = project_section,
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
          { "<leader>a", group = "Claude" },
          { "<leader>G", group = "Go: генерация" },
          { "<leader>m", group = "мультикурсор" },
          { "<leader>r", group = "запуск" },
          { "gp", group = "посмотреть (peek)" },
          { "<leader>t", group = "тесты" },
          { "<leader>f", group = "файлы" },
          { "<leader>g", group = "git" },
          { "<leader>j", group = "нижняя панель" },
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
