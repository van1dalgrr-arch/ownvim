-- Плавность, как в VS Code: курсор плавно перелетает (и при наборе — cursorSmoothCaretAnimation), прокрутка
-- плавная, рамка блока под курсором проявляется. Раздел "animations" — каждое отдельно, на лету:
--   "cursor": { "enabled": true, "insert": true, "stiffness": 0.8, "trailing_stiffness": 0.6,
--               "insert_stiffness": 0.9, "min_distance": 2, "between_buffers": true }
--     stiffness — скорость головы (1 — мгновенно), trailing_stiffness — как быстро догоняет хвост,
--     insert_stiffness — то же во вставке (быстрее: набор не должен тянуться),
--     min_distance — сдвиг короче стольких символов — без шлейфа (2: шаг на символ — набор, h/l — мгновенно)
--     style — "glide": курсор скользит, сохраняя форму (как smooth caret), "trail": тянется шлейфом
--     fps — кадров в секунду (120 — плавнее, 60 — бережнее к батарее)
--   "windows": { "enabled": true, "ms": 160 } — новый сплит, дерево, терминал снизу выдвигаются, а не появляются рывком
--   "scroll": { "enabled": true, "duration_ms": 100, "easing": "outQuad" } — easing: linear, outQuad, outCubic, inOutQuad…
--     (outQuad — быстро трогается и мягко останавливается, как прокрутка трекпадом)
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
    local glide = (cur.style or "glide") == "glide"
    -- glide: голова и хвост движутся почти вместе — курсор скользит, а не размазывается
    smear.stiffness = cur.stiffness or (glide and 0.36 or 0.8)
    smear.trailing_stiffness = cur.trailing_stiffness or (glide and 0.33 or 0.6)
    smear.matrix_pixel_threshold = glide and 0.5 or 0.7
    smear.damping = glide and 0.82 or 0.85
    smear.distance_stop_animating = 0.05 -- доезжает до места мягко, без «щелчка» в конце
    -- во вставке у smear свои, медленные умолчания (0.5) — без них набор тянется за курсором
    smear.stiffness_insert_mode = cur.insert_stiffness or 0.6
    smear.trailing_stiffness_insert_mode = (cur.insert_stiffness or 0.6) * 0.92
    smear.damping_insert_mode = 0.85
    smear.distance_stop_animating_vertical_bar = 0.3 -- каретка во вставке доплывает, а не прыгает на последнем шаге
    smear.min_horizontal_distance_smear = cur.min_distance or 2
    smear.time_interval = math.floor(1000 / math.max(30, math.min(240, cur.fps or 120)))
    -- Ghostty сам рисует символы Legacy Computing — шлейф и края гладкие, а не из квадратиков
    smear.legacy_computing_symbols_support = cur.legacy_symbols == nil and vim.env.TERM_PROGRAM == "ghostty" or cur.legacy_symbols == true
    smear.smear_insert_mode = cur.insert ~= false
    smear.smear_between_buffers = cur.between_buffers ~= false
    smear.enabled = cur.enabled ~= false
    if package.loaded["own.modes"] then require("own.modes").reload() end -- шлейф цветом режима
  end
  if rawget(_G, "Snacks") then
    -- snacks читает свой конфиг при включении: поправить и включить заново
    local sc = o.scroll or {}
    Snacks.config.scroll = vim.tbl_deep_extend("force", Snacks.config.scroll or {}, {
      animate = { duration = { step = 10, total = sc.duration_ms or 100 }, easing = sc.easing or "linear" },
      -- зажал j / ctrl-d — каждый шаг тоже плавный, но короткий, чтобы не отставать
      animate_repeat = { delay = 100, duration = { step = 5, total = math.floor((sc.duration_ms or 100) / 2.5) }, easing = sc.easing or "linear" },
    })
    Snacks.scroll.disable()
    if sc.enabled ~= false then Snacks.scroll.enable() end
    Snacks.config.indent = vim.tbl_deep_extend("force", Snacks.config.indent or {},
      { animate = { enabled = (o.indent_scope or {}).enabled == true, style = "out", easing = "outQuad",
        duration = { step = 15, total = (o.indent_scope or {}).duration_ms or 200 } } })
    if Snacks.indent.enabled then
      Snacks.indent.disable()
      Snacks.indent.enable()
    end
  end
end

-- ── окна выдвигаются ────────────────────────────────────────────────────────

local started_at = vim.uv.now()

local function slide(win)
  local w = a().windows or {}
  if w.enabled == false or vim.g.own_no_fade or vim.g.SessionLoad then return end
  if vim.uv.now() - started_at < 1500 then return end -- старт и восстановление сессии — сразу, без анимации
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then return end
  -- куда разделили: окно в «row» раскладки — сплит рядом (растёт ширина), в «col» — под / над (растёт высота)
  local function parent(node, kind)
    if node[1] == "leaf" then return node[2] == win and kind or nil end
    for _, child in ipairs(node[2]) do
      local found = parent(child, node[1])
      if found then return found end
    end
  end
  local kind = parent(vim.fn.winlayout())
  if kind ~= "row" and kind ~= "col" then return end
  local vertical = kind == "row"
  local target = vertical and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win)
  if target < 4 then return end
  local set = vertical and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height
  local total = math.max(60, w.ms or 160)
  local t0 = vim.uv.now()
  local get = function() return vertical and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win) end
  pcall(set, win, 1)
  local from = get() -- меньше winminwidth / winminheight окно не станет — начать с того, что получилось
  local last = from
  if from >= target then return end
  local tm = vim.uv.new_timer()
  tm:start(0, 10, vim.schedule_wrap(function()
    if tm:is_closing() then return end
    local cur = vim.api.nvim_win_is_valid(win) and get()
    -- окно закрыли или его размер поменял кто-то другой (сам пользователь, плагин) — не спорить
    if not cur or cur ~= last then tm:stop(); tm:close(); return end
    local k = math.min(1, (vim.uv.now() - t0) / total)
    local e = 1 - (1 - k) ^ 3 -- быстро выезжает, мягко встаёт
    pcall(set, win, math.floor(from + (target - from) * e + 0.5))
    last = get()
    if k >= 1 then
      tm:stop(); tm:close()
      if last ~= target then pcall(set, win, target) end
    end
  end))
end

--- :Smooth — что из плавности сейчас работает (и почему нет), потом короткое демо: прокрутка, прыжок, окно
function M.check()
  local o = a()
  local lines = {}
  local function row(ok, text, why) lines[#lines + 1] = (ok and "✓ " or "✗ ") .. text .. ((not ok and why) and ("  — " .. why) or "") end
  local smear = package.loaded["smear_cursor"]
  row(smear and smear.enabled, "курсор скользит" .. (smear and (" (вставка: " .. (smear.smear_insert_mode and "да" or "нет") .. ")") or ""),
    not smear and "smear-cursor не загружен — :restart или modules.animations" or "animations.cursor.enabled = false или тихий режим")
  row(rawget(_G, "Snacks") and Snacks.scroll.enabled, ("прокрутка %d мс"):format((o.scroll or {}).duration_ms or 100),
    "animations.scroll.enabled = false или тихий режим (пробел uq)")
  row((o.windows or {}).enabled ~= false and not vim.g.own_no_fade, "окна выдвигаются", "animations.windows / тихий режим")
  local soft = (require("own.settings").current or {}).soft or {}
  row(package.loaded["own.modules.soft"] ~= nil and (soft.fade or {}).enabled ~= false and not vim.g.own_no_fade,
    "окна проявляются, режимы перетекают", "modules.soft выключен или тихий режим")
  row(vim.env.TERM_PROGRAM == "ghostty" or vim.env.TERM_PROGRAM == "WezTerm" or vim.env.TERM_PROGRAM == "kitty",
    "терминал: " .. tostring(vim.env.TERM_PROGRAM or vim.env.TERM), "в этом терминале шлейф может быть блочным")
  if vim.g.own_quiet then lines[#lines + 1] = "! включён тихий режим — анимации спят; пробел uq — выключить" end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "плавность" })
  -- демо: вниз, обратно, прыжок курсора — видно всё по очереди
  local win, view = vim.api.nvim_get_current_win(), vim.fn.winsaveview()
  local n = vim.api.nvim_buf_line_count(0)
  local steps = {
    function() if n > vim.o.lines then vim.cmd("normal! \4") end end, -- ctrl-d
    function() if n > vim.o.lines then vim.cmd("normal! \21") end end, -- ctrl-u
    function() vim.cmd("normal! L") end,
    function() vim.cmd("normal! H") end,
    function() vim.cmd("normal! M") end,
    function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win); vim.fn.winrestview(view) end end,
  }
  for i, f in ipairs(steps) do vim.defer_fn(function() pcall(f) end, 400 * i) end
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
  vim.api.nvim_create_user_command("Smooth", M.check, { desc = "Плавность: что работает + демо" })
  -- новое окно-сплит выдвигается: размер — после того, как плагин его задал (vim.schedule)
  local known = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do known[w] = true end
  vim.api.nvim_create_autocmd("WinNew", { group = group, callback = function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if not known[w] then
        known[w] = true
        vim.schedule(function() slide(w) end)
      end
    end
  end })
  vim.api.nvim_create_autocmd("WinClosed", { group = group, callback = function(ev) known[tonumber(ev.match)] = nil end })
  -- метка — сразу, а не после загрузки плагинов: курсор не должен успеть проехать со шлейфом
  vim.api.nvim_create_autocmd("UIEnter", { group = group, once = true, callback = terminal_fx })
end

M.reload = apply

return M
