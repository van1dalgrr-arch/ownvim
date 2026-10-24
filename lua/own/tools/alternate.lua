-- Тест ↔ код (cmd-shift-t, как Navigate → Test в GoLand) — для любого языка, по соглашениям о именах:
--   Go        foo.go ↔ foo_test.go
--   TS / JS   foo.ts ↔ foo.test.ts, foo.spec.ts, __tests__/foo.test.ts
--   Python    foo.py ↔ test_foo.py, foo_test.py, tests/test_foo.py
--   Rust      src/foo.rs ↔ tests/foo.rs (тесты внутри файла — прыжок к mod tests)
--   C / C++   foo.cpp ↔ foo_test.cpp, tests/foo_test.cpp
--   Lua       foo.lua ↔ foo_spec.lua, spec/foo_spec.lua
-- Есть пара — открывается; нет — создаётся первый вариант (папка тоже), как «Create New Test» в GoLand.
local M = {}

local exists = function(p) return vim.uv.fs_stat(p) ~= nil end

-- для файла кода: варианты пути к тесту (первый — что создавать); dir — папка файла, name — без расширения
local function tests_for(dir, name, ext)
  local up = vim.fn.fnamemodify(dir, ":h")
  if ext == "go" then return { ("%s/%s_test.go"):format(dir, name) } end
  if ext == "py" then
    return { ("%s/test_%s.py"):format(dir, name), ("%s/%s_test.py"):format(dir, name),
      ("%s/tests/test_%s.py"):format(dir, name), ("%s/tests/test_%s.py"):format(up, name) }
  end
  if ext == "rs" then
    local crate = dir:match("^(.*)/src$") or dir:match("^(.*)/src/") or up
    return { ("%s/tests/%s.rs"):format(crate, name) }
  end
  if ext == "lua" then return { ("%s/%s_spec.lua"):format(dir, name), ("%s/spec/%s_spec.lua"):format(up, name) } end
  if vim.tbl_contains({ "c", "cc", "cpp", "cxx" }, ext) then
    return { ("%s/%s_test.%s"):format(dir, name, ext), ("%s/tests/%s_test.%s"):format(up, name, ext),
      ("%s/test/%s_test.%s"):format(up, name, ext) }
  end
  -- ts, tsx, js, jsx, mjs, vue, svelte…
  return { ("%s/%s.test.%s"):format(dir, name, ext), ("%s/%s.spec.%s"):format(dir, name, ext),
    ("%s/__tests__/%s.test.%s"):format(dir, name, ext) }
end

-- для файла теста: варианты пути к коду (nil — это не тест)
local function code_for(dir, name, ext)
  local up = vim.fn.fnamemodify(dir, ":h")
  local base = name:match("^(.+)_test$") or name:match("^(.+)_spec$") or name:match("^(.+)%.test$")
    or name:match("^(.+)%.spec$") or name:match("^test_(.+)$")
  if base then
    local dirs = { dir }
    local tail = vim.fn.fnamemodify(dir, ":t")
    if vim.tbl_contains({ "tests", "test", "spec", "__tests__" }, tail) then
      dirs = { up, up .. "/src", up .. "/" .. vim.fn.fnamemodify(up, ":t") }
    end
    local out = {}
    for _, d in ipairs(dirs) do out[#out + 1] = ("%s/%s.%s"):format(d, base, ext) end
    return out
  end
  -- Rust: tests/foo.rs → src/foo.rs (и src/foo/mod.rs)
  if ext == "rs" and vim.fn.fnamemodify(dir, ":t") == "tests" then
    return { ("%s/src/%s.rs"):format(up, name), ("%s/src/%s/mod.rs"):format(up, name) }
  end
end

-- Rust: тесты внутри файла — #[cfg(test)] mod tests
local function rust_inline()
  local lnum
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:match("^%s*#%[cfg%(test%)%]") then lnum = i break end
  end
  if not lnum then return false end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.cmd("normal! zz")
  return true
end

function M.switch()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then return vim.notify("сначала сохрани файл", vim.log.levels.WARN) end
  local dir, name, ext = vim.fn.fnamemodify(path, ":h"), vim.fn.fnamemodify(path, ":t:r"), vim.fn.fnamemodify(path, ":e")
  if ext == "" then return vim.notify("у файла нет расширения — не понять, где его тест", vim.log.levels.WARN) end

  local code = code_for(dir, name, ext)
  local list = code or tests_for(dir, name, ext)
  for _, p in ipairs(list) do
    if exists(p) then return vim.cmd.edit(vim.fn.fnameescape(p)) end
  end
  -- код не рядом (tests/ → pkg/calc.py) — ищем по имени в проекте
  if code then
    local root = require("own.root").get()
    local want = vim.fn.fnamemodify(list[1], ":t")
    local found = vim.fs.find(function(n, d) return n == want and not d:find("/tests?/") and not d:find("/node_modules") end,
      { path = root, type = "file", limit = 1 })[1]
    if found then return vim.cmd.edit(vim.fn.fnameescape(found)) end
  end
  if code then return vim.notify("не нашёл код для этого теста: " .. vim.fn.fnamemodify(list[1], ":~:."), vim.log.levels.WARN) end
  if ext == "rs" and rust_inline() then return end

  local target = list[1]
  vim.fn.mkdir(vim.fn.fnamemodify(target, ":h"), "p")
  vim.cmd.edit(vim.fn.fnameescape(target))
  if ext == "go" and vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "" then
    -- тот же пакет, что у кода: первая строка package из исходного файла
    local pkg = "main"
    for _, line in ipairs(vim.fn.readfile(path, "", 40)) do
      pkg = line:match("^package%s+([%w_]+)") or pkg
      if line:match("^package") then break end
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "package " .. pkg, "", 'import "testing"', "" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
  end
  vim.notify("новый тест: " .. vim.fn.fnamemodify(target, ":~:."))
end

return M
