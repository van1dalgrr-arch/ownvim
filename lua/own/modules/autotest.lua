-- Тесты в фоне: сохранил Go-файл — go test пакета (из кэша — мгновенно); в статусной строке ✓ 42 / ✗ 1,
-- упавшая проверка — ошибкой на её строке. Блок "tests" — в statusline.right. пробел t A — вкл/выкл.
local M = {}

function M.setup() require("own.tools.autotest").setup() end

return M
