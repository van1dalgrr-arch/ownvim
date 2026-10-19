-- JSON с комментариями (// и /* */) и запятыми в конце — как settings.json в Zed и VS Code.
-- Комментарии и лишние запятые заменяются пробелами той же длины: позиции не съезжают,
-- и ошибка vim.json указывает на ту же строку и столбец, что в файле.
local M = {}

local function blank(s) return (s:gsub("[^\n]", " ")) end

-- конец строки JSON, которая открылась кавычкой в позиции i (с учётом \")
local function string_end(s, i)
  local j = i + 1
  while true do
    local k = s:find('[\\"\n]', j)
    if not k then return #s end
    local c = s:sub(k, k)
    if c == "\\" then j = k + 2 else return k end
  end
end

-- убрать комментарии, не трогая строки: прыгаем к следующей кавычке или слэшу, а не идём по символу
local function strip_comments(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local k = s:find('["/]', i)
    if not k then
      out[#out + 1] = s:sub(i)
      break
    end
    out[#out + 1] = s:sub(i, k - 1)
    local c, nxt = s:sub(k, k), s:sub(k + 1, k + 1)
    if c == '"' then
      local e = string_end(s, k)
      out[#out + 1] = s:sub(k, e)
      i = e + 1
    elseif nxt == "/" then
      local e = (s:find("\n", k, true) or n + 1) - 1
      out[#out + 1] = blank(s:sub(k, e))
      i = e + 1
    elseif nxt == "*" then
      local _, e = s:find("*/", k + 2, true)
      e = e or n
      out[#out + 1] = blank(s:sub(k, e))
      i = e + 1
    else
      out[#out + 1] = c
      i = k + 1
    end
  end
  return table.concat(out)
end

-- убрать запятую перед } или ] (комментариев уже нет)
local function strip_trailing_commas(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local k = s:find('[",]', i)
    if not k then
      out[#out + 1] = s:sub(i)
      break
    end
    out[#out + 1] = s:sub(i, k - 1)
    if s:sub(k, k) == '"' then
      local e = string_end(s, k)
      out[#out + 1] = s:sub(k, e)
      i = e + 1
    else
      out[#out + 1] = s:find("^%s*[%]}]", k + 1) and " " or ","
      i = k + 1
    end
  end
  return table.concat(out)
end

-- номер строки (с 1) и столбец (с 0) по смещению в тексте
local function position(text, offset)
  local before = text:sub(1, math.max(offset - 1, 0))
  local _, lines = before:gsub("\n", "")
  local last = before:match("[^\n]*$")
  return lines + 1, #last
end

--- Текст без комментариев (заменены пробелами — позиции те же, что в исходном)
M.strip = strip_comments

--- Разобрать JSONC.
--- @return table|nil value, {lnum: integer, col: integer, message: string}|nil err
function M.decode(text)
  local clean = strip_trailing_commas(strip_comments(text))
  if vim.trim(clean) == "" then return {} end
  local ok, value = pcall(vim.json.decode, clean, { luanil = { object = true, array = true } })
  if ok then
    if type(value) ~= "table" then return nil, { lnum = 1, col = 0, message = "ждал объект { … } на верхнем уровне" } end
    return value
  end
  local msg = tostring(value)
  local at = tonumber(msg:match("character (%d+)")) or 1
  local lnum, col = position(clean, at)
  msg = msg:gsub("^.-: ", ""):gsub(" at character %d+", "")
  return nil, { lnum = lnum, col = col, message = "JSON: " .. msg }
end

--- Строка, где в тексте встречается ключ "name" (для подсказок об опечатках)
function M.find_key(text, name)
  local lnum = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lnum = lnum + 1
    local col = line:find('"' .. vim.pesc(name) .. '"%s*:')
    if col then return lnum, col - 1 end
  end
end

return M
