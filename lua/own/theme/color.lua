-- Цвета: "#rrggbb" ↔ числа, смешивание, прозрачность VS Code (#rrggbbaa) поверх фона.
local M = {}

function M.rgb(hex)
  hex = hex:gsub("^#", "")
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function M.hex(r, g, b)
  local function c(x) return math.max(0, math.min(255, math.floor(x + 0.5))) end
  return string.format("#%02x%02x%02x", c(r), c(g), c(b))
end

--- a поверх b с долей alpha (0..1)
function M.blend(a, b, alpha)
  local r1, g1, b1 = M.rgb(a)
  local r2, g2, b2 = M.rgb(b)
  return M.hex(r1 * alpha + r2 * (1 - alpha), g1 * alpha + g2 * (1 - alpha), b1 * alpha + b2 * (1 - alpha))
end

--- светлее (amount > 0) или темнее (< 0)
function M.shade(c, amount)
  return amount > 0 and M.blend("#ffffff", c, amount) or M.blend("#000000", c, -amount)
end

function M.is_hex(s) return type(s) == "string" and s:match("^#%x%x%x%x%x%x%x?%x?$") ~= nil or (type(s) == "string" and s:match("^#%x%x%x$") ~= nil) end

--- "#abc" → "#aabbcc", "#rrggbbaa" → смешать с фоном
function M.normalize(c, bg)
  if type(c) ~= "string" then return nil end
  if c:match("^#%x%x%x$") then c = "#" .. c:sub(2, 2):rep(2) .. c:sub(3, 3):rep(2) .. c:sub(4, 4):rep(2) end
  if c:match("^#%x%x%x%x%x%x%x%x$") then
    local a = tonumber(c:sub(8, 9), 16) / 255
    return bg and M.blend(c:sub(1, 7), bg, a) or c:sub(1, 7)
  end
  if c:match("^#%x%x%x%x$") then return M.normalize("#" .. c:sub(2, 2):rep(2) .. c:sub(3, 3):rep(2) .. c:sub(4, 4):rep(2) .. c:sub(5, 5):rep(2), bg) end
  return c:match("^#%x%x%x%x%x%x$") and c:lower() or nil
end

--- яркость 0..1 (для «тёмная/светлая»)
function M.luminance(c)
  local r, g, b = M.rgb(c)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
end

return M
