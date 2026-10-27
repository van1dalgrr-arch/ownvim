-- SQL (Postgres): дополнение, проверки и миграции.
--   Сервер SQL (postgres_lsp) подключается к базе проекта сам — .env DATABASE_URL или postgres из compose
--   (own.sql.db): таблицы и колонки в дополнении, неизвестная колонка — ошибкой, опасные миграции — предупреждением
--   (NOT NULL без DEFAULT, индекс без CONCURRENTLY, DROP COLUMN…), K — описание.
--   Схема из миграций: таблицы, колонки, типы, enum — даже без запущенной базы и до применения миграции
--   (own.sql.source). FROM | — таблицы, u.| — колонки, CREATE TABLE (x | — типы, после типа — NOT NULL, DEFAULT…
--   Миграции (own.sql.migrations): пробел r m — меню (новая, up, down, redo, статус), :Migrate new add_phone_to_users;
--   down пишется сам по up; в первой строке — применена ли; cmd-shift-t — up ↔ down.
--   Сниппеты — snippets/sql.json: tbl, col, fk, idx, enum, addcol, notnull, trgupd, upsert…
-- Раздел "modules": { "sql": { … } }:
--   "migrations": "" — папка миграций (по умолчанию ищется сама: migrations, db/migrations, internal/…/migrations)
--   "tool": "auto" — "migrate" (golang-migrate) | "goose"; auto — по файлам
--   "auto_down": true — down по up при сохранении, пока down не правили руками
--   "status": true — ✓ применена / ○ ждёт в первой строке миграции
--   "lsp_db": true — сервер SQL подключается к базе проекта
local settings = require("own.settings")

local M = {}

local function o() return settings.module_opts(settings.current or {}, "sql") end

local SQL = { "sql", "pgsql", "plsql" }

function M.plugins()
  return {
    {
      "saghen/blink.cmp",
      optional = true,
      opts = function(_, opts)
        opts.sources = opts.sources or {}
        local list = { "lsp", "own_sql", "snippets", "buffer" }
        if settings.enabled(settings.current or {}, "database") then table.insert(list, 3, "dadbod") end
        local per = {}
        for _, ft in ipairs(SQL) do per[ft] = list end
        opts.sources.per_filetype = vim.tbl_extend("force", opts.sources.per_filetype or {}, per)
        opts.sources.providers = opts.sources.providers or {}
        opts.sources.providers.own_sql = { name = "SQL", module = "own.sql.source", score_offset = 2 }
        -- то, что сервер SQL знает и так из базы, — один раз: у нас подробнее (тип, ограничения, файл миграции)
        local lsp = opts.sources.providers.lsp or {}
        local prev = lsp.transform_items
        lsp.transform_items = function(ctx, items)
          if vim.tbl_contains(SQL, vim.bo[ctx.bufnr or 0].filetype) then items = require("own.sql.source").dedupe(ctx, items) end
          return prev and prev(ctx, items) or items
        end
        opts.sources.providers.lsp = lsp
        return opts
      end,
    },
  }
end

--- Настройки сервера postgres_lsp: база проекта и папка миграций — когда сервер стартует для своего корня
function M.lsp(cfg)
  local user_init = cfg.on_init
  cfg.on_init = function(client, result)
    local root = client.root_dir or vim.uv.cwd()
    local add = {}
    -- свой postgres-language-server.jsonc в проекте — главнее: база и миграции оттуда
    local own_cfg = vim.uv.fs_stat(root .. "/postgres-language-server.jsonc") or vim.uv.fs_stat(root .. "/postgrestools.jsonc")
    if own_cfg then return user_init and user_init(client, result) end
    if o().lsp_db ~= false then
      local url = require("own.sql.db").project_url(root)
      if url then add.db = { connectionString = url } end
    end
    local ok, dir = pcall(require("own.sql.migrations").dir, vim.api.nvim_get_current_buf())
    if ok and dir and vim.startswith(dir, root .. "/") then add.migrations = { migrationsDir = dir:sub(#root + 2) } end
    if next(add) then
      client.settings = vim.tbl_deep_extend("keep", client.settings or {}, add)
      client:notify("workspace/didChangeConfiguration", { settings = client.settings })
    end
    if user_init then return user_init(client, result) end
  end
  return cfg
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.sql", { clear = true })
  require("own.sql.migrations").setup(group)
end

return M
