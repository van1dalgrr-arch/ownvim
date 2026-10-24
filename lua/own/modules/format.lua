-- Форматирование (conform.nvim): при сохранении и по пробел c f. Всё — раздел "format" в settings.jsonc:
--   "on_save": true — форматировать при записи (и автосохранении); пробел u f — выкл на время
--   "timeout_ms": 3000
--   "lsp": "fallback" — языковой сервер форматирует, если для языка нет своих форматтеров;
--          "never" — никогда, "prefer" — сервер вместо форматтеров, "first"/"last" — вместе с ними
--   "languages": { "go": ["goimports", "gofumpt"], … } — по порядку; имена — github.com/stevearc/conform.nvim#formatters
--   "formatters": { "pg_format": { "prepend_args": […] } } — настройки форматтера, как в conform (command, args…)
-- Программы ставятся сами через mason. Всё применяется на лету.
local settings = require("own.settings")
local tools = require("own.tools")

local M = {}

local function f() return (settings.current or {}).format or {} end

-- какая программа нужна форматтеру: из своих настроек, из conform или его имя
local function command_of(name)
  local own = (f().formatters or {})[name]
  if type(own) == "table" and type(own.command) == "string" then return own.command end
  local ok, def = pcall(require, "conform.formatters." .. name)
  if ok and type(def) == "table" and type(def.command) == "string" then return def.command end
  return name
end

-- программы форматтеров — когда открыт файл этого языка (а не все сразу при старте)
local ensured = {}
local function ensure_ft(ft)
  for _, name in ipairs((f().languages or {})[ft] or {}) do
    if not ensured[name] then
      ensured[name] = true
      local bin = command_of(name)
      tools.ensure_bin(bin, name, nil,
        (bin == "rustfmt" and "rustfmt берётся из rustup: brew install rustup && rustup default stable" or ("нет программы %q для форматтера %s"):format(bin, name)), ft)
    end
  end
end

local function apply()
  local conform = require("conform")
  conform.formatters_by_ft = vim.deepcopy(f().languages or {})
  for name, cfg in pairs(f().formatters or {}) do conform.formatters[name] = cfg end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then ensure_ft(vim.bo[buf].filetype) end
  end
end

local function format_opts()
  local o = f()
  return { timeout_ms = o.timeout_ms or 3000, lsp_format = o.lsp or "fallback" }
end

function M.plugins()
  return {
    {
      "stevearc/conform.nvim",
      event = "BufWritePre",
      cmd = "ConformInfo",
      config = function()
        require("conform").setup({ notify_on_error = true })
        apply()
      end,
    },
  }
end

function M.format(buf, quiet)
  require("conform").format(vim.tbl_extend("force", format_opts(), { bufnr = buf or 0, quiet = quiet }))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.format", { clear = true })
  vim.api.nvim_create_autocmd("FileType", { group = group, callback = function(ev) ensure_ft(ev.match) end })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function(ev)
      if f().on_save == false or vim.g.autoformat == false or vim.b[ev.buf].autoformat == false then return end
      -- автосохранение — молча: ошибка форматтера на недописанном коде уходит в :ConformInfo, не в уведомление
      M.format(ev.buf, vim.b[ev.buf].own_autosave == true)
    end,
  })
end

function M.reload()
  if package.loaded["conform"] then return apply() end
  -- conform ещё не загружен (грузится при первом сохранении) — программы ставим уже сейчас
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then ensure_ft(vim.bo[buf].filetype) end
  end
end

return M
