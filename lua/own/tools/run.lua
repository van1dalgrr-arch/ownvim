-- ▶ слева от точек входа и тестов — как значки запуска в GoLand / PyCharm:
--   Go      func main и func TestX / BenchmarkX / FuzzX / ExampleX (в _test.go)
--   Python  if __name__ == "__main__" и def test_* / class Test* (в test_*.py, *_test.py)
--   JS / TS #!/usr/bin/env node и it / test / describe (в *.test.js, *.spec.ts…)
-- пробел r x — запустить то, в чём курсор; пробел r X — то же под отладчиком (delve / debugpy).
-- Тесты идут через neotest (результат ✓/✗ рядом с тестом), main — в терминале снизу, остальное Go — go test.
local M = {}
local ns = vim.api.nvim_create_namespace("own.run")

local function is_test_py(file)
  local name = vim.fs.basename(file)
  return name:match("^test_.*%.py$") or name:match("_test%.py$")
end

local function is_test_js(file) return file:match("%.test%.[cm]?[jt]sx?$") or file:match("%.spec%.[cm]?[jt]sx?$") end

local function js_kind(line, file)
  if line:match("^#!.*node") then return "main", "main" end
  if not is_test_js(file) then return nil end
  for _, fn in ipairs({ "it", "test", "describe" }) do
    local name = line:match("^%s*" .. fn .. "[%.%w]*%(%s*[\"'`](.-)[\"'`]")
    if name then return "test", name end
  end
end

-- строка → что это и как называется
local KIND = {
  javascript = js_kind, typescript = js_kind, javascriptreact = js_kind, typescriptreact = js_kind,
  go = function(line, file)
    if line:match("^func main%(%)") then return "main", "main" end
    if not file:match("_test%.go$") then return nil end
    for _, k in ipairs({ "Test", "Benchmark", "Fuzz", "Example" }) do
      local name = line:match("^func (" .. k .. "[%w_]*)%(")
      if name then return k:lower(), name end
    end
  end,
  python = function(line, file)
    if line:match("^if __name__ == [\"']__main__[\"']%s*:") then return "main", "main" end
    if not is_test_py(file) then return nil end
    local name = line:match("^%s*def (test[%w_]*)%(") or line:match("^%s*async def (test[%w_]*)%(")
      or line:match("^class (Test[%w_]*)[%(:]")
    if name then return "test", name end
  end,
}

-- верхний уровень, за который поиск «в чём курсор» не уходит
local function js_top(line) return line:match("^[%w]") ~= nil end

local TOP = {
  javascript = js_top, typescript = js_top, javascriptreact = js_top, typescriptreact = js_top,
  go = function(line) return line:match("^func ") end,
  python = function(line) return line:match("^def ") or line:match("^async def ") or line:match("^class ") or line:match("^if ") end,
}

local PATTERN = { go = "*.go", python = "*.py", javascript = { "*.js", "*.mjs", "*.cjs", "*.jsx", "*.ts", "*.mts", "*.cts", "*.tsx" } }

function M.marks(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local kind = KIND[vim.bo[buf].filetype]
  if not kind then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local file = vim.api.nvim_buf_get_name(buf)
  -- на строке с ошибкой или предупреждением слева нужен их значок, а не ▶
  local problem = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do problem[d.lnum + 1] = true end
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local k = kind(line, file)
    if k and not problem[i] then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
        sign_text = "▶",
        sign_hl_group = k == "main" and "DotfilesRunMain" or "DotfilesRunTest",
        priority = 5, -- ниже ошибок и git
      })
    end
  end
end

-- то, в чём курсор: ближайшая точка входа или тест выше, но не дальше функции верхнего уровня
local function current(ft)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  for i = #lines, 1, -1 do
    local k, name = KIND[ft](lines[i], file)
    if k then return k, name, i end
    if TOP[ft](lines[i]) then return end
  end
end

local function term(cmd, dir)
  Snacks.terminal(cmd, { cwd = dir, auto_close = false, win = { position = "bottom", height = 0.3 } })
end

local function test_at(line, debug)
  vim.api.nvim_win_set_cursor(0, { line, #vim.fn.getline(line):match("^%s*") }) -- neotest берёт тест под курсором
  return require("neotest").run.run({ strategy = debug and "dap" or nil })
end

local function run_python(debug)
  local k, _, line = current("python")
  local file = vim.fn.expand("%:p")
  if not k then
    if is_test_py(file) then return require("neotest").run.run({ file, strategy = debug and "dap" or nil }) end
    return vim.notify("курсор не в if __name__ == \"__main__\" и не в тесте", vim.log.levels.WARN)
  end
  if k == "test" then return test_at(line, debug) end
  local dir = require("own.root").get()
  local py = require("own.modules.python")
  if debug then
    return require("dap").run({ type = "python", name = vim.fs.basename(file), request = "launch", program = file,
      cwd = dir, pythonPath = py.python(dir), console = "integratedTerminal", justMyCode = false })
  end
  term({ py.python(dir), file }, dir)
end

-- JS / TS: тест — neotest, остальное — файл целиком в node (TypeScript node 23.6+ запускает сам)
local function run_js(debug)
  local ft = vim.bo.filetype
  local file = vim.fn.expand("%:p")
  local dir = require("own.root").get()
  if is_test_js(file) then
    local k, _, line = current(ft)
    if k == "test" then return test_at(line, debug) end
    return require("neotest").run.run({ file, strategy = debug and "dap" or nil })
  end
  if debug then
    return require("dap").run({ type = "pwa-node", name = vim.fs.basename(file), request = "launch", program = file,
      cwd = dir, console = "integratedTerminal", sourceMaps = true })
  end
  term({ "node", file }, dir)
end

function M.run(debug)
  if vim.bo.filetype == "python" then return run_python(debug) end
  if KIND[vim.bo.filetype] == js_kind then return run_js(debug) end
  if vim.bo.filetype ~= "go" then return vim.notify("▶ работает в Go-, Python- и JS/TS-файлах", vim.log.levels.WARN) end
  local k, name, line = current("go")
  local dir = vim.fn.expand("%:p:h")
  if not k then
    if vim.fn.expand("%"):match("_test%.go$") then
      return require("neotest").run.run({ vim.fn.expand("%:p"), strategy = debug and "dap" or nil }) -- весь файл
    end
    return vim.notify("курсор не в func main и не в тесте", vim.log.levels.WARN)
  end
  if k == "main" then
    if debug then
      return require("dap").run({ type = "go", name = "main", request = "launch", program = dir })
    end
    return term("go run .", dir)
  end
  if k == "test" then return test_at(line, debug) end
  local cmds = {
    benchmark = "go test -run '^$' -bench '^" .. name .. "$' -benchmem .",
    fuzz = "go test -run '^$' -fuzz '^" .. name .. "$' -fuzztime 30s .",
    example = "go test -run '^" .. name .. "$' -v .",
  }
  if debug then
    return require("dap").run({ type = "go", name = name, request = "launch", mode = "test", program = dir,
      args = k == "benchmark" and { "-test.run", "^$", "-test.bench", "^" .. name .. "$" } or { "-test.run", "^" .. name .. "$" } })
  end
  term(cmds[k], dir)
end

--- Значки для языка: "go" (по умолчанию), "python" или "javascript" (и TypeScript)
function M.setup(lang)
  lang = lang or "go"
  local group = vim.api.nvim_create_augroup("own.run." .. lang, { clear = true })
  local timers = {}
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "InsertLeave", "DiagnosticChanged" }, {
    group = group,
    pattern = PATTERN[lang],
    callback = function(ev)
      -- после паузы в 200 мс, а не на каждое нажатие
      local t = timers[ev.buf] or vim.uv.new_timer()
      timers[ev.buf] = t
      t:start(200, 0, vim.schedule_wrap(function() M.marks(ev.buf) end))
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      if timers[ev.buf] then timers[ev.buf]:close(); timers[ev.buf] = nil end
    end,
  })
end

return M
