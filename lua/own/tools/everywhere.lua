-- Поиск везде (Search Everywhere из GoLand): пробел пробел — одно окно на всё.
-- Файлы проекта, действия ownvim (с их клавишами), конфигурации запуска, режимы, темы — печатаешь, что нужно,
-- а не вспоминаешь, какой клавишей это ищется. «#» первым символом — символы проекта (LSP).
local M = {}

local function keys_of()
  -- действие → клавиша из раздела keys: показать справа, чтобы клавиши запоминались сами
  local out = {}
  for lhs, what in pairs(((require("own.settings").current or {}).keys) or {}) do
    local name = type(what) == "string" and what or nil
    if name and not out[name] then
      local key = lhs:match("^%S+%s+(.+)$") or lhs
      out[name] = key:gsub("<leader>", "␣ "):gsub("<space>", "␣ ")
    end
  end
  return out
end

local function run_action(name)
  local fn = require("own.actions").get(name)
  if type(fn) == "function" then return fn() end
  if type(fn) == "string" then vim.api.nvim_feedkeys(vim.keycode(fn), "m", false) end
end

local function own_items()
  local items = {}
  local keys = keys_of()
  for name, a in pairs(require("own.actions").list) do
    local desc = a[2] or name
    items[#items + 1] = { text = desc .. " " .. name, desc = desc, name = name, key = keys[name], kind = "action",
      icon = "\u{ea86}" }
  end
  local ws = require("own.modules.workspace")
  for i, m in ipairs(ws.modes) do
    items[#items + 1] = { text = "Режим " .. m.title .. " mode " .. m.name, desc = "Режим: " .. m.title, kind = "mode",
      mode = m.name, key = "␣ " .. i, icon = m.icon }
  end
  local launch = require("own.tools.launch")
  launch.list(function() end) -- прогреть: конфигурации Go ищутся в фоне и появятся со следующего открытия
  for _, c in ipairs(launch.cached() or {}) do
    items[#items + 1] = { text = "Запустить " .. c.name .. " run " .. (c.detail or ""), desc = "Запустить: " .. c.name,
      kind = "run", conf = c, icon = "\u{f040a}" }
  end
  for _, it in ipairs(require("snacks.picker.source.vim").colorschemes()) do
    if not it.file:find(vim.fs.normalize(vim.env.VIMRUNTIME), 1, true) then
      items[#items + 1] = { text = "Тема " .. it.text .. " theme", desc = "Тема: " .. it.text, kind = "theme", theme = it.text,
        icon = "\u{f03d8}" }
    end
  end
  table.sort(items, function(a, b) return a.desc < b.desc end)
  return items
end

local function format_own(item)
  local ret = {
    { (item.icon or "•") .. "  ", item.kind == "action" and "Special" or "Function" },
    { item.desc, "Normal" },
  }
  if item.key then
    ret[#ret + 1] = { "  " .. item.key, "Comment" }
  end
  return ret
end

local function confirm_own(picker, item)
  picker:close()
  if not item then return end
  vim.schedule(function()
    if item.kind == "action" then return run_action(item.name) end
    if item.kind == "mode" then return require("own.modules.workspace").set_mode(item.mode) end
    if item.kind == "theme" then
      vim.cmd.colorscheme(item.theme)
      local s = require("own.settings")
      local cur = (s.current or {}).theme
      if type(cur) == "table" then cur = vim.deepcopy(cur); cur[vim.o.background] = item.theme else cur = item.theme end
      s.set("theme", cur)
      return
    end
    if item.kind == "run" then
      require("own.modules.workspace").set_project("run", item.conf.id)
      return require("own.tools.launch").run()
    end
  end)
end

function M.open()
  local root = require("own.root").get()
  Snacks.picker.pick({
    title = "Везде · файлы, действия, запуск, темы",
    multi = {
      { source = "files", cwd = root },
      { finder = function() return own_items() end, format = format_own,
        confirm = confirm_own, preview = "none" },
    },
    matcher = { frecency = true, sort_empty = false },
    layout = { preset = "vscode" },
    win = {
      input = {
        keys = {
          -- «#» — символы проекта (LSP)
          ["#"] = { function(picker)
            if picker.input:get() ~= "" then return vim.api.nvim_feedkeys("#", "n", false) end
            picker:close()
            vim.schedule(function() Snacks.picker.lsp_workspace_symbols() end)
          end, mode = "i" },
        },
      },
    },
  })
end

return M
