-- Автодополнение (blink.cmp): меню при наборе, описание рядом, подсказка аргументов, сниппеты.
-- Всё — раздел "completion" в settings.jsonc:
--   "sources": ["lsp", "path", "snippets", "buffer"] — откуда предлагать (на лету)
--   "ghost_text": true — серым продолжение прямо в строке (на лету)
--   "auto_show": true — меню само, без ctrl-space (на лету)
--   "documentation": true — описание выбранного справа (на лету)
--   "signature": true — подсказка аргументов при наборе вызова
--   "auto_brackets": true — скобки после функции
--   "friendly_snippets": true — готовый набор сниппетов для всех языков; false — только свои
--   "keymap": "vscode" — tab и enter принимают, tab в шаблоне — к следующему полю; "enter" — только enter;
--             "super-tab" — только tab; "default" — ctrl-y
--   "max_height": 10, "border": "rounded"
--   "blink": { … } — любые настройки blink.cmp как есть (cmp.saghen.dev/configuration/reference) — поверх всего выше
-- Свои сниппеты — snippets/<язык>.json в формате VS Code (рядом с settings.jsonc).
local settings = require("own.settings")

local M = {}

local LIVE = { sources = true, ghost_text = true, auto_show = true, documentation = true }

local function c() return (settings.current or {}).completion or {} end
local function on(key) return c()[key] ~= false end

local function build()
  local o = c()
  local border = o.border or "rounded"
  local opts = {
    keymap = (o.keymap or "vscode") == "vscode" and {
      -- как в VS Code: tab и enter принимают подсказку; нет подсказки — tab прыгает по полям шаблона, иначе — отступ
      preset = "enter",
      ["<Tab>"] = { "select_and_accept", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
      ["<C-y>"] = { "select_and_accept" },
    } or { preset = o.keymap, ["<C-y>"] = { "select_and_accept" } },
    appearance = { nerd_font_variant = "mono" },
    completion = {
      accept = { auto_brackets = { enabled = o.auto_brackets ~= false } },
      menu = {
        auto_show = on("auto_show"),
        border = border,
        max_height = o.max_height or 10,
        draw = {
          treesitter = { "lsp" },
          -- значок вида — из темы иконок (mini.icons, раздел icons), если она включена
          components = {
            kind_icon = {
              text = function(ctx)
                local ok, icons = pcall(require, "mini.icons")
                return (ok and icons.get("lsp", ctx.kind) or ctx.kind_icon) .. ctx.icon_gap
              end,
              highlight = function(ctx)
                local ok, icons = pcall(require, "mini.icons")
                return ok and select(2, icons.get("lsp", ctx.kind)) or ctx.kind_hl
              end,
            },
          },
        },
      },
      documentation = { auto_show = on("documentation"), auto_show_delay_ms = 200, window = { border = border } },
      ghost_text = { enabled = on("ghost_text") },
      list = { selection = { preselect = true, auto_insert = false } },
    },
    signature = { enabled = o.signature ~= false, window = { border = border } },
    sources = {
      -- сниппеты: свои из snippets/ (blink читает эту папку конфига сам) + friendly-snippets
      default = function() return c().sources or { "lsp", "path", "snippets", "buffer" } end,
      providers = { snippets = { opts = { friendly_snippets = o.friendly_snippets ~= false } } },
    },
    cmdline = { enabled = true, completion = { menu = { auto_show = true } } },
    fuzzy = { implementation = "prefer_rust_with_warning" },
  }
  return vim.tbl_deep_extend("force", opts, o.blink or {})
end

local applied -- то, что требует перезапуска, — чтобы честно сказать об этом

local function static(o)
  local s = vim.deepcopy(o)
  for k in pairs(LIVE) do s[k] = nil end
  return s
end

function M.plugins()
  return {
    {
      "saghen/blink.cmp",
      version = "1.*", -- готовая быстрая сборка поиска (Rust) скачивается сама
      lazy = false, -- при загрузке отдаёт серверам свои возможности — до их старта
      dependencies = { "rafamadriz/friendly-snippets" },
      opts = build,
    },
  }
end

function M.setup() applied = static(c()) end

-- blink читает свой конфиг на каждом показе меню — поменять поля в нём и есть «применить на лету»
local function apply_live()
  local ok, cfg = pcall(require, "blink.cmp.config")
  if not ok then return end
  cfg.completion.menu.auto_show = on("auto_show")
  cfg.completion.documentation.auto_show = on("documentation")
  cfg.completion.ghost_text.enabled = on("ghost_text")
end

function M.reload()
  apply_live()
  local now = static(c())
  if not vim.deep_equal(now, applied) then
    vim.notify("completion: sources, ghost_text, auto_show, documentation — уже применились; остальное — после :restart", vim.log.levels.WARN)
  end
end

return M
