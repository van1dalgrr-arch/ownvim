-- Вернуть закрытый файл — как cmd-shift-t в VS Code (пробел b u): закрытые буферы запоминаются стопкой
-- вместе с местом курсора; каждое нажатие возвращает следующий.
local M = {}

local closed = {}

function M.reopen()
  while #closed > 0 do
    local it = table.remove(closed)
    if vim.fn.filereadable(it.path) == 1 and vim.fn.bufloaded(it.path) == 0 then
      vim.cmd.edit(vim.fn.fnameescape(it.path))
      pcall(vim.api.nvim_win_set_cursor, 0, it.pos)
      return
    end
  end
  vim.notify("закрытых файлов нет")
end

function M.setup()
  vim.api.nvim_create_autocmd("BufDelete", {
    group = vim.api.nvim_create_augroup("own.reopen", { clear = true }),
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or not vim.bo[ev.buf].buflisted then return end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == "" then return end
      local pos = vim.api.nvim_buf_get_mark(ev.buf, '"')
      closed[#closed + 1] = { path = path, pos = { math.max(pos[1], 1), pos[2] } }
      if #closed > 30 then table.remove(closed, 1) end
    end,
  })
end

return M
