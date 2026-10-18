-- Режим видно сразу: курсор, строка и номер зеленеют во вставке, фиолетовые в выделении.
-- Не печатаешь auto_normal_ms миллисекунд — сам выходит из вставки (0 — никогда; пробел u I — выкл на время).
-- Сама логика — lua/own/modes.lua.
local M = {}

function M.setup(opts)
  M.reload(opts)
  require("own.modes").setup()
end

function M.reload(opts)
  local ms = opts.auto_normal_ms or 5000
  vim.g.auto_normal_ms = ms > 0 and ms or nil
  if ms <= 0 then vim.g.auto_normal = false end
end

return M
