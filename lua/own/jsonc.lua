-- JSON с комментариями (// и /* */) и запятыми в конце — как settings.json в Zed и VS Code.
-- Комментарии и лишние запятые заменяются пробелами той же длины: позиции не съезжают,
-- и ошибка vim.json указывает на ту же строку и столбец, что в файле.
local M = {}

local function blank(s) return (s:gsub("[^\n]", " ")) end

-- убрать комментарии, не трогая строки
local function strip_comments(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then j = j + 1 elseif d == '"' or d == "\n" then break end
        j = j + 1
      end
      out[#out + 1] = s:sub(i, j)
      i = j + 1
    elseif s:sub(i, i + 1) == "//" then
      local j = s:find("\n", i, true) or n + 1
      out[#out + 1] = blank(s:sub(i, j - 1))
      i = j
    elseif s:sub(i, i + 1) == "/*" then
      local _, j = s:find("*/", i + 2, true)
      j = j or n
      out[#out + 1] = blank(s:sub(i, j))
      i = j + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- убрать запятую перед } или ] (комментариев уже нет)
local function strip_trailing_commas(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then j = j + 1 elseif d == '"' then break end
        j = j + 1
      end
      out[#out + 1] = s:sub(i, j)
      i = j + 1
    elseif c == "," and s:find("^%s*[%]}]", i + 1) then
      out[#out + 1] = " "
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
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
