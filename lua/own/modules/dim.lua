-- Неактивные окна тусклее: окно, где ты пишешь, — ярко, соседние сплиты, дерево, терминал снизу — приглушены,
-- подсветка кода в них остаётся (просто тише). Переход фокуса — плавный. Окна поверх кода не трогаются.
-- Настройки модуля: { "level": 0.6, "animate": true, "style": "default", "by": "windows", "except": ["own_tree"] }
--   level — насколько ярко неактивное окно (1 — как активное, 0 — исчезает), animate — плавно гаснет и загорается,
--   style — рецепт vimade: "default" (гаснет всё), "minimalist" (ещё и номера, значки, ~ прячутся), "duo", "ripple"
--     (чем дальше окно от активного, тем тусклее), "paradox"; by — "windows" (каждое окно) или "buffers"
--     (сплиты с тем же файлом горят вместе); except — типы файлов, которые не гаснут.
-- Пробел u W — выключить на время.
local M = {}

local function config(opts)
  local except = opts.except or {}
  return {
    recipe = { opts.style or "default", { animate = opts.animate ~= false } },
    fadelevel = opts.level or 0.6,
    ncmode = opts.by or "windows",
    blocklist = {
      default = {
        -- одна статусная строка на всё окно (laststatus 3) — не гаснет вместе с окном
        highlights = { laststatus_3 = function() if vim.go.laststatus == 3 then return "StatusLine" end end,
          "TabLineSel", "Pmenu", "PmenuSel", "PmenuKind", "PmenuKindSel", "PmenuExtra", "PmenuExtraSel", "PmenuSbar", "PmenuThumb",
          "/^OwnSL/" },
        buf_opts = { buftype = { "prompt" } },
      },
      floats = function(win, active)
        return win.win_config.relative ~= "" and (win ~= active or win.buf_opts.buftype == "terminal")
      end,
      except = #except > 0 and { buf_opts = { filetype = except } } or nil,
    },
  }
end

function M.plugins(opts)
  return {
    {
      "TaDaa/vimade",
      event = "VeryLazy",
      opts = config(opts),
      config = function(_, o)
        require("vimade").setup(o)
        Snacks.toggle({
          name = "Тусклые неактивные окна",
          get = function() return vim.g.own_dim ~= false end,
          set = function(on)
            vim.g.own_dim = on
            vim.cmd(on and "VimadeEnable" or "VimadeDisable")
          end,
        }):map("<leader>uW")
      end,
    },
  }
end

-- settings.jsonc сохранили — новые уровень и стиль сразу
function M.reload(opts)
  local vimade = package.loaded["vimade"]
  if vimade then vimade.setup(config(opts or {})) end
end

return M
