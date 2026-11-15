-- «Расширения» — как панель Extensions в VS Code: слева всё, из чего собран ownvim.
--   МОДУЛИ — части самого ownvim (раздел "modules"): ● включён, ○ выключен; enter / пробел — переключить
--   ПЛАГИНЫ — свои из раздела "plugins"; x — убрать, o — страница на GitHub
--   i — магазин плагинов (каталог с поиском), u — обновить плагины, L — менеджер lazy.nvim,
--   o на модуле — его файл (в начале — что он делает и какие у него настройки), r — обновить список
-- Набор модулей и плагинов встаёт после :restart — панель сама предложит.
local settings = require("own.settings")

local M = {}

local ns = vim.api.nvim_create_namespace("own.extensions")
local state = { buf = nil, items = {} }

local function is_dict(t) return type(t) == "table" and (next(t) == nil or not vim.islist(t)) end

function M.win()
  if not state.buf then return nil end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(w) == state.buf then return w end
  end
end

local function short(desc)
  desc = (desc or ""):gsub("%s*%(.-%)", ""):gsub("[:;—].*$", "")
  return vim.trim(desc)
end

function M.render()
  local buf = state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local cur = settings.current or {}
  local desc = require("own.schema").descriptions()
  local lines, items, marks = {}, {}, {}
  local function add(text, hl, item)
    lines[#lines + 1] = text
    if item then items[#lines] = item end
    if hl then marks[#marks + 1] = { #lines - 1, 0, #text, hl } end
  end
  add(" enter вкл/выкл · i магазин · u обновить", "Comment")

  local names = vim.tbl_keys(cur.modules or {})
  table.sort(names)
  local on_n = 0
  for _, n in ipairs(names) do if settings.enabled(cur, n) then on_n = on_n + 1 end end
  add("")
  add((" МОДУЛИ  %d из %d"):format(on_n, #names), "OwnSideTitle")
  for _, name in ipairs(names) do
    local on = settings.enabled(cur, name)
    local d = short(desc["modules." .. name])
    local text = ("  %s %s"):format(on and "●" or "○", name)
    add(text .. (d ~= "" and ("  " .. d) or ""), nil, { kind = "module", name = name, on = on })
    local row = #lines - 1
    marks[#marks + 1] = { row, 2, 2 + #(on and "●" or "○"), on and "DiagnosticOk" or "Comment" }
    if not on then marks[#marks + 1] = { row, 2, #text, "Comment" } end
    if d ~= "" then marks[#marks + 1] = { row, #text, #lines[#lines], "Comment" } end
  end

  local plugins = vim.tbl_keys(cur.plugins or {})
  table.sort(plugins)
  add("")
  add((" ПЛАГИНЫ  %d"):format(#plugins), "OwnSideTitle")
  if #plugins == 0 then add("  своих нет — i, чтобы выбрать", "Comment") end
  for _, repo in ipairs(plugins) do
    local on = cur.plugins[repo] ~= false
    local text = ("  %s %s"):format(on and "●" or "○", repo)
    add(text, nil, { kind = "plugin", repo = repo, on = on })
    marks[#marks + 1] = { #lines - 1, 2, 2 + #(on and "●" or "○"), on and "DiagnosticOk" or "Comment" }
  end

  local ok, lazy = pcall(require, "lazy")
  if ok then
    local st = lazy.stats()
    add("")
    add((" всего плагинов: %d, загружено: %d"):format(st.count, st.loaded), "Comment")
  end

  local w = M.win()
  local row = w and vim.api.nvim_win_get_cursor(w)[1] or nil
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  state.items = items
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    if m[2] < m[3] then vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = math.min(m[3], #lines[m[1] + 1]), hl_group = m[4] }) end
  end
  if w then pcall(vim.api.nvim_win_set_cursor, w, { math.min(row and row > 1 and row or 4, #lines), 0 }) end
end

local function item()
  local w = M.win()
  return w and state.items[vim.api.nvim_win_get_cursor(w)[1]] or nil
end

-- раздел в settings.jsonc с комментариями через панель не переписываем — они бы пропали
local function guarded(key)
  if not settings.has_comments(key) then return false end
  vim.notify(('в разделе "%s" твои комментарии — правь в файле, чтобы они не пропали'):format(key))
  local w
  for _, x in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(x).relative == "" and vim.bo[vim.api.nvim_win_get_buf(x)].buftype == "" then w = x; break end
  end
  if w then vim.api.nvim_set_current_win(w) end
  settings.open_at(key)
  return true
end

local function toggle_module(it)
  if guarded("modules") then return end
  local user = settings.user()
  local mods = is_dict(user.modules) and vim.deepcopy(user.modules) or {}
  local default = (settings.defaults().modules or {})[it.name]
  local default_on = default == true or (is_dict(default) and default.enabled ~= false)
  if it.on then
    if is_dict(mods[it.name]) then
      mods[it.name].enabled = false
    elseif default_on then
      mods[it.name] = false
    else
      mods[it.name] = nil -- и так выключен по умолчанию — просто убрать своё «включить»
    end
  else
    if is_dict(mods[it.name]) then
      mods[it.name].enabled = nil
      if next(mods[it.name]) == nil then mods[it.name] = nil end
    else
      mods[it.name] = nil
    end
    -- по умолчанию выключен — включить явно
    if not default_on and mods[it.name] == nil then mods[it.name] = true end
  end
  settings.set("modules", next(mods) and mods or vim.empty_dict())
  M.render()
end

local function remove_plugin(it)
  if guarded("plugins") then return end
  if vim.fn.confirm(("Убрать плагин %s из settings.jsonc?"):format(it.repo), "&Да\n&Нет", 2) ~= 1 then return end
  local plugins = vim.deepcopy(settings.user().plugins or {})
  plugins[it.repo] = nil
  settings.set("plugins", next(plugins) and plugins or vim.empty_dict())
  M.render()
end

local function code_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then return w end
  end
end

local function open_item(it)
  if it.kind == "plugin" then return vim.ui.open("https://github.com/" .. it.repo) end
  local path = vim.fn.stdpath("config") .. "/lua/own/modules/" .. it.name .. ".lua"
  if vim.fn.filereadable(path) == 0 then return vim.notify("у модуля " .. it.name .. " нет своего файла") end
  local w = code_win()
  if w then vim.api.nvim_set_current_win(w) else vim.cmd("rightbelow vsplit") end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "own_extensions"
  vim.bo[buf].bufhidden = "hide"
  local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc }) end
  local function on_item(fn) return function() local it = item(); if it then fn(it) end end end
  local function toggle(it)
    if it.kind == "module" then return toggle_module(it) end
    open_item(it)
  end
  map("<cr>", on_item(toggle), "Включить / выключить")
  map("<space>", on_item(toggle), "Включить / выключить")
  map("<2-LeftMouse>", on_item(toggle), "Включить / выключить")
  map("o", on_item(open_item), "Файл модуля / страница плагина")
  map("x", on_item(function(it) if it.kind == "plugin" then remove_plugin(it) end end), "Убрать плагин")
  map("i", function() require("own.store").open() end, "Магазин плагинов")
  map("u", function() vim.cmd("Lazy update") end, "Обновить плагины")
  map("L", function() vim.cmd("Lazy") end, "Менеджер плагинов")
  map("r", M.render, "Обновить список")
  return buf
end

--- Открыть панель (рабочее место ставит её слева)
function M.open()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then state.buf = make_buf() end
  local width = settings.module_opts(settings.current or {}, "workspace").left_width or 32
  vim.cmd("topleft " .. width .. "vsplit")
  vim.api.nvim_win_set_buf(0, state.buf)
  local wo = vim.wo[0]
  wo.number, wo.relativenumber, wo.statuscolumn, wo.cursorline, wo.wrap, wo.list = false, false, "", true, false, false
  M.render()
end

return M
