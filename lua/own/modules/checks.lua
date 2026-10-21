-- Свои проверки без кода: раздел "checks" (в settings.jsonc или JSONC-наборе extensions/*.jsonc).
-- Команда запускается по событию, её вывод «файл:строка:столбец: текст» — замечания на строках (Go: core/extensions/checks).
--   "checks": { "go vet": { "run": "go vet ./...", "pattern": "*.go", "on": ["BufWritePost"], "cwd": "root",
--                            "severity": "warn", "format": "<регулярка с группами file, line, message>" } }
-- :Checks — прогнать проверки текущего файла сейчас. Применяется на лету.
local settings = require("own.settings")

local M = {}

local function list() return (settings.current or {}).checks or {} end

local function run(name, spec)
  require("own.ext").call("checks.run", { name = name, spec = spec }, "checks")
end

local function apply()
  local group = vim.api.nvim_create_augroup("own.checks", { clear = true })
  for name, spec in pairs(list()) do
    if type(spec) == "table" and spec.run and spec.enabled ~= false then
      vim.api.nvim_create_autocmd(spec.on or { "BufWritePost" }, {
        group = group,
        pattern = vim.split(spec.pattern or "*", ",", { trimempty = true }),
        callback = function() run(name, spec) end,
      })
    end
  end
end

function M.setup()
  apply()
  vim.api.nvim_create_user_command("Checks", function()
    local file = vim.api.nvim_buf_get_name(0)
    local n = 0
    for name, spec in pairs(list()) do
      if type(spec) == "table" and spec.run and spec.enabled ~= false and vim.regex(vim.fn.glob2regpat(spec.pattern or "*")):match_str(vim.fs.basename(file)) then
        run(name, spec)
        n = n + 1
      end
    end
    vim.notify(n > 0 and ("проверок запущено: %d"):format(n) or "для этого файла проверок нет (раздел checks)")
  end, { desc = "Прогнать свои проверки (раздел checks) для текущего файла" })
end

M.reload = apply

return M
