-- Редактор настроек — как Settings в VS Code (cmd-, / пробел f s): все настройки списком с поиском и описанием.
--   ● — значение своё (отличается от умолчания). enter — поменять: да/нет переключается сразу, остальное — спросит.
--   ctrl-r — вернуть умолчание, ctrl-o — открыть settings.jsonc на этом разделе.
-- Пишется в settings.jsonc и применяется на лету. Разделы, где в settings.jsonc есть свои комментарии
-- (клавиши, задачи), через список не переписываются — откроется файл, чтобы комментарии не пропали.
local settings = require("own.settings")

local M = {}

local function is_dict(t) return type(t) == "table" and (next(t) == nil or not vim.islist(t)) end

-- большие разделы-списки правят в файле: в списке с поиском им не место
local SKIP = { keys = true, plugins = true, tasks = true, commands = true, checks = true, snippets = true }

local function flatten(value, path, out)
  for k, v in pairs(value) do
    local p = path and (path .. "." .. k) or k
    if is_dict(v) and next(v) ~= nil then flatten(v, p, out) else out[#out + 1] = { path = p, default = v } end
  end
end

local function get(t, path)
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local function show(v)
  if v == nil then return "—" end
  local s = type(v) == "table" and vim.json.encode(v) or tostring(v)
  if type(v) == "string" then s = '"' .. v .. '"' end
  return #s > 48 and (s:sub(1, 47) .. "…") or s
end

--- Записать значение по пути "statusline.style" в свой слой (nil — убрать, вернётся умолчание)
function M.write(path, value)
  local parts = vim.split(path, ".", { plain = true })
  local top = parts[1]
  if settings.has_comments(top) then
    vim.notify(('в разделе "%s" твои комментарии — правь в файле, чтобы они не пропали'):format(top))
    return settings.open_at(top)
  end
  local user = settings.user()
  if #parts == 1 then
    if value == nil then value = get(settings.defaults(), path) end -- верхний ключ не убрать — пишем умолчание
    return settings.set(top, value)
  end
  local block = user[top]
  -- "modules": { "modes": true } → чтобы поменять поле внутри, нужен объект
  if not is_dict(block) then block = {} end
  block = vim.deepcopy(block)
  local t = block
  for i = 2, #parts - 1 do
    if not is_dict(t[parts[i]]) then t[parts[i]] = {} end
    t = t[parts[i]]
  end
  t[parts[#parts]] = value
  settings.set(top, next(block) and block or vim.empty_dict())
end

local function items()
  local defaults, user, cur = settings.defaults(), settings.user(), settings.current or {}
  local desc = require("own.schema").descriptions()
  local leaves = {}
  for k, v in pairs(defaults) do
    if not SKIP[k] then
      if is_dict(v) and next(v) ~= nil then flatten(v, k, leaves) else leaves[#leaves + 1] = { path = k, default = v } end
    end
  end
  table.sort(leaves, function(a, b) return a.path < b.path end)
  for _, it in ipairs(leaves) do
    it.value = get(cur, it.path)
    if it.value == nil then it.value = it.default end
    it.mine = get(user, it.path) ~= nil and not vim.deep_equal(it.value, it.default)
    it.desc = desc[it.path] or ""
    it.text = it.path .. " " .. it.desc
    it.preview = {
      ft = "markdown",
      text = ("# %s\n\n%s\n\n- сейчас: `%s`\n- по умолчанию: `%s`\n\nenter — поменять · ctrl-r — вернуть умолчание · ctrl-o — открыть в settings.jsonc")
        :format(it.path, it.desc ~= "" and it.desc or "_без описания_", vim.json.encode(it.value), vim.json.encode(it.default)),
    }
  end
  return leaves
end

local function edit(it, reopen)
  if type(it.value) == "boolean" then
    M.write(it.path, not it.value)
    return reopen()
  end
  local shown = type(it.value) == "string" and it.value or vim.json.encode(it.value)
  vim.ui.input({ prompt = it.path .. ": ", default = shown }, function(text)
    if text == nil then return reopen() end
    local value
    if type(it.default) == "string" then
      value = text
    else
      local ok, v = pcall(vim.json.decode, text)
      if not ok then return vim.notify("не разобрать значение: " .. text, vim.log.levels.WARN) end
      value = v
    end
    M.write(it.path, value)
    reopen()
  end)
end

function M.open(query)
  local function reopen(q) return function() vim.schedule(function() M.open(q) end) end end
  Snacks.picker.pick({
    title = "Настройки",
    items = items(),
    pattern = query,
    format = function(it)
      return {
        { it.mine and "● " or "  ", "DiagnosticOk" },
        { it.path, it.mine and "Title" or "Normal" },
        { "  " .. show(it.value), type(it.value) == "boolean" and (it.value and "DiagnosticOk" or "Comment") or "String" },
        { it.desc ~= "" and ("  " .. it.desc) or "", "Comment" },
      }
    end,
    preview = "preview",
    confirm = function(picker, it)
      local q = picker.input and picker.input.filter and picker.input.filter.pattern or nil
      picker:close()
      if it then edit(it, reopen(q)) end
    end,
    actions = {
      own_reset = function(picker, it)
        if not it then return end
        local q = picker.input and picker.input.filter and picker.input.filter.pattern or nil
        picker:close()
        M.write(it.path, nil)
        reopen(q)()
      end,
      own_file = function(picker, it)
        picker:close()
        if it then settings.open_at(vim.split(it.path, ".", { plain = true })[1]) end
      end,
    },
    win = { input = { keys = {
      ["<c-r>"] = { "own_reset", mode = { "n", "i" } },
      ["<c-o>"] = { "own_file", mode = { "n", "i" } },
    } } },
  })
end

return M
