-- Go-ядро ownvim (папка core/, программа ownvimd): сборка, вызов команд, мост по RPC.
-- Программа собирается сама из исходников в ~/.local/share/ownvim/ownvimd: при первом запуске — сразу (нужен go),
-- после правки Go-кода — в фоне, после первой отрисовки.
--   require("own.core").run({ "settings", "load", … })  — вызвать команду и дождаться ответа
--   require("own.core").request("ping")                 — метод моста (ownvimd serve, vim.rpcrequest)
local M = {}

M.src = vim.fn.stdpath("config") .. "/core"
M.bin = vim.fn.stdpath("data") .. "/ownvimd"
M.error = nil -- почему ядро недоступно (для :OwnHealth)

local function mtime(p)
  local st = vim.uv.fs_stat(p)
  return st and (st.mtime.sec + st.mtime.nsec / 1e9) or nil
end

-- самый свежий из исходников ядра (.go, go.mod, go.sum)
local function newest_source()
  local newest = 0
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local p = dir .. "/" .. name
      if kind == "directory" then
        walk(p)
      elseif name:match("%.go$") or name == "go.mod" or name == "go.sum" then
        newest = math.max(newest, mtime(p) or 0)
      end
    end
  end
  if vim.uv.fs_stat(M.src) then walk(M.src) end
  return newest
end

--- Программы нет или исходники новее неё
function M.stale()
  local b = mtime(M.bin)
  return not b or newest_source() > b
end

local function build_cmd() return { "go", "build", "-trimpath", "-o", M.bin, "./cmd/ownvimd" } end

-- core/extensions/all.go — подключить все папки расширений (пишется перед каждой сборкой, если список поменялся)
local MODULE = "github.com/van1dalgrr-arch/ownvim/core"
function M.generate_registry()
  local dir = M.src .. "/extensions"
  if not vim.uv.fs_stat(dir) then return end
  local names = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "directory" then
      for f in vim.fs.dir(dir .. "/" .. name) do
        if f:match("%.go$") and not f:match("_test%.go$") then names[#names + 1] = name; break end
      end
    end
  end
  table.sort(names)
  local lines = {
    "// Код создан ownvim (lua/own/core.lua) перед сборкой — не правь руками: здесь все папки core/extensions/*.",
    "package extensions",
    "",
  }
  if #names > 0 then
    lines[#lines + 1] = "import ("
    for _, n in ipairs(names) do lines[#lines + 1] = ('\t_ "%s/extensions/%s"'):format(MODULE, n) end
    lines[#lines + 1] = ")"
  end
  local path = dir .. "/all.go"
  local ok, old = pcall(vim.fn.readfile, path)
  if not ok or not vim.deep_equal(old, lines) then vim.fn.writefile(lines, path) end
end

-- ошибки компиляции — на строках Go-файлов (как у линтера), пока сборка не пройдёт
local build_ns = vim.api.nvim_create_namespace("own.core.build")
local function show_build_errors(stderr)
  local by_file = {}
  for line in (stderr or ""):gmatch("[^\n]+") do
    local file, lnum, col, msg = line:match("^(.-%.go):(%d+):(%d+): (.*)$")
    if not file then file, lnum, msg = line:match("^(.-%.go):(%d+): (.*)$") end
    if file then
      -- путь — реальный: ownvim открыт через ссылку ~/.config/ownvim, а go пишет пути от настоящей папки
      local path = vim.fs.normalize(vim.fn.resolve(file:sub(1, 1) == "/" and file or (M.src .. "/" .. file:gsub("^%./", ""))))
      by_file[path] = by_file[path] or {}
      table.insert(by_file[path], { lnum = tonumber(lnum) - 1, col = math.max((tonumber(col) or 1) - 1, 0),
        message = msg, severity = vim.diagnostic.severity.ERROR, source = "go build" })
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.fs.normalize(vim.fn.resolve(vim.api.nvim_buf_get_name(buf)))
      vim.diagnostic.set(build_ns, buf, by_file[name] or {})
    end
  end
end

--- Собрать синхронно. → ok, ошибка
function M.build()
  if vim.fn.executable("go") ~= 1 then return false, "нет go — brew install go" end
  M.generate_registry()
  local r = vim.system(build_cmd(), { cwd = M.src, text = true }):wait(180000)
  if r.code ~= 0 then return false, vim.trim(r.stderr or "") end
  return true
end

--- Программа есть и свежая; нет — собрать сейчас (первый запуск). Устаревшая, но рабочая — тоже годится:
--- пересоберётся в фоне (rebuild_async). → ok
function M.ensure()
  if vim.uv.fs_stat(M.bin) then return true end
  io.stdout:write("ownvim: собираю Go-ядро (один раз)…\n")
  local ok, err = M.build()
  M.error = not ok and err or nil
  return ok
end

local building, again = false, nil

--- Пересобрать в фоне, если Go-код поменялся (после git pull или своей правки).
--- on_done(ok) — после сборки; force — собрать, даже если программа не старее исходников.
function M.rebuild_async(on_done, force)
  if vim.fn.executable("go") ~= 1 or (not force and not M.stale()) then return end
  if building then again = { on_done, force }; return end -- сохранили ещё раз во время сборки — собрать потом
  building = true
  M.generate_registry()
  vim.system(build_cmd(), { cwd = M.src, text = true }, vim.schedule_wrap(function(r)
    building = false
    local ok = r.code == 0
    if ok then
      M.error = nil
      if M.chan then M.stop() end -- мост перезапустится с новой программой при следующем вызове
      show_build_errors("")
    else
      M.error = vim.trim(r.stderr or "")
      show_build_errors(M.error)
      vim.notify("Go-ядро не собралось — ошибки на строках:\n" .. M.error, vim.log.levels.ERROR)
    end
    if on_done then on_done(ok) end
    if again then
      local a = again
      again = nil
      M.rebuild_async(a[1], a[2])
    end
  end))
end

--- Вызвать команду ownvimd и дождаться. → vim.SystemCompleted | nil
function M.run(args, opts)
  if not M.ensure() then return nil end
  local cmd = { M.bin }
  vim.list_extend(cmd, args)
  return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait(10000)
end

-- ── мост ─────────────────────────────────────────────────────────────────────

--- Запустить ownvimd serve (один раз) → канал
function M.start()
  if M.chan then return M.chan end
  if not M.ensure() then error("Go-ядро недоступно: " .. tostring(M.error)) end
  local log = vim.fn.stdpath("state") .. "/ownvimd.log"
  M.chan = vim.fn.jobstart({ M.bin, "serve" }, {
    rpc = true,
    env = { OWNVIM_DATA = vim.fn.stdpath("data") }, -- хранилище расширений (sdk.Store) для фоновых задач
    on_stderr = function(_, lines)
      local f = io.open(log, "a")
      if f then f:write(table.concat(lines, "\n")); f:close() end
    end,
    on_exit = function() M.chan = nil end,
  })
  if M.chan <= 0 then
    M.chan = nil
    error("ownvimd serve не запустился")
  end
  return M.chan
end

function M.stop()
  if M.chan then pcall(vim.fn.jobstop, M.chan) end
  M.chan = nil
end

--- Метод моста с ответом (ждёт)
function M.request(method, ...) return vim.rpcrequest(M.start(), method, ...) end

--- Метод моста без ответа
function M.notify(method, ...) return vim.rpcnotify(M.start(), method, ...) end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    group = vim.api.nvim_create_augroup("own.core", { clear = true }),
    callback = function()
      vim.defer_fn(function() M.rebuild_async(function(ok) if ok then require("own.ext").reload(true) end end) end, 1000)
    end,
  })
end

return M
