-- ownvim — своя сборка Neovim. Порядок старта:
--   1. настройки: defaults.jsonc + settings.jsonc (lua/own/settings.lua)
--   2. globals и options — до плагинов (leader должен быть известен заранее)
--   3. lazy.nvim: плагины включённых модулей (lua/own/modules/*) + раздел plugins
--   4. setup модулей, тема, клавиши
--   5. слежка за settings.jsonc: сохранил — применилось
local settings = require("own.settings")

local M = {}

local function apply_globals(s)
  for k, v in pairs(s.globals or {}) do vim.g[k] = v end
end

local function apply_options(s)
  for k, v in pairs(s.options or {}) do
    local ok, err = pcall(function()
      if type(v) == "table" then vim.opt[k] = v else vim.o[k] = v end
    end)
    if not ok then settings.warn(k, tostring(err):gsub("^.-: ", "")) end
  end
end

local function module_names(s)
  local names = {}
  for name in pairs(s.modules or {}) do
    if settings.enabled(s, name) then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function module(name)
  local ok, mod = pcall(require, "own.modules." .. name)
  if not ok then
    settings.warn(name, "модуль не загрузился: " .. tostring(mod))
    return nil
  end
  return mod
end

-- спецификация для lazy.nvim
local function spec(s)
  local out = {}
  for _, name in ipairs(module_names(s)) do
    local mod = module(name)
    local plugins = mod and mod.plugins
    if type(plugins) == "function" then plugins = plugins(settings.module_opts(s, name)) end
    vim.list_extend(out, plugins or {})
  end
  -- раздел plugins: "автор/плагин": true | false | { opts, event, keys, … как в lazy.nvim }
  for repo, v in pairs(s.plugins or {}) do
    if v == false then
      out[#out + 1] = { repo, enabled = false }
    elseif v == true then
      out[#out + 1] = { repo }
    elseif type(v) == "table" then
      local p = vim.deepcopy(v)
      p[1] = repo
      out[#out + 1] = p
    end
  end
  return out
end

local function lazy_bootstrap()
  local path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not vim.uv.fs_stat(path) then
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", path })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({ { "lazy.nvim не скачался:\n", "ErrorMsg" }, { out, "WarningMsg" } }, true, {})
      return false
    end
  end
  vim.opt.rtp:prepend(path)
  return true
end

local function apply_theme(s)
  if settings.enabled(s, "themes") then
    require("own.modules.themes").apply(s.theme)
  elseif s.theme and s.theme ~= "auto" then
    pcall(vim.cmd.colorscheme, s.theme)
  end
end

local function apply_keys(s)
  local ru = settings.enabled(s, "russian") and settings.module_opts(s, "russian").alt_keys ~= false
  require("own.keys").apply(s.keys, ru)
end

-- что требует перезапуска: набор модулей и раздел plugins
local function needs_restart(new, old)
  return not vim.deep_equal(module_names(new), module_names(old)) or not vim.deep_equal(new.plugins or {}, old.plugins or {})
end

local function on_change(new, old)
  apply_globals(new)
  apply_options(new)
  for _, name in ipairs(module_names(new)) do
    local mod = package.loaded["own.modules." .. name]
    if mod and mod.reload then mod.reload(settings.module_opts(new, name)) end
  end
  apply_theme(new)
  apply_keys(new)
  settings.show_problems()
  if needs_restart(new, old) then
    vim.notify("модули или плагины поменялись — :restart, чтобы они встали", vim.log.levels.WARN)
  else
    vim.notify("настройки применены")
  end
end

function M.setup()
  local s, err = settings.load()
  if not s then
    -- сломанный settings.jsonc не должен ломать редактор: стартуем на умолчаниях
    vim.schedule(function() vim.notify("settings.jsonc не прочитан, работаю на умолчаниях: " .. err, vim.log.levels.ERROR) end)
    s = settings.load(true)
    if not s then error("defaults.jsonc сломан: " .. err) end
  end
  settings.current = s

  apply_globals(s)
  apply_options(s)

  if lazy_bootstrap() then
    require("lazy").setup({
      spec = spec(s),
      defaults = { lazy = false, version = false },
      install = { colorscheme = { "tokyonight", "habamax" } },
      rocks = { enabled = false },
      checker = { enabled = false },
      change_detection = { notify = false },
      performance = { rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" } } },
    })
  end

  for _, name in ipairs(module_names(s)) do
    local mod = module(name)
    if mod and mod.setup then
      local ok, e = pcall(mod.setup, settings.module_opts(s, name))
      if not ok then settings.warn(name, "setup упал: " .. tostring(e)) end
    end
  end
  apply_theme(s)
  apply_keys(s)

  require("own.auto").setup()
  require("own.store").setup()
  require("own.tree").setup()
  vim.api.nvim_create_user_command("OwnHealth", "checkhealth own", { desc = "Всё ли на месте" })
  vim.api.nvim_create_user_command("Settings", function(a) settings.open(a.args) end, {
    nargs = "?",
    complete = function() return { "defaults" } end,
    desc = "Открыть settings.jsonc (или defaults)",
  })
  settings.watch(on_change)
  -- JSON-схема для подсказок в settings.jsonc — после отрисовки и при каждом сохранении настроек
  local function schema() pcall(require("own.schema").build) end
  vim.defer_fn(schema, 300)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("own.schema", { clear = true }),
    pattern = { "*.jsonc", "*.json" },
    callback = function() vim.schedule(schema) end,
  })
  vim.schedule(function()
    local n = 0
    for _, list in pairs(settings.problems) do n = n + #list end
    if n > 0 then vim.notify(("в настройках %d замечаний — :Settings"):format(n), vim.log.levels.WARN) end
  end)
end

return M
