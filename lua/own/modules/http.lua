-- Postman в файле и эндпоинты, как в GoLand: .http — enter на запросе отправляет, ответ — в окне справа;
-- пробел r e / alt-a — все маршруты Gin с полным путём (enter — к хендлеру, ctrl-y — curl);
-- пробел r h / alt-p — api.http проекта из маршрутов.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("own.http", { clear = true }),
    pattern = "http",
    callback = function(ev)
      local http = require("own.tools.http")
      local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = ev.buf, desc = desc }) end
      map("<cr>", http.send, "HTTP: отправить запрос под курсором")
      map("<esc>", http.close, "HTTP: закрыть ответ")
      map("<leader>Rs", http.send, "HTTP: отправить")
      map("<leader>Rr", http.replay, "HTTP: повторить последний")
      map("<leader>Rc", http.copy_curl, "HTTP: скопировать как curl")
      map("<leader>Rn", function() http.jump(1) end, "HTTP: следующий запрос")
      map("<leader>Rp", function() http.jump(-1) end, "HTTP: предыдущий запрос")
    end,
  })
end

return M
