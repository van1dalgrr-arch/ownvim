-- Задачи, как ctrl-r в Zed / Run Configurations в GoLand: список — в settings.jsonc, запуск — пробел r r.
-- Раздел "tasks": { "list": [ { "name": "…", "cmd": "…", "when": ["go.mod"], "cwd": "root" | "file" } ] }
--   when — задача видна, только если в корне проекта есть хоть один из файлов (нет when — всегда)
--   ft — только когда открыт файл этого языка: ["cpp", "c"]
--   в cmd подставляется: ${root} — корень проекта, ${file} — текущий файл, ${file_dir} — его папка,
--   ${image} — имя образа (папка проекта):dev
local settings = require("own.settings")

local M = {}

local function list() return ((settings.current or {}).tasks or {}).list or {} end

local function expand(cmd)
  local root = require("own.root").get()
  local vars = {
    root = root,
    file = vim.fn.expand("%:p"),
    file_dir = vim.fn.expand("%:p:h"),
    image = vim.fn.fnamemodify(root, ":t"):lower():gsub(" ", "-") .. ":dev",
  }
  return (cmd:gsub("%${(%w+)}", function(k) return vars[k] and vim.fn.shellescape(vars[k]) or "${" .. k .. "}" end))
end

local function register()
  local overseer = require("overseer")
  for _, t in ipairs(list()) do
    overseer.register_template({
      name = t.name,
      builder = function()
        local cwd = t.cwd == "file" and vim.fn.expand("%:p:h") or require("own.root").get()
        return { name = t.name, cmd = expand(t.cmd), cwd = cwd }
      end,
      condition = (t.when or t.ft) and {
        callback = function(search)
          if t.ft then
            local fts = type(t.ft) == "table" and t.ft or { t.ft }
            if not vim.tbl_contains(fts, search.filetype or vim.bo.filetype) then return false end
          end
          if not t.when then return true end
          for _, f in ipairs(type(t.when) == "table" and t.when or { t.when }) do
            if vim.uv.fs_stat(search.dir .. "/" .. f) then return true end
          end
          return false
        end,
      } or nil,
    })
  end
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

function M.reload()
  if package.loaded["overseer"] then
    vim.notify("tasks: список задач обновится после :restart", vim.log.levels.WARN)
  end
end

return M
