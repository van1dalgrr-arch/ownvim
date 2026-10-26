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

-- цвета стартового экрана — из текущей темы (любой): градиент заголовка от акцента к синему, клавиши цветом акцента
local function hex(group, attr)
  local v = vim.api.nvim_get_hl(0, { name = group, link = false })[attr or "fg"]
  return v and ("#%06x"):format(v) or nil
end

local GRADIENT = 6
local function dash_colors()
  local color = require("own.theme.color")
  local bg = hex("Normal", "bg") or (vim.o.background == "light" and "#ffffff" or "#000000")
  local from = hex("OwnIconAccent") or hex("Statement") or hex("Title") or "#bb9af7"
  -- второй цвет — заметно другой: ключевые слова, функции или типы (у Sunset акцент и функции оба розовые)
  local to
  for _, g in ipairs({ "Statement", "Function", "Type", "Special" }) do
    local v = hex(g)
    if v and v:lower() ~= from:lower() then to = v break end
  end
  to = to or "#7aa2f7"
  for i = 1, GRADIENT do
    vim.api.nvim_set_hl(0, "OwnDashGrad" .. i, { fg = color.blend(to, from, (i - 1) / (GRADIENT - 1)), bold = true })
  end
  vim.api.nvim_set_hl(0, "OwnDashKey", { fg = from, bold = true })
  vim.api.nvim_set_hl(0, "OwnDashKeyBracket", { fg = color.blend(from, bg, 0.45) })
  vim.api.nvim_set_hl(0, "OwnDashTagline", { fg = hex("Comment") or color.blend(hex("Normal") or "#cccccc", bg, 0.5), italic = true })
end

-- заголовок: строки из «█╗» — градиентом, остальные (подпись) — тихим курсивом; каждая строка по центру
local function header_section(header)
  local lines = type(header) == "table" and header or vim.split(header or "ownvim", "\n", { plain = true })
  return function()
    dash_colors()
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, vim.api.nvim_strwidth(l)) end
    -- блоки и рамки (█ ╗ ═) — по регулярке vim: в шаблонах Lua диапазоны байтовые
    local function is_art(l) return vim.fn.match(l, [=[[\u2580-\u259f\u2500-\u257f]]=]) >= 0 end
    local total = #vim.tbl_filter(is_art, lines)
    local texts, n, prev_art = {}, 0, false
    for i, l in ipairs(lines) do
      local art = is_art(l)
      local hl = "OwnDashTagline"
      if art then
        n = n + 1
        hl = "OwnDashGrad" .. (total > 1 and math.floor((n - 1) * (GRADIENT - 1) / (total - 1) + 1.5) or 1)
      end
      local gap = (prev_art and not art) and "\n" or "" -- воздух между логотипом и подписью
      local pad = (" "):rep(math.floor((w - vim.api.nvim_strwidth(l)) / 2))
      texts[#texts + 1] = { gap .. pad .. l .. (i < #lines and "\n" or ""), hl = hl }
      prev_art = art
    end
    return { text = texts, align = "center", padding = 2 }
  end
end

-- «⚡ 43 мс · 6 из 80 плагинов» — по-русски, вместо английской строки snacks
local function startup_section()
  local ok, stats = pcall(function() return require("lazy.stats").stats() end)
  if not ok or not stats then return nil end
  local ms = math.floor(stats.startuptime + 0.5)
  return {
    align = "center",
    padding = 1,
    text = {
      { "\u{f0e7}  ", hl = "OwnDashGrad1" },
      { ("%d мс"):format(ms), hl = "OwnDashKey" },
      { "  ·  ", hl = "footer" },
      { ("%d из %d плагинов загружено"):format(stats.loaded, stats.count), hl = "footer" },
    },
  }
end

-- «info» — рамка, как у fastfetch и промпта dotfiles:
-- ╭─( dev㉿van1dal )─────────────╮
-- │  nvim     0.12.0            │
-- │ ⚡ старт    43 мс · 6/80 …    │ …
local function info_section()
  dash_colors()
  local ok, stats = pcall(function() return require("lazy.stats").stats() end)
  local v = vim.version()
  local rows = {
    { "\u{e62b}", "nvim", ("%d.%d.%d"):format(v.major, v.minor, v.patch) },
    { "\u{f0e7}", "старт", ok and stats and ("%d мс · %d/%d плагинов"):format(math.floor(stats.startuptime + 0.5), stats.loaded, stats.count) or "—" },
    { "\u{f1fc}", "тема", vim.g.colors_name or "—" },
    { "\u{f073}", "сегодня", os.date("%d.%m.%Y · %H:%M") },
  }
  local who = (vim.env.USER or "me") .. "㉿" .. (vim.fn.hostname():gsub("%..*$", ""))
  local W = vim.api.nvim_strwidth
  local KEY = 9
  local inner = W(who) + 6
  for _, r in ipairs(rows) do inner = math.max(inner, W(r[1]) + 1 + KEY + W(r[3]) + 2) end
  local F, texts = "OwnDashKeyBracket", {}
  local function add(s, hl) texts[#texts + 1] = { s, hl = hl } end
  add("╭─( ", F); add(who, "OwnDashKey"); add(" )" .. ("─"):rep(inner - W(who) - 5) .. "╮\n", F)
  for i, r in ipairs(rows) do
    local core = W(r[1]) + 1 + KEY + W(r[3])
    add("│ ", F)
    add(r[1] .. " ", "OwnDashGrad" .. math.min(i + 1, GRADIENT))
    add(r[2] .. (" "):rep(KEY - W(r[2])), "OwnDashTagline")
    add(r[3], "Normal")
    add((" "):rep(inner - core - 1) .. "│\n", F)
  end
  add("╰" .. ("─"):rep(inner) .. "╯", F)
  return { text = texts, align = "center", padding = 2 }
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
  local names = d.sections or { "header", "buttons", "startup" }
  -- кнопки с воздухом, если на экране только они; с недавними файлами и проектами — плотнее, чтобы всё влезло
  local busy = #vim.tbl_filter(function(n) return n == "recent" or n == "projects" or n == "project" end, names) > 0
  local SECTIONS = {
    header = header_section(d.header),
    buttons = { section = "keys", gap = busy and 0 or 1, padding = 2 },
    recent = { icon = "\u{f1da} ", title = "Недавние файлы", section = "recent_files", cwd = true, indent = 2, padding = 1, limit = d.recent or 5 },
    projects = { icon = "\u{f07b} ", title = "Проекты", section = "projects", indent = 2, padding = 1, limit = d.projects or 5 },
    startup = startup_section,
    info = info_section,
    project = project_section,
  }
  local sections = {}
  for _, name in ipairs(names) do
    sections[#sections + 1] = SECTIONS[name] or { text = name, align = "center", padding = 1 }
  end
  return {
    preset = { keys = keys },
    sections = sections,
    -- клавиша — цветом акцента в тихих скобках: [f]
    formats = {
      key = function(item)
        return { { "[", hl = "OwnDashKeyBracket" }, { item.key, hl = "OwnDashKey" }, { "]", hl = "OwnDashKeyBracket" } }
      end,
    },
  }
end

-- сообщения и командная строка — новый интерфейс nvim 0.12 (ui2): длинное сообщение сворачивается в «[+3]»
-- вместо «Press ENTER» и не сдвигает экран; g< — все сообщения. "appearance": { "messages": "classic" } — как было
local function messages()
  local want = ((settings.current or {}).appearance or {}).messages ~= "classic"
  local ok, ui2 = pcall(require, "vim._core.ui2")
  if not ok or M.ui2 == want then return end
  if want or M.ui2 ~= nil then pcall(ui2.enable, { enable = want }) end
  M.ui2 = want
end

function M.setup() messages(); require("own.frames").setup(); require("own.intro").setup() end
function M.reload() messages(); require("own.frames").reload() end

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
      -- номер текущей строки со стрелкой ❯ (appearance.frames) — обёртка над колонкой snacks
      vim.o.statuscolumn = require("own.frames").on() and [[%!v:lua.require'own.frames'.statuscolumn()]]
        or [[%!v:lua.require'snacks.statuscolumn'.get()]]
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      -- клавиша ─ описание: линией, как рамки ownvim (appearance.frames); заголовок окна — в скобках, через own.frames
      -- значки по смыслу описания — у всех пунктов, а не только у тех, что which-key узнаёт по-английски.
      -- Описания по-русски, а :lower() в Lua кириллицу не трогает — поэтому основы слов без первой буквы
      icons = {
        -- клавиша ─ описание: линией, как рамки ownvim (appearance.frames); заголовок окна — в скобках (own.frames)
        separator = require("own.frames").on() and "─" or "➜",
        rules = {
          { pattern = "ерев", icon = "\u{f0645} ", color = "green" },
          { pattern = "уфер", icon = "\u{f04e9} ", color = "cyan" },
          { pattern = "азделить", icon = "\u{eb56} ", color = "blue" },
          { pattern = "кно", icon = "\u{eb7f} ", color = "blue" },
          { pattern = "кна", icon = "\u{eb7f} ", color = "blue" },
          { pattern = "вкладк", icon = "\u{f04e9} ", color = "blue" },
          { pattern = "лавиш", icon = "\u{f030c} ", color = "purple" },
          { pattern = "лагин", icon = "\u{f487} ", color = "purple" },
          { pattern = "ведомлен", icon = "\u{f009a} ", color = "yellow" },
          { pattern = "еудобств", icon = "\u{f249} ", color = "orange" },
          { pattern = "опирован", icon = "\u{f0147} ", color = "yellow" },
          { pattern = "криншот", icon = "\u{f0100} ", color = "purple" },
          { pattern = "равок", icon = "\u{f1da} ", color = "orange" },
          { pattern = "оманд", icon = "\u{f120} ", color = "cyan" },
          { pattern = "данных", icon = "\u{f1c0} ", color = "azure" },
          { pattern = "есси", icon = "\u{f021} ", color = "azure" },
          { pattern = "ерминал", icon = "\u{ea85} ", color = "red" },
          { pattern = "тест", icon = "\u{f0668} ", color = "green" },
          { pattern = "Тест", icon = "\u{f0668} ", color = "green" },
          { pattern = "тлад", icon = "\u{f188} ", color = "red" },
          { pattern = "ормат", icon = "\u{f0262} ", color = "purple" },
          { pattern = "ереимен", icon = "\u{f0455} ", color = "orange" },
          { pattern = "шибк", icon = "\u{f0159} ", color = "red" },
          { pattern = "ультикурсор", icon = "\u{f01c0} ", color = "purple" },
          { pattern = "анель", icon = "\u{f018d} ", color = "blue" },
          { pattern = "енерац", icon = "\u{f0626} ", color = "cyan" },
          { pattern = "ереключ", icon = "\u{f205} ", color = "grey" },
          { pattern = "астройк", icon = "\u{f013} ", color = "grey" },
          { pattern = "апуск", icon = "\u{f04b} ", color = "green" },
          { pattern = "ыход", icon = "\u{f05fc} ", color = "red" },
          { pattern = "ыйти", icon = "\u{f05fc} ", color = "red" },
          { pattern = "складк", icon = "\u{f0dc} ", color = "grey" },
          { pattern = "брамлен", icon = "\u{f016a} ", color = "purple" },
          { pattern = "уски", icon = "\u{f440} ", color = "orange" },
          { pattern = "claude", icon = "\u{f06a9} ", color = "orange" },
          { pattern = "kubernetes", icon = "\u{f10fe} ", color = "blue" },
          { pattern = "оиск", icon = "\u{f002} ", color = "green" },
          { pattern = "айти", icon = "\u{f002} ", color = "green" },
          { pattern = "айл", icon = "\u{f0214} ", color = "cyan" },
          { pattern = "ереход", icon = "\u{f061} ", color = "blue" },
          { pattern = "код", icon = "\u{f121} ", color = "cyan" },
          { pattern = "Код", icon = "\u{f121} ", color = "cyan" },
        },
      },
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
