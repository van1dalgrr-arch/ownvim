-- Автосохранение: вышел из вставки, поправил в обычном режиме, ушёл в другое окно — файл записан.
-- Запись запускает форматирование (в Go — goimports и gofumpt, этап «Go как IDE»).
-- Выключить на время: :let g:autosave = v:false. Файлы, которые поменяли снаружи (Claude Code, git,
-- go generate), подхватываются сами — после паузы в наборе и при переходе между буферами.
local M = {}

function M.setup()
  vim.g.autosave = true
  local group = vim.api.nvim_create_augroup("own.autosave", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost", "BufLeave" }, {
    group = group,
    nested = true, -- иначе запись не запустит BufWritePre, и форматирование не сработает
    callback = function(ev)
      local b = vim.bo[ev.buf]
      if not vim.g.autosave or b.buftype ~= "" or not b.modifiable or b.readonly or not b.modified then return end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name == "" or vim.fn.filereadable(name) == 0 then return end
      vim.api.nvim_buf_call(ev.buf, function() vim.cmd("silent! write") end)
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "BufEnter" }, {
    group = group,
    nested = true, -- чтобы после перечитывания сработали подсветка и LSP
    callback = function()
      if vim.fn.mode() ~= "c" and vim.bo.buftype == "" then vim.cmd("silent! checktime") end
    end,
  })
end

return M
