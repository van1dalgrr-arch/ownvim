-- Плавность, как в VS Code: курсор плавно перелетает (и при наборе — cursorSmoothCaretAnimation), прокрутка
-- плавная, рамка блока под курсором проявляется. Раздел "animations" — каждое отдельно, на лету:
--   "cursor": { "enabled": true, "insert": true, "stiffness": 0.8, "trailing_stiffness": 0.6,
--               "insert_stiffness": 0.9, "min_distance": 2, "between_buffers": true }
--     stiffness — скорость головы (1 — мгновенно), trailing_stiffness — как быстро догоняет хвост,
--     insert_stiffness — то же во вставке (быстрее: набор не должен тянуться),
--     min_distance — сдвиг короче стольких символов — без шлейфа (2: шаг на символ — набор, h/l — мгновенно)
--   "scroll": { "enabled": true, "duration_ms": 100 }
--   "indent_scope": { "enabled": false } — рамка текущего блока рисуется плавно
--   "terminal": false — эффекты Ghostty (fx: плавный курсор, шлейф, искры) в окне ownvim выключены, в остальных
--     вкладках терминала остаются. ownvim метит свою вкладку: 255-й цвет палитры — #ff00ff (nvim палитрой не пользуется),
--     шейдеры dotfiles видят метку в iPalette[255] и не анимируют; вышел или ctrl-z — метка снята (OSC 104)
local settings = require("own.settings")

local M = {}

local function a() return (settings.current or {}).animations or {} end

-- метка вкладки Ghostty: эффекты здесь не нужны
local MARK, UNMARK = "\27]4;255;rgb:ff/00/ff\27\\", "\27]104;255\27\\"
local marked = false

local function send(s) pcall(vim.api.nvim_ui_send, s) end

local function terminal_fx()
  local want = a().terminal == false
  if want ~= marked then send(want and MARK or UNMARK) end
  marked = want
end

local function apply()
  local o = a()
  terminal_fx()
  local cur = o.cursor or {}
  local ok, smear = pcall(require, "smear_cursor")
  if ok then
    smear.stiffness = cur.stiffness or 0.8
    smear.trailing_stiffness = cur.trailing_stiffness or 0.6
    -- во вставке у smear свои, медленные умолчания (0.5) — без них набор тянется за курсором
    smear.stiffness_insert_mode = cur.insert_stiffness or 0.9
    smear.trailing_stiffness_insert_mode = cur.insert_stiffness or 0.9
    smear.min_horizontal_distance_smear = cur.min_distance or 2
    smear.smear_insert_mode = cur.insert ~= false
    smear.smear_between_buffers = cur.between_buffers ~= false
    smear.enabled = cur.enabled ~= false
    if package.loaded["own.modes"] then require("own.modes").reload() end -- шлейф цветом режима
  end
  if rawget(_G, "Snacks") then
    -- snacks читает свой конфиг при включении: поправить и включить заново
    local sc = o.scroll or {}
    Snacks.config.scroll = vim.tbl_deep_extend("force", Snacks.config.scroll or {},
      { animate = { duration = { total = sc.duration_ms or 100 } } })
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
  -- на время ctrl-z и после выхода вкладка снова обычный терминал — с эффектами
  local group = vim.api.nvim_create_augroup("own.animations.fx", { clear = true })
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, { group = group, callback = function()
    if marked then send(UNMARK) end
  end })
  vim.api.nvim_create_autocmd("VimResume", { group = group, callback = function()
    if marked then send(MARK) end
  end })
  -- метка — сразу, а не после загрузки плагинов: курсор не должен успеть проехать со шлейфом
  vim.api.nvim_create_autocmd("UIEnter", { group = group, once = true, callback = terminal_fx })
end

M.reload = apply

return M
