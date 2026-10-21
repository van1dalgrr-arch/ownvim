-- Линтеры (nvim-lint): проверки, которых нет в языковом сервере — golangci-lint для Go, hadolint для Dockerfile.
-- Замечания — на строках, как ошибки сервера. Всё — раздел "lint" в settings.jsonc:
--   "events": ["BufReadPost", "BufWritePost", "InsertLeave"] — когда запускать
--   "languages": { "go": ["golangcilint"], … } — имена: github.com/mfussenegger/nvim-lint#available-linters
--   "linters": { "golangcilint": { "args": […] } } — настройки линтера, как в nvim-lint (cmd, args, stdin…)
-- Программы ставятся сами через mason. Всё применяется на лету.
local settings = require("own.settings")
local tools = require("own.tools")

local M = {}

local function l() return (settings.current or {}).lint or {} end

local function cmd_of(lint, name)
  local def = lint.linters[name]
  if type(def) == "function" then def = def() end
  local cmd = type(def) == "table" and def.cmd
  if type(cmd) == "function" then cmd = cmd() end
  return type(cmd) == "string" and cmd or name
end

local ensured = {}
local function apply()
  local lint = require("lint")
  lint.linters_by_ft = vim.deepcopy(l().languages or {})
  -- свои настройки — функцией: определение линтера загрузится при первом запуске, а не на старте
  -- (golangci-lint при загрузке синхронно спрашивает версию и go env — ~50 мс)
  for name, cfg in pairs(l().linters or {}) do
    lint.linters[name] = function()
      local ok, base = pcall(require, "lint.linters." .. name)
      if not ok then base = {} end
      if type(base) == "function" then base = base() end
      return vim.tbl_deep_extend("force", base, cfg)
    end
  end
end

-- программы линтеров — когда открыт файл этого языка
local function ensure_ft(ft)
  local lint = package.loaded["lint"]
  if not lint then return end
  for _, name in ipairs(lint.linters_by_ft[ft] or {}) do
    if not ensured[name] then
      ensured[name] = true
      if lint.linters[name] then
        tools.ensure_bin(cmd_of(lint, name), name, nil, nil, ft)
      else
        settings.warn(ft, ("у nvim-lint нет линтера %q — задай его в lint.linters (cmd, args, parser)"):format(name))
      end
    end
  end
end

local group
local function run()
  ensure_ft(vim.bo.filetype)
  -- линтер, которого нет в PATH, молча пропускаем — mason ещё ставит его, или о нём уже сказано в настройках
  local lint = require("lint")
  local names = vim.tbl_filter(function(name)
    return lint.linters[name] and vim.fn.executable(cmd_of(lint, name)) == 1
  end, lint._resolve_linter_by_ft(vim.bo.filetype))
  if #names > 0 then lint.try_lint(names) end
end

local function watch()
  group = vim.api.nvim_create_augroup("own.lint", { clear = true })
  vim.api.nvim_create_autocmd(l().events or { "BufReadPost", "BufWritePost", "InsertLeave" }, {
    group = group,
    -- после отрисовки: первый вызов линтера бывает тяжёлым (golangci-lint при загрузке спрашивает версию — ~50 мс)
    callback = function() vim.defer_fn(run, 150) end,
  })
end

function M.plugins()
  return {
    {
      "mfussenegger/nvim-lint",
      event = { "VeryLazy", "BufWritePost" }, -- после первой отрисовки: замечания линтера и так приходят позже
      config = function()
        apply()
        vim.defer_fn(run, 150)
      end,
    },
  }
end

function M.setup() watch() end

function M.reload()
  watch()
  if package.loaded["lint"] then
    apply()
    run()
  end
end

return M
