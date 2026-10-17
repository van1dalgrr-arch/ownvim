-- Мелочи из LazyVim, без которых непривычно: подсветка скопированного, окна делятся поровну при
-- изменении размера, курсор там, где был в прошлый раз, q закрывает служебные окна, папка для
-- нового файла создаётся сама, в тексте и коммитах — перенос строк и орфография.
local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("own.basics", { clear = true })
  local au = function(event, opts) vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", { group = group }, opts)) end

  au("TextYankPost", { callback = function() (vim.hl or vim.highlight).on_yank() end })
  au({ "FocusGained", "TermClose", "TermLeave" }, {
    callback = function() if vim.o.buftype ~= "nofile" then vim.cmd("checktime") end end,
  })
  au("VimResized", {
    callback = function()
      local tab = vim.fn.tabpagenr()
      vim.cmd("tabdo wincmd =")
      vim.cmd("tabnext " .. tab)
    end,
  })
  au("BufReadPost", {
    callback = function(ev)
      local exclude = { gitcommit = true, gitrebase = true }
      if exclude[vim.bo[ev.buf].filetype] or vim.b[ev.buf].own_last_loc then return end
      vim.b[ev.buf].own_last_loc = true
      local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
      if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
    end,
  })
  au("FileType", {
    pattern = { "help", "lspinfo", "man", "notify", "qf", "query", "checkhealth", "startuptime", "tsplayground",
      "gitsigns-blame", "grug-far", "dbout", "neotest-output", "neotest-summary", "neotest-output-panel" },
    callback = function(ev)
      vim.bo[ev.buf].buflisted = false
      vim.schedule(function()
        vim.keymap.set("n", "q", function()
          vim.cmd("close")
          pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
        end, { buffer = ev.buf, silent = true, desc = "Закрыть" })
      end)
    end,
  })
  au("FileType", {
    pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
    callback = function()
      vim.opt_local.wrap = true
      vim.opt_local.spell = true
    end,
  })
  au("FileType", { pattern = { "json", "jsonc", "json5" }, callback = function() vim.opt_local.conceallevel = 0 end })
  au("BufWritePre", {
    callback = function(ev)
      if ev.match:match("^%w%w+:[\\/][\\/]") then return end
      local file = vim.uv.fs_realpath(ev.match) or ev.match
      vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
    end,
  })
end

return M
