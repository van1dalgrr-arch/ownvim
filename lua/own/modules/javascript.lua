-- JavaScript / TypeScript как Go: ▶ слева от тестов (it / test / describe в *.test.js, *.spec.ts) и у файлов
-- с #!/usr/bin/env node; пробел r x — запустить (файл — node, тест — neotest: vitest / jest), пробел r X — в отладчике
-- (js-debug, ставится сам). Сервер vtsls — дополнение с автоимпортом, подсказки типов (пробел c t — вписать),
-- prettierd при сохранении, eslint — если в проекте есть его конфиг. TypeScript node запускает сам (node 23.6+).
-- modules.javascript: { "run_marks": true }
local tools = require("own.tools")

local M = {}

local FT = { "javascript", "typescript", "javascriptreact", "typescriptreact" }

function M.setup(opts)
  opts = type(opts) == "table" and opts or {}
  if opts.run_marks ~= false then require("own.tools.run").setup("javascript") end
  -- отладчик js-debug — когда открыт JS/TS-файл
  if tools.mason() then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("own.javascript", { clear = true }),
      pattern = FT,
      once = true,
      callback = function()
        if not tools.installed("js-debug-adapter") then tools.install("js-debug-adapter", "js-debug", function() end) end
      end,
    })
  end
end

return M
