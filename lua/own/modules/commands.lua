-- Свои команды-скрипты на любом языке (Python и т.п.) — раздел "commands" в settings.jsonc. Как писать — docs/extensions.ru.md.
--   "Имя": { "run": "python3 extensions/x.py", "input": "selection|file|line|word|none",
--            "output": "replace|insert|window|notify|none", "key": "n <leader>xs", "ft": ["go"] }
-- Скрипт получает текст в stdin, ответ пишет в stdout; контекст — переменные OWN_FILE, OWN_LINE, OWN_ROOT, OWN_FILETYPE.
local settings = require("own.settings")

local M = {}

local function list() return (settings.current or {}).commands or {} end
local applied = {}

local function get_input(kind)
  if kind == "file" then return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), 1, vim.fn.line("$") end
  if kind == "line" then return vim.fn.getline("."), vim.fn.line("."), vim.fn.line(".") end
  if kind == "word" then return vim.fn.expand("<cword>") end
  if kind == "selection" then
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    if vim.fn.mode():match("[vV\22]") then
      vim.cmd("normal! \27")
    else
      a, b = vim.fn.line("'<"), vim.fn.line("'>")
    end
    if a > b then a, b = b, a end
    return table.concat(vim.api.nvim_buf_get_lines(0, a - 1, b, false), "\n"), a, b
  end
  return ""
end

function M.run(name)
  local c = list()[name]
  if not c then return vim.notify("нет команды " .. name, vim.log.levels.ERROR) end
  local input, a, b = get_input(c.input or "none")
  local buf = vim.api.nvim_get_current_buf()
  local cmd = c.run:gsub("^(%S+)%s+(extensions/)", "%1 " .. vim.fn.stdpath("config") .. "/%2")
  local env = { OWN_FILE = vim.api.nvim_buf_get_name(0), OWN_LINE = tostring(vim.fn.line(".")),
    OWN_ROOT = require("own.root").get(), OWN_FILETYPE = vim.bo.filetype, OWN_WORD = vim.fn.expand("<cword>") }
  vim.system({ "sh", "-c", cmd }, { stdin = input, env = env, text = true, cwd = env.OWN_ROOT }, vim.schedule_wrap(function(r)
    if r.code ~= 0 then
      return vim.notify(("%s: ошибка %d\n%s"):format(name, r.code, r.stderr or ""), vim.log.levels.ERROR)
    end
    local out = (r.stdout or ""):gsub("\n$", "")
    local o = c.output or "notify"
    if o == "replace" and a then
      vim.api.nvim_buf_set_lines(buf, a - 1, b, false, vim.split(out, "\n"))
    elseif o == "replace" and c.input == "word" then
      vim.cmd("normal! ciw" .. out)
    elseif o == "insert" then
      vim.api.nvim_put(vim.split(out, "\n"), "l", true, true)
    elseif o == "window" then
      local b2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(b2, 0, -1, false, vim.split(out, "\n"))
      vim.cmd("botright 12split")
      vim.api.nvim_win_set_buf(0, b2)
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = b2 })
    elseif o == "notify" and out ~= "" then
      vim.notify(out, vim.log.levels.INFO, { title = name })
    end
  end))
end

local function apply()
  for _, k in ipairs(applied) do pcall(vim.keymap.del, k[1], k[2]) end
  applied = {}
  for name, c in pairs(list()) do
    if c.key then
      local modes, lhs = c.key:match("^(%a+)%s+(.+)$")
      if modes then
        for m in modes:gmatch(".") do
          vim.keymap.set(m, lhs, function()
            if c.ft and not vim.tbl_contains(c.ft, vim.bo.filetype) then return vim.notify(name .. ": не для этого типа файла") end
            M.run(name)
          end, { desc = name })
          applied[#applied + 1] = { m, lhs }
        end
      else
        settings.warn(name, "key — «режимы клавиша», например \"n <leader>xs\"")
      end
    end
  end
end

function M.pick()
  local names = vim.tbl_keys(list())
  table.sort(names)
  vim.ui.select(names, { prompt = "Мои команды" }, function(n) if n then M.run(n) end end)
end

function M.new(name)
  if not name or name == "" then return vim.notify("ExtensionNew <имя>", vim.log.levels.WARN) end
  local dir = vim.fn.stdpath("config") .. "/extensions"
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. name .. ".py"
  if not vim.uv.fs_stat(file) then
    vim.fn.writefile({
      "# " .. name .. " — расширение ownvim. Как работает: docs/extensions.ru.md",
      "# Вход — stdin (выделение/файл/строка), выход — stdout. Ошибка — exit(1) и текст в stderr.",
      "import os, sys",
      "",
      "text = sys.stdin.read()",
      'file = os.environ.get("OWN_FILE", "")',
      "",
      "print(text.upper(), end=\"\")",
    }, file)
  end
  local cmds = vim.deepcopy(list())
  cmds[name] = cmds[name] or { run = "python3 extensions/" .. name .. ".py", input = "selection", output = "replace" }
  settings.set("commands", cmds)
  vim.cmd.edit(vim.fn.fnameescape(file))
end

function M.setup()
  apply()
  vim.api.nvim_create_user_command("Commands", M.pick, { desc = "Мои команды-скрипты" })
  vim.api.nvim_create_user_command("ExtensionNew", function(a) M.new(a.args) end, { nargs = 1, desc = "Новое расширение на Python" })
end

M.reload = apply

return M
