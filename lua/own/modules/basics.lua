-- Мелочи из LazyVim, без которых непривычно: подсветка скопированного, окна делятся поровну при
-- изменении размера, курсор там, где был в прошлый раз, q закрывает служебные окна, папка для
-- нового файла создаётся сама, в тексте и коммитах — перенос строк и орфография.
local M = {}

-- скопированное вспыхивает цветом акцента и плавно гаснет (а не мигает оранжевым IncSearch)
local yank_ns = vim.api.nvim_create_namespace("own.yank")
local FADE = { 0.38, 0.38, 0.3, 0.22, 0.14, 0.07 } -- доли цвета по шагам, шаг — 45 мс
local function yank_flash()
  local ev = vim.v.event
  if ev.operator ~= "y" then return end
  local hex = function(group, attr)
    local v = vim.api.nvim_get_hl(0, { name = group, link = false })[attr or "fg"]
    return v and ("#%06x"):format(v)
  end
  local color = require("own.theme.color")
  local accent = hex("OwnIconAccent") or hex("IncSearch", "bg") or "#bb9af7"
  local bg = hex("Normal", "bg") or (vim.o.background == "light" and "#ffffff" or "#000000")
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.api.nvim_buf_get_mark(buf, "["), vim.api.nvim_buf_get_mark(buf, "]")
  local step = 0
  local timer = vim.uv.new_timer()
  if not timer then return end
  timer:start(0, 45, vim.schedule_wrap(function()
    step = step + 1
    if not vim.api.nvim_buf_is_valid(buf) then step = #FADE + 1 end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, yank_ns, 0, -1) end
    if step > #FADE then
      if not timer:is_closing() then timer:close() end
      return
    end
    vim.api.nvim_set_hl(0, "OwnYank", { bg = color.blend(accent, bg, FADE[step]) })
    vim.hl.range(buf, yank_ns, "OwnYank", { s[1] - 1, s[2] }, { e[1] - 1, e[2] },
      { regtype = ev.regtype, inclusive = true })
  end))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.basics", { clear = true })
  local au = function(event, opts) vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", { group = group }, opts)) end

  au("TextYankPost", { callback = yank_flash })
  au({ "FocusGained", "TermClose", "TermLeave" }, {
    callback = function() if vim.o.buftype ~= "nofile" then vim.cmd("checktime") end end,
  })
  au("VimResized", {
    callback = function()
      local tab = vim.fn.tabpagenr()
      vim.cmd("tabdo wincmd =")
      vim.cmd("tabnext " .. tab)
      -- окно стало шире — вернуть сдвиг вбок, иначе код так и остаётся обрезанным слева («turn» вместо «return»)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if not vim.wo[win].wrap then
          vim.api.nvim_win_call(win, function()
            local view = vim.fn.winsaveview()
            local width = vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
            if view.leftcol > 0 and vim.fn.virtcol(".") < width then
              view.leftcol = 0
              vim.fn.winrestview(view)
            end
          end)
        end
      end
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
