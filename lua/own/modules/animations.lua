-- Плавность, как в VS Code: курсор плавно перелетает (и при наборе — cursorSmoothCaretAnimation), прокрутка
-- плавная, рамка блока под курсором проявляется. Раздел "animations" — каждое отдельно, на лету:
--   "cursor": { "enabled": true, "insert": true, "stiffness": 0.8, "trailing_stiffness": 0.6, "between_buffers": true }
--     stiffness — скорость головы (1 — мгновенно), trailing_stiffness — как быстро догоняет хвост
--   "scroll": { "enabled": true, "duration_ms": 150 }
--   "indent_scope": { "enabled": false } — рамка текущего блока рисуется плавно
local settings = require("own.settings")

local M = {}

local function a() return (settings.current or {}).animations or {} end

local function apply()
  local o = a()
  local cur = o.cursor or {}
  local ok, smear = pcall(require, "smear_cursor")
  if ok then
    smear.stiffness = cur.stiffness or 0.8
    smear.trailing_stiffness = cur.trailing_stiffness or 0.6
    smear.smear_insert_mode = cur.insert ~= false
    smear.smear_between_buffers = cur.between_buffers ~= false
    smear.enabled = cur.enabled ~= false
  end
  if rawget(_G, "Snacks") then
    -- snacks читает свой конфиг при включении: поправить и включить заново
    local sc = o.scroll or {}
    Snacks.config.scroll = vim.tbl_deep_extend("force", Snacks.config.scroll or {},
      { animate = { duration = { total = sc.duration_ms or 150 } } })
    Snacks.scroll.disable()
    if sc.enabled ~= false then Snacks.scroll.enable() end
    Snacks.config.indent = vim.tbl_deep_extend("force", Snacks.config.indent or {},
      { animate = { enabled = (o.indent_scope or {}).enabled == true } })
    if Snacks.indent.enabled then
      Snacks.indent.disable()
      Snacks.indent.enable()
    end
  end
end

function M.plugins()
  return {
    {
      "sphamba/smear-cursor.nvim",
      event = "VeryLazy",
      opts = { hide_target_hack = true, cursor_color = "none", never_draw_over_target = true },
      config = function(_, opts)
        require("smear_cursor").setup(opts)
        apply()
      end,
    },
  }
end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    group = vim.api.nvim_create_augroup("own.animations", { clear = true }),
    callback = apply,
  })
end

M.reload = apply

return M
