-- :OwnHealth (или :checkhealth own) — всё ли на месте, как dot doctor: настройки, программы, серверы, форматтеры,
-- линтеры, парсеры, шрифт, тема, скорость старта. У каждой проблемы — как починить.
local M = {}

local h = vim.health

local function settings() return require("own.settings").current or {} end

local function check_settings()
  h.start("Настройки")
  local s = require("own.settings")
  local n = 0
  for path, list in pairs(s.problems) do
    for _, d in ipairs(list) do
      n = n + 1
      h.warn(("%s:%d — %s"):format(vim.fn.fnamemodify(path, ":t"), d.lnum + 1, d.message), "открой :Settings — замечание подсвечено на строке")
    end
  end
  if n == 0 then h.ok("settings.jsonc и defaults.jsonc разобраны, замечаний нет") end
  local enabled = {}
  for name in pairs(settings().modules or {}) do
    if s.enabled(settings(), name) then enabled[#enabled + 1] = name end
  end
  h.info(("модулей включено: %d"):format(#enabled))
end

-- Go-ядро: программа ownvimd (core/), движок настроек, мост
local function check_core()
  h.start("Go-ядро (core/, ownvimd)")
  local core = require("own.core")
  if vim.fn.executable("go") ~= 1 then
    h.warn("нет go — ядро не пересоберётся после правок; настройки читает запасной Lua-движок", { "brew install go" })
  end
  if not vim.uv.fs_stat(core.bin) then
    return h.error("ownvimd не собран: " .. tostring(core.error or "?"), { "cd ~/dev/ownvim/core && go build -o " .. core.bin .. " ./cmd/ownvimd" })
  end
  local v = vim.system({ core.bin, "version" }, { text = true }):wait(3000)
  h.ok(("ownvimd %s — %s"):format(vim.trim(v.stdout or "?"), core.bin))
  if core.stale() then h.warn("Go-код новее программы — пересоберётся в фоне после старта (или :lua require'own.core'.build())") end
  if core.error then h.error("последняя сборка упала:\n" .. core.error) end
  local cache = vim.fn.stdpath("data") .. "/own-settings.cache.json"
  if vim.uv.fs_stat(cache) then h.ok("настройки читаются из кэша ядра: " .. cache) else h.warn("кэша настроек нет — соберётся при следующем чтении") end
  local ok, res = pcall(function()
    local t = vim.uv.hrtime()
    for _ = 1, 50 do core.request("ping") end
    return (vim.uv.hrtime() - t) / 1e6 / 50
  end)
  if ok then h.ok(("мост работает: %.3f мс на вызов"):format(res)) else h.error("мост не отвечает: " .. tostring(res)) end
end

local function check_programs()
  h.start("Программы")
  local need = {
    { "git", "brew install git" },
    { "rg", "brew install ripgrep — поиск по проекту" },
    { "tree-sitter", "brew install tree-sitter — парсеры языков (подсветка)" },
    { "curl", "нужен для установки серверов и тем" },
  }
  local nice = {
    { "lazygit", "brew install lazygit — alt-g" },
    { "go", "brew install go" },
    { "fd", "brew install fd — быстрее поиск файлов" },
    { "freeze", "brew install charmbracelet/tap/freeze — скриншот кода (пробел P)" },
    { "cmake", "brew install cmake — задачи C/C++" },
    { "cargo", "brew install rustup && rustup default stable — Rust" },
  }
  for _, p in ipairs(need) do
    if vim.fn.executable(p[1]) == 1 then h.ok(p[1]) else h.error(p[1] .. " не найден", p[2]) end
  end
  for _, p in ipairs(nice) do
    if vim.fn.executable(p[1]) == 1 then h.ok(p[1]) else h.info(p[1] .. " нет — " .. p[2]) end
  end
  local v = vim.version()
  if vim.version.lt(v, { 0, 12, 0 }) then h.error("Neovim " .. tostring(v) .. " — нужен 0.12+", "brew upgrade neovim") else h.ok("Neovim " .. tostring(v)) end
end

local function check_lsp()
  h.start("Языковые серверы")
  for name, v in pairs((settings().lsp or {}).servers or {}) do
    if v ~= false then
      local cfg = vim.lsp.config[name]
      local cmd = cfg and cfg.cmd
      if type(cmd) == "table" then
        if vim.fn.executable(cmd[1]) == 1 then h.ok(name .. " — " .. cmd[1])
        else h.warn(name .. ": нет программы " .. cmd[1], "откроется файл этого языка — mason поставит сам; или :Mason") end
      else
        local pkg = require("own.tools").package_for_lsp_cached(name)
        if pkg and not require("own.tools").installed(pkg) then h.warn(name .. ": пакет " .. pkg .. " не стоит", ":Mason") else h.ok(name) end
      end
    end
  end
end

local function check_tools(section, label)
  h.start(label)
  local cfg = settings()[section] or {}
  local seen = {}
  for ft, list in pairs(cfg.languages or {}) do
    for _, name in ipairs(list) do
      if not seen[name] then
        seen[name] = true
        local bin = name:gsub("_", "-"):gsub("^golangcilint$", "golangci-lint"):gsub("^clang%-format$", "clang-format")
        local ok, def = pcall(require, (section == "format" and "conform.formatters." or "lint.linters.") .. name)
        if ok and type(def) == "table" and type(def.command or def.cmd) == "string" then bin = def.command or def.cmd end
        if vim.fn.executable(bin) == 1 then h.ok(("%s (%s)"):format(name, ft))
        else h.info(("%s (%s): нет %s — поставится при первом файле %s"):format(name, ft, bin, ft)) end
      end
    end
  end
end

local function check_treesitter()
  h.start("Подсветка (treesitter)")
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok then return h.warn("nvim-treesitter не загружен", "модуль treesitter выключен?") end
  local have = {}
  for _, l in ipairs(ts.get_installed()) do have[l] = true end
  local miss = {}
  for _, l in ipairs(((settings().modules or {}).treesitter or {}).languages or {}) do
    if not have[l] then miss[#miss + 1] = l end
  end
  if #miss == 0 then h.ok(("парсеров: %d"):format(vim.tbl_count(have)))
  else h.warn("нет парсеров: " .. table.concat(miss, ", "), ":TSInstall " .. table.concat(miss, " ")) end
end

local function check_look()
  h.start("Вид")
  h.info("тема: " .. tostring(vim.g.colors_name))
  local f = settings().font or {}
  if f.family then
    local file = vim.fn.expand("~/.config/ghostty/ownvim.ghostty")
    if vim.uv.fs_stat(file) then h.ok("шрифт " .. f.family .. " — записан в Ghostty")
    else h.warn("шрифт задан, но Ghostty-файла нет", "это Ghostty? шрифт задаёт терминал") end
  else
    h.info("шрифт — из терминала (раздел font пуст)")
  end
  if not vim.o.termguicolors then h.warn("нет 24-битного цвета", "терминал без truecolor: Ghostty, iTerm2, WezTerm, kitty") end
end

local function check_speed()
  h.start("Скорость старта")
  local out = vim.fn.tempname()
  vim.fn.system({ "nvim", "--headless", "--startuptime", out, "+qa" })
  local ms
  for line in io.lines(out) do
    local t = line:match("^(%d+%.%d+).*NVIM STARTED")
    if t then ms = tonumber(t) end
  end
  os.remove(out)
  if not ms then return h.info("не измерить") end
  local text = ("%.0f мс без файла"):format(ms)
  if ms < 60 then h.ok(text) elseif ms < 120 then h.warn(text, ":Lazy profile — что грузится дольше всего")
  else h.error(text, ":Lazy profile — что грузится дольше всего; выключи лишние модули") end
end

function M.check()
  check_settings()
  check_core()
  check_programs()
  check_lsp()
  check_tools("format", "Форматтеры")
  check_tools("lint", "Линтеры")
  check_treesitter()
  check_look()
  check_speed()
end

return M
