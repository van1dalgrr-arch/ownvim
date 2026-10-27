-- JSON-схема для settings.jsonc — подсказки, как в settings.json у VS Code: дополнение ключей и значений,
-- описание по K (из комментариев defaults.jsonc), проверка типов. Собирается сама из defaults.jsonc, тем, тем иконок,
-- модулей, действий и списка серверов nvim-lspconfig; лежит в данных ownvim, jsonls подхватывает её для settings.jsonc.
local jsonc = require("own.jsonc")
local settings = require("own.settings")

local M = {}

M.path = vim.fn.stdpath("data") .. "/own-settings.schema.json"

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- комментарии defaults.jsonc → описание по пути ключа ("statusline.style")
local function comments(text)
  local clean = jsonc.strip(text)
  local out, stack, pending = {}, {}, {}
  local orig_lines = vim.split(text, "\n", { plain = true })
  local clean_lines = vim.split(clean, "\n", { plain = true })
  for i, line in ipairs(clean_lines) do
    local orig = orig_lines[i] or ""
    local only_comment = orig:match("^%s*//%s*(.*)$")
    if only_comment then
      pending[#pending + 1] = only_comment
    else
      local key = line:match('^%s*"([^"]+)"%s*:')
      if key then
        local path = table.concat(vim.list_extend(vim.deepcopy(stack), { key }), ".")
        local inline = orig:match('//%s*(.-)%s*$')
        local desc = table.concat(vim.list_extend(vim.deepcopy(pending), inline and { inline } or {}), " ")
        if desc ~= "" then out[path] = desc end
        -- значение-объект на этой строке и не закрыт на ней — спускаемся
        local rest = line:sub(line:find(":", 1, true) + 1)
        local opens = select(2, rest:gsub("{", "")) - select(2, rest:gsub("}", ""))
        if opens > 0 then stack[#stack + 1] = key end
      else
        local closes = select(2, line:gsub("}", "")) - select(2, line:gsub("{", ""))
        for _ = 1, closes do table.remove(stack) end
      end
      if line:match("%S") then pending = {} end
    end
  end
  return out
end

local function type_of(v)
  if type(v) == "boolean" then return "boolean" end
  if type(v) == "number" then return math.floor(v) == v and "integer" or "number" end
  if type(v) == "string" then return "string" end
  if type(v) == "table" then return (next(v) == nil or not vim.islist(v)) and "object" or "array" end
end

-- схема по значению по умолчанию: объект — свойства, список — items по первому элементу
local function from_value(v, path, desc)
  local s = { description = desc[path] }
  local t = type_of(v)
  if t == "object" then
    s.type = "object"
    s.properties = {}
    for k, x in pairs(v) do s.properties[k] = from_value(x, path .. "." .. k, desc) end
  elseif t == "array" then
    s.type = "array"
    if v[1] ~= nil then s.items = from_value(v[1], path .. "[]", desc) end
  elseif t then
    s.type = t
  end
  return s
end

local function files(dir, ext)
  local out = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%." .. ext .. "$") then out[#out + 1] = name:gsub("%." .. ext .. "$", "") end
  end
  table.sort(out)
  return out
end

function M.build()
  local text = read(settings.files.defaults) or "{}"
  local defaults = jsonc.decode(text) or {}
  local desc = comments(text)
  local root = from_value(defaults, "", {})
  local P = root.properties
  for k, v in pairs(defaults) do P[k] = from_value(v, k, desc) end
  local config = vim.fn.stdpath("config")

  -- тема: имя или { dark, light }; имена — JSON-темы и все colorscheme
  local themes = files(config .. "/themes", "json")
  for _, c in ipairs(vim.fn.getcompletion("", "color")) do
    if not vim.tbl_contains(themes, c) then themes[#themes + 1] = c end
  end
  local theme_name = { type = "string", enum = vim.list_extend({ "auto" }, themes) }
  P.theme = {
    description = desc.theme,
    anyOf = { theme_name, { type = "object", properties = { dark = theme_name, light = theme_name }, additionalProperties = false } },
  }

  -- модули: из файлов; true/false или объект с настройками
  local mods = P.modules.properties
  for _, name in ipairs(files(config .. "/lua/own/modules", "lua")) do
    local d = mods[name] or {}
    mods[name] = { description = d.description, anyOf = { { type = "boolean" }, vim.tbl_extend("force", d.type == "object" and d or {}, { type = "object" }) } }
  end
  P.modules.additionalProperties = false

  -- клавиши: "режимы клавиша": действие | клавиши | :команда | { do, desc, remap… } | false
  local names = vim.tbl_keys(require("own.actions").list)
  table.sort(names)
  local action_desc = {}
  for _, n in ipairs(names) do action_desc[#action_desc + 1] = select(2, require("own.actions").get(n)) end
  local key_value = {
    anyOf = {
      { type = "string", enum = names, markdownEnumDescriptions = action_desc, description = "действие" },
      { type = "string", description = "клавиши как есть (\"<C-w>h\") или :команда" },
      { const = false, description = "убрать клавишу" },
      {
        type = "object",
        properties = {
          ["do"] = { type = "string", description = "действие, клавиши или :команда" },
          desc = { type = "string" }, remap = { type = "boolean" }, expr = { type = "boolean" },
          silent = { type = "boolean" }, nowait = { type = "boolean" },
        },
        required = { "do" },
      },
    },
  }
  P.keys = {
    description = desc.keys,
    type = "object",
    propertyNames = { pattern = "^[nixsotc]+ .+$" },
    additionalProperties = key_value,
  }

  -- статусная строка: блоки — свои и custom
  local blocks = { "mode", "branch", "diagnostics", "file", "filetype", "encoding", "indent", "lsp", "diff", "tests",
    "position", "progress", "time", "search", "macro", "ext", "rest", "quiet", "ram", "uptime", "wpm", "music" }
  local sl = P.statusline.properties
  sl.style.enum = { "frame", "bubbles", "arrows", "slant", "flat", "plain" }
  sl.left.items = { type = "string", examples = blocks }
  sl.right.items = { type = "string", examples = blocks }
  sl.path.enum = { "relative", "name", "full" }
  P.tabline.properties.show.enum = { "auto", "always", "never" }
  P.tabline.properties.style.enum = { "underline", "bar", "slant", "plain" }
  P.icons.properties.theme.enum = files(config .. "/icons", "json")
  P.completion.properties.keymap.enum = { "vscode", "enter", "super-tab", "default" }
  P.tools.properties.install.enum = { "mason", "system" }
  P.format.properties.lsp.enum = { "fallback", "never", "prefer", "first", "last" }

  -- языковые серверы: все имена nvim-lspconfig
  local servers = {}
  for _, f in ipairs(vim.api.nvim_get_runtime_file("lsp/*.lua", true)) do servers[vim.fn.fnamemodify(f, ":t:r")] = true end
  local server_value = { anyOf = { { type = "boolean" }, { type = "object", properties = {
    cmd = { type = "array", items = { type = "string" } }, filetypes = { type = "array", items = { type = "string" } },
    settings = { type = "object" }, init_options = { type = "object" }, root_markers = { type = "array" },
    install = { type = "string", description = "имя пакета mason, если не совпадает" }, enabled = { type = "boolean" },
  } } } }
  local sp = P.lsp.properties.servers.properties
  for name in pairs(servers) do sp[name] = vim.tbl_extend("force", server_value, { description = (sp[name] or {}).description }) end
  P.lsp.properties.servers.additionalProperties = server_value

  -- свои плагины: "автор/плагин": true | false | спецификация lazy.nvim
  P.plugins = {
    description = desc.plugins,
    type = "object",
    propertyNames = { pattern = "^[\\w.-]+/[\\w.-]+$" },
    additionalProperties = { anyOf = { { type = "boolean" }, { type = "object", properties = {
      opts = { type = "object" }, event = {}, cmd = {}, ft = {}, keys = { type = "array" }, branch = { type = "string" },
      version = { type = "string" }, lazy = { type = "boolean" }, main = { type = "string" }, dependencies = { type = "array" },
    } } } },
  }
  -- цвета: общие и "[тема]"
  P.colors = { description = desc.colors, type = "object", properties = {
    palette = { type = "object" }, syntax = { type = "object" }, groups = { type = "object" },
  }, patternProperties = { ["^\\[.+\\]$"] = { type = "object" } } }

  root["$schema"] = "http://json-schema.org/draft-07/schema#"
  root.title = "ownvim settings.jsonc"
  root.additionalProperties = false
  root.allowTrailingCommas = true -- как в settings.json у VS Code: запятая в конце — не ошибка
  root.allowComments = true
  local json = vim.json.encode(root)
  local f = assert(io.open(M.path, "w"))
  f:write(json)
  f:close()
  return M.path
end

return M
