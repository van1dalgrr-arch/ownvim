-- Задачи, как ctrl-r в Zed / Run Configurations в GoLand: список — в settings.jsonc, запуск — пробел r r.
-- Раздел "tasks": { "list": [ { "name": "…", "cmd": "…", "when": ["go.mod"], "cwd": "root" | "file" } ] }
--   when — задача видна, только если в корне проекта есть хоть один из файлов (нет when — всегда)
--   ft — только когда открыт файл этого языка: ["cpp", "c"]
--   в cmd подставляется: ${root} — корень проекта, ${file} — текущий файл, ${file_dir} — его папка,
--   ${image} — имя образа (папка проекта):dev, ${input:Подсказка} — спросить при запуске
--   env — файл(ы) с переменными для задачи: ".env" или [".env", ".env.local"]
-- Правка списка видна сразу, без :restart.
local settings = require("own.settings")

local M = {}

local function list() return ((settings.current or {}).tasks or {}).list or {} end

-- .env проекта → переменные задачи: KEY=value, export KEY=value, кавычки снимаются, # — комментарий
local function read_env(path)
  local env = {}
  local f = io.open(path)
  if not f then return env end
  for line in f:lines() do
    local k, v = line:match("^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$")
    if not k then k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$") end
    if k then
      local q = v:sub(1, 1)
      if (q == '"' or q == "'") and v:sub(-1) == q and #v > 1 then v = v:sub(2, -2) else v = v:gsub("%s+#.*$", "") end
      env[k] = v
    end
  end
  f:close()
  return env
end

-- ${input:Подсказка} — спросить при запуске (окно параметров overseer); одинаковые подсказки — одно поле.
-- Подсказка и есть имя поля, а пробелы в именах overseer запрещает — меняем их на неразрывные
local function key(label) return (label:gsub(" ", "\u{00a0}")) end

local function inputs(cmd)
  local params = {}
  for label in cmd:gmatch("%${input:([^}]+)}") do
    if not params[key(label)] then params[key(label)] = { type = "string", order = vim.tbl_count(params) + 1 } end
  end
  return params
end

local function expand(cmd, params)
  local root = require("own.root").get()
  local vars = {
    root = root,
    file = vim.fn.expand("%:p"),
    file_dir = vim.fn.expand("%:p:h"),
    image = vim.fn.fnamemodify(root, ":t"):lower():gsub(" ", "-") .. ":dev",
  }
  cmd = cmd:gsub("%${input:([^}]+)}", function(label) return vim.fn.shellescape((params or {})[key(label)] or "") end)
  return (cmd:gsub("%${(%w+)}", function(k) return vars[k] and vim.fn.shellescape(vars[k]) or "${" .. k .. "}" end))
end

local function visible(t, search)
  if t.ft then
    local fts = type(t.ft) == "table" and t.ft or { t.ft }
    if not vim.tbl_contains(fts, search.filetype or vim.bo.filetype) then return false end
  end
  if not t.when then return true end
  for _, f in ipairs(type(t.when) == "table" and t.when or { t.when }) do
    if vim.uv.fs_stat(search.dir .. "/" .. f) then return true end
  end
  return false
end

local function template(t)
  return {
    name = t.name,
    params = inputs(t.cmd),
    builder = function(params)
      local root = require("own.root").get()
      local cwd = t.cwd == "file" and vim.fn.expand("%:p:h") or root
      local env
      if t.env then
        env = {}
        for _, file in ipairs(type(t.env) == "table" and t.env or { t.env }) do
          env = vim.tbl_extend("force", env, read_env(root .. "/" .. file))
        end
      end
      return { name = t.name, cmd = expand(t.cmd, params), cwd = cwd, env = env }
    end,
  }
end

-- один поставщик на весь список: overseer спрашивает его при каждом открытии, поэтому правка
-- settings.jsonc видна сразу, без :restart
local function register()
  require("overseer").register_template({
    name = "own.tasks",
    generator = function(search)
      local out = {}
      for _, t in ipairs(list()) do
        if visible(t, search) then out[#out + 1] = template(t) end
      end
      return out
    end,
  })
end

function M.plugins()
  return {
    {
      "stevearc/overseer.nvim",
      cmd = { "OverseerRun", "OverseerToggle", "OverseerRunCmd" },
      config = function()
        require("overseer").setup({ dap = false })
        register()
      end,
    },
  }
end

return M
