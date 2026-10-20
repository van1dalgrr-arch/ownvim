-- Всё ставится само: открыл файл языка, для которого ничего не настроено, — ownvim сам включает
-- языковой сервер, форматтер и линтер и ставит их через mason. Раздел "auto" в settings.jsonc:
--   "languages": { "typescript": { "lsp": ["vtsls"], "format": ["prettierd"], "lint": […] }, "lua": false }
--     — проверенный набор; false — для этого языка ничего не ставить
--   "discover": true — языка нет в наборе: ищем сервер в реестре mason (один — ставим, несколько — спросим раз)
-- Какие языки уже включены — в данных ownvim (own-auto.json); это слой между defaults.jsonc и settings.jsonc,
-- поэтому settings.jsonc всегда сильнее: "vtsls": false в lsp.servers выключает даже то, что включилось само.
local M = {}

local path = vim.fn.stdpath("data") .. "/own-auto.json"

-- язык → true (из набора "languages") | { lsp, format, lint } (найдено в mason) | false (ничего не нужно)
local function read()
  local f = io.open(path)
  if not f then return {} end
  local ok, t = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(t) == "table" and t or {}
end

local function write(t)
  local f = io.open(path, "w")
  if f then f:write(vim.json.encode(t)); f:close() end
end

local function rec_of(a, seen, ft)
  local langs = a.languages or {}
  if langs[ft] == false then return nil end
  local v = seen[ft]
  if v == true then return type(langs[ft]) == "table" and langs[ft] or nil end
  return type(v) == "table" and v or nil
end

--- Слой настроек из включённых языков (s — defaults + settings.jsonc). nil — авто выключено.
function M.layer(s)
  local a = s.auto or {}
  if a.enabled == false then return nil end
  local layer = { lsp = { servers = {} }, format = { languages = {} }, lint = { languages = {} } }
  local seen = read()
  for ft in pairs(seen) do
    local rec = rec_of(a, seen, ft)
    if rec then
      for _, name in ipairs(rec.lsp or {}) do layer.lsp.servers[name] = true end
      if rec.format then layer.format.languages[ft] = rec.format end
      if rec.lint then layer.lint.languages[ft] = rec.lint end
    end
  end
  return layer
end

local function cur() return require("own.settings").current or {} end

local function server_on(v) return v ~= false and not (type(v) == "table" and v.enabled == false) end

-- какой-то включённый сервер уже знает этот язык?
local function covered(ft)
  for name, v in pairs((cur().lsp or {}).servers or {}) do
    if server_on(v) then
      local fts = type(v) == "table" and v.filetypes
      if not fts then
        local ok, cfg = pcall(function() return vim.lsp.config[name] end)
        fts = ok and cfg and cfg.filetypes
      end
      if fts and vim.tbl_contains(fts, ft) then return true end
    end
  end
  return false
end

-- серверы из реестра mason, которые умеют этот язык (по filetypes их конфигов в nvim-lspconfig).
-- Серверы «для всего сразу» (орфография, ast-grep, snyk — больше 6 языков) — не серверы языка, их не предлагаем.
-- Сначала узкие: сервер одного языка обычно и есть его основной.
local function discover(ft, done)
  local registry = require("mason-registry")
  registry.refresh(vim.schedule_wrap(function()
    local found, width = {}, {}
    for _, spec in ipairs(registry.get_all_package_specs()) do
      local name = spec.neovim and spec.neovim.lspconfig
      if name and not width[name] and not spec.deprecation and vim.tbl_contains(spec.categories or {}, "LSP") then
        local ok, cfg = pcall(function() return vim.lsp.config[name] end)
        local fts = ok and cfg and cfg.filetypes or {}
        if #fts <= 6 and vim.tbl_contains(fts, ft) then
          found[#found + 1] = name
          width[name] = #fts
        end
      end
    end
    table.sort(found, function(a, b) return width[a] == width[b] and a < b or width[a] < width[b] end)
    done(found)
  end))
end

-- перечитать настройки с новым слоем и применить только то, что касается инструментов
local function apply()
  local settings = require("own.settings")
  local new = settings.load()
  if not new then return end
  settings.current = new
  for _, name in ipairs({ "lsp", "format", "lint" }) do
    local mod = package.loaded["own.modules." .. name]
    if mod and mod.reload then mod.reload() end
  end
  settings.show_problems()
end

local function enable(ft, value, rec)
  local seen = read()
  seen[ft] = value
  write(seen)
  if not rec then return end
  local what = vim.list_extend(vim.list_extend(vim.list_extend({}, rec.lsp or {}), rec.format or {}), rec.lint or {})
  vim.notify(("%s: включаю %s — ставится само. Не надо — \"auto\": { \"languages\": { %q: false } }")
    :format(ft, table.concat(what, ", "), ft))
  apply()
end

local busy = {}
local function on_filetype(ev)
  local ft = ev.match
  local a = cur().auto or {}
  if a.enabled == false or busy[ft] or ft == "" then return end
  if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then return end
  local langs = a.languages or {}
  if langs[ft] == false or read()[ft] ~= nil then return end
  if type(langs[ft]) == "table" then return enable(ft, true, langs[ft]) end
  if a.discover == false or not require("own.tools").mason() or covered(ft) then return end
  busy[ft] = true
  discover(ft, function(found)
    busy[ft] = nil
    if #found == 0 then return enable(ft, false) end
    if #found == 1 then return enable(ft, { lsp = found }, { lsp = found }) end
    local none = "ничего не ставить"
    vim.ui.select(vim.list_extend(vim.deepcopy(found), { none }),
      { prompt = ("Для %s есть несколько серверов — какой поставить?"):format(ft) }, function(choice)
        if not choice then return end -- закрыл без выбора — спросим в следующий раз
        if choice == none then return enable(ft, false) end
        enable(ft, { lsp = { choice } }, { lsp = { choice } })
      end)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("own.auto", { clear = true }),
    -- после остальных обработчиков FileType: буфер уже настроен, серверы из настроек уже знают о нём
    callback = function(ev) vim.schedule(function() if vim.api.nvim_buf_is_valid(ev.buf) then on_filetype(ev) end end) end,
  })
  vim.api.nvim_create_user_command("AutoTools", function(a)
    local seen = read()
    if a.args ~= "" then
      seen[a.args] = nil
      write(seen)
      apply()
      return vim.notify(a.args .. ": забыл — при следующем открытии файла решу заново")
    end
    local lines = {}
    for ft in vim.spairs(seen) do
      local rec = rec_of(cur().auto or {}, seen, ft)
      local what = rec and vim.list_extend(vim.list_extend(vim.list_extend({}, rec.lsp or {}), rec.format or {}), rec.lint or {})
      lines[#lines + 1] = ("%-14s %s"):format(ft, what and table.concat(what, ", ") or "—")
    end
    vim.notify(#lines > 0 and table.concat(lines, "\n") or "пока ничего не включалось само", vim.log.levels.INFO, { title = "Само поставилось" })
  end, {
    nargs = "?",
    complete = function() return vim.tbl_keys(read()) end,
    desc = "Что ownvim включил сам; :AutoTools <язык> — забыть язык",
  })
end

return M
