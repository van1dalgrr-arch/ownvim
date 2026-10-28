-- Python как Go в ownvim: окружение проекта находится само (.venv, venv, poetry, pipenv, $VIRTUAL_ENV, conda) и
-- уходит в basedpyright, тесты и отладчик; ▶ слева от if __name__ == "__main__" и test_* (пробел r x — запустить,
-- пробел r X — в отладчике); дополнение из неимпортированных модулей — import пишется сам; при сохранении ruff
-- исправляет, сортирует импорты и форматирует (как goimports + gofumpt); пробел c t — вписать подсказку типа в код.
-- Раздел "python":
--   "venv": "" — папка окружения от корня проекта ("" — найти самому); пробел r v — выбрать на ходу
--   "run_marks": true — ▶ слева от main и тестов
-- Сам Python: brew install uv (uv venv && uv sync) или python3 -m venv .venv
local settings = require("own.settings")
local root = require("own.root")

local M = {}

local function p() return (settings.current or {}).python or {} end

local cache = {} -- корень → папка окружения (false — нет)
local asked = {} -- корень → poetry/pipenv уже спрошены

local function has_python(dir) return dir and vim.uv.fs_stat(dir .. "/bin/python") ~= nil end

-- poetry и pipenv держат окружение вне проекта — спросить их (в фоне, один раз), потом обновить сервер
local function ask_tools(dir)
  if asked[dir] then return end
  asked[dir] = true
  local cmd
  if vim.uv.fs_stat(dir .. "/poetry.lock") and vim.fn.executable("poetry") == 1 then
    cmd = { "poetry", "env", "info", "-p" }
  elseif vim.uv.fs_stat(dir .. "/Pipfile") and vim.fn.executable("pipenv") == 1 then
    cmd = { "pipenv", "--venv" }
  end
  if not cmd then return end
  vim.system(cmd, { cwd = dir, text = true }, vim.schedule_wrap(function(r)
    local path = vim.trim(r.stdout or "")
    if r.code == 0 and has_python(path) and not cache[dir] then
      cache[dir] = path
      M.apply(dir)
    end
  end))
end

--- Папка окружения проекта или nil
function M.venv(dir)
  dir = dir or root.get()
  local chosen = require("own.modules.workspace").project_state(dir).python_venv
  if has_python(chosen) then return chosen end
  if cache[dir] ~= nil then return cache[dir] or nil end
  local found
  local own = p().venv
  if own and own ~= "" then
    own = vim.fn.expand(own)
    found = own:sub(1, 1) == "/" and own or vim.fs.normalize(dir .. "/" .. own)
    if not has_python(found) then found = nil end
  end
  if not found then
    for _, name in ipairs({ ".venv", "venv", "env", ".env" }) do
      if has_python(dir .. "/" .. name) then found = dir .. "/" .. name; break end
    end
  end
  -- окружение, из которого запущен nvim, — только если в проекте своего нет
  if not found and has_python(vim.env.VIRTUAL_ENV) then found = vim.env.VIRTUAL_ENV end
  if not found and vim.env.CONDA_DEFAULT_ENV and vim.env.CONDA_DEFAULT_ENV ~= "base" and has_python(vim.env.CONDA_PREFIX) then
    found = vim.env.CONDA_PREFIX
  end
  cache[dir] = found or false
  if not found then ask_tools(dir) end
  return found
end

--- Python проекта: из окружения, иначе системный
function M.python(dir)
  local v = M.venv(dir)
  if v then return v .. "/bin/python" end
  return vim.fn.exepath("python3") ~= "" and vim.fn.exepath("python3") or "python3"
end

--- Имя окружения для строки статуса: «.venv», «myproj-x1y2-py3.12»
function M.venv_name(dir)
  local v = M.venv(dir)
  return v and vim.fs.basename(v) or nil
end

--- settings для basedpyright с python.pythonPath проекта (свой pythonPath в настройках главнее)
function M.settings(s, dir)
  s = vim.deepcopy(s or {})
  s.python = s.python or {}
  if not s.python.pythonPath then s.python.pythonPath = M.python(dir or root.get()) end
  return s
end

--- Конфигурация basedpyright: путь к Python — по корню, когда сервер стартует
function M.lsp(cfg)
  cfg.before_init = function(_, config)
    -- та же таблица, что у клиента (client.settings): заменить её целиком — клиент не увидит
    config.settings.python = M.settings(config.settings, config.root_dir).python
  end
  return cfg
end

--- Окружение поменялось — работающим серверам новый pythonPath
function M.apply(dir)
  local base = (vim.lsp.config.basedpyright or {}).settings
  for _, client in ipairs(vim.lsp.get_clients({ name = "basedpyright" })) do
    if not dir or client.root_dir == dir then
      client.settings = M.settings(base, client.root_dir)
      client:notify("workspace/didChangeConfiguration", { settings = client.settings })
    end
  end
  vim.cmd("redrawstatus")
end

--- Выбрать окружение проекта: найденные рядом, poetry/uv-кэш нет — путь руками; помнится для проекта
function M.choose()
  local dir = root.get()
  local items = {}
  for _, name in ipairs({ ".venv", "venv", "env", ".env" }) do
    if has_python(dir .. "/" .. name) then items[#items + 1] = dir .. "/" .. name end
  end
  for _, v in ipairs({ vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX, cache[dir] or nil }) do
    if has_python(v) and not vim.tbl_contains(items, v) then items[#items + 1] = v end
  end
  items[#items + 1] = "другая папка…"
  items[#items + 1] = "найти самому"
  vim.ui.select(items, {
    prompt = "Окружение Python (сейчас: " .. (M.venv_name(dir) or "системный") .. ")",
    format_item = function(i) return vim.startswith(i, dir .. "/") and i:sub(#dir + 2) or i end,
  }, function(choice)
    if not choice then return end
    local function set(path)
      require("own.modules.workspace").set_project("python_venv", path)
      cache[dir], asked[dir] = nil, nil
      M.apply(dir)
      vim.notify("Python: " .. M.python(dir))
    end
    if choice == "найти самому" then return set(nil) end
    if choice == "другая папка…" then
      return vim.ui.input({ prompt = "Папка окружения: ", default = dir .. "/", completion = "dir" }, function(path)
        if not path or path == "" then return end
        path = vim.fs.normalize(vim.fn.expand(path))
        if not has_python(path) then return vim.notify("в " .. path .. " нет bin/python", vim.log.levels.WARN) end
        set(path)
      end)
    end
    set(choice)
  end)
end

--- Вписать в код подсказки типов строки под курсором (-> int, : list[str]) — как двойной клик по подсказке в PyCharm
function M.apply_hints()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local hints = vim.lsp.inlay_hint.get({ bufnr = 0, range = { start = { line = row, character = 0 }, ["end"] = { line = row + 1, character = 0 } } })
  local by_client = {}
  for _, h in ipairs(hints) do
    for _, e in ipairs(h.inlay_hint.textEdits or {}) do
      by_client[h.client_id] = by_client[h.client_id] or {}
      table.insert(by_client[h.client_id], e)
    end
  end
  if not next(by_client) then return vim.notify("в строке нет подсказок, которые можно вписать", vim.log.levels.WARN) end
  for id, edits in pairs(by_client) do
    local client = vim.lsp.get_client_by_id(id)
    vim.lsp.util.apply_text_edits(edits, vim.api.nvim_get_current_buf(), client and client.offset_encoding or "utf-16")
  end
end

--- Python-черновик: main.py в данных nvim — сразу запускать (пробел r x)
function M.scratch()
  local dir = vim.fn.stdpath("data") .. "/py-scratch"
  local file = dir .. "/main.py"
  if not vim.uv.fs_stat(file) then
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "def main() -> None:", '    print("черновик")', "", "", 'if __name__ == "__main__":', "    main()" }, file)
  end
  vim.cmd.edit(file)
end

function M.setup()
  if p().run_marks ~= false then require("own.tools.run").setup("python") end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("own.python", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      -- описание по K — от basedpyright; у ruff оно пустое и перекрывает настоящее
      if client and client.name == "ruff" then client.server_capabilities.hoverProvider = false end
    end,
  })
end

function M.reload()
  cache, asked = {}, {}
  M.apply()
end

return M
