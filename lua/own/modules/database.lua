-- База данных (vim-dadbod): подключения слева, запрос в файле — enter/пробел S выполняет, результат —
-- таблицей; в .sql — дополнение по таблицам и колонкам базы. Раздел "database" в settings.jsonc:
--   "connections": { "local": "postgres://postgres:postgres@localhost:5432/app" } — свои подключения
--   "project_env": true — подключение проекта само: DATABASE_URL из .env в корне проекта, иначе postgres из
--     compose-файла (POSTGRES_USER/PASSWORD/DB и порт), иначе postgres://postgres:<DB_PASSWORD>@localhost:5432/<папка>
--   "save_location": "~/.local/share/ownvim/db_ui" — где лежат сохранённые запросы
-- Подключения применяются на лету.
local settings = require("own.settings")

local M = {}

local function db() return (settings.current or {}).database or {} end

local function apply()
  local dbs = vim.deepcopy(db().connections or {})
  if db().project_env ~= false then
    local url, name = require("own.sql.db").project_url()
    if url and not dbs[name] then dbs[name] = url end
  end
  vim.g.dbs = dbs
  vim.g.db_ui_save_location = vim.fn.expand(db().save_location or (vim.fn.stdpath("data") .. "/db_ui"))
end

function M.plugins()
  return {
    { "tpope/vim-dadbod", cmd = "DB" },
    {
      "kristijanhusak/vim-dadbod-ui",
      dependencies = { "tpope/vim-dadbod", { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } } },
      cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
      init = function()
        vim.g.db_ui_use_nerd_fonts = 1
        vim.g.db_ui_show_database_icon = 1
        vim.g.db_ui_auto_execute_table_helpers = 1
        vim.g.db_ui_execute_on_save = 0 -- автосохранение не должно гонять запросы
      end,
    },
    -- в .sql дополнение знает таблицы и колонки подключённой базы
    {
      "saghen/blink.cmp",
      optional = true,
      opts = function(_, opts)
        opts.sources = opts.sources or {}
        opts.sources.per_filetype = vim.tbl_extend("force", opts.sources.per_filetype or {}, {
          sql = { "lsp", "dadbod", "snippets", "buffer" },
          mysql = { "lsp", "dadbod", "snippets", "buffer" },
          plsql = { "lsp", "dadbod", "snippets", "buffer" },
        })
        opts.sources.providers = opts.sources.providers or {}
        opts.sources.providers.dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" }
        return opts
      end,
    },
  }
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("own.database", { clear = true }),
    callback = apply,
  })
end

M.reload = apply

return M
