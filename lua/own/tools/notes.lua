-- Заметки о неудобствах: пробел ? — «вот тут неудобно», записывается вместе с местом (проект, файл, строка, режим,
-- выделение, последняя команда). Хранятся в данных ownvim (~/.local/share/ownvim/own-notes.json), не в проекте.
-- :Notes (пробел N) — список: enter — к месту, ctrl-x — решено (убрать), ctrl-y — всё в буфер обмена (markdown).
local M = {}

M.path = vim.fn.stdpath("data") .. "/own-notes.json"

local function read()
  local f = io.open(M.path)
  if not f then return {} end
  local ok, t = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(t) == "table" and t or {}
end

local function write(list)
  local f = assert(io.open(M.path, "w"))
  f:write(vim.json.encode(list))
  f:close()
end

-- где сейчас: снимается до окна ввода, пока курсор ещё в коде
local function context()
  local mode = vim.fn.mode()
  local ctx = {
    time = os.date("%Y-%m-%d %H:%M"),
    project = vim.fs.basename(require("own.root").get()),
    file = vim.api.nvim_buf_get_name(0),
    line = vim.fn.line("."),
    col = vim.fn.col("."),
    mode = mode,
    ft = vim.bo.filetype,
    last_cmd = vim.fn.histget(":", -1),
  }
  if vim.bo.buftype ~= "" then ctx.file = "" end
  if mode:match("[vV\22]") then
    local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
    local ok, sel = pcall(vim.fn.getregion, a, b, { type = mode })
    if ok then ctx.selection = table.concat(sel, "\n"):sub(1, 500) end
    vim.cmd("normal! \27")
  end
  return ctx
end

function M.add()
  local ctx = context()
  local where = ctx.file ~= "" and (" · %s:%d"):format(vim.fn.fnamemodify(ctx.file, ":t"), ctx.line) or ""
  vim.ui.input({ prompt = "Что неудобно?" .. where .. " " }, function(text)
    if not text or vim.trim(text) == "" then return end
    ctx.text = vim.trim(text)
    local list = read()
    list[#list + 1] = ctx
    write(list)
    vim.notify(("записал — заметок: %d (пробел N — список)"):format(#list))
  end)
end

local function markdown(list)
  local out = { "# Неудобства ownvim", "" }
  for _, n in ipairs(list) do
    local where = n.file ~= "" and (" — `%s:%d`"):format(vim.fn.fnamemodify(n.file, ":~"), n.line) or ""
    out[#out + 1] = ("- **%s** · %s · режим %s · %s%s"):format(n.text, n.project or "?", n.mode or "?", n.time or "", where)
    if n.selection then out[#out + 1] = "  выделено: `" .. n.selection:gsub("\n", "⏎") .. "`" end
  end
  return table.concat(out, "\n")
end

function M.list()
  local list = read()
  if #list == 0 then return vim.notify("заметок нет — пробел ? записать неудобство") end
  local items = {}
  for i = #list, 1, -1 do -- новые сверху
    local n = list[i]
    items[#items + 1] = {
      idx = i,
      note = n,
      text = table.concat({ n.text, n.project or "", n.file or "", n.ft or "" }, " "),
      file = n.file ~= "" and vim.uv.fs_stat(n.file or "") and n.file or nil,
      pos = n.file ~= "" and { n.line or 1, math.max((n.col or 1) - 1, 0) } or nil,
      preview = (n.file == "" or not vim.uv.fs_stat(n.file or "")) and { text = markdown({ n }), ft = "markdown" } or nil,
    }
  end
  Snacks.picker.pick({
    title = ("Неудобства · %d"):format(#list),
    items = items,
    format = function(item)
      local n = item.note
      local where = n.file ~= "" and ("  %s:%d"):format(vim.fn.fnamemodify(n.file, ":t"), n.line) or ""
      return {
        { (n.time or ""):sub(6) .. "  ", "Comment" },
        { n.text, "Normal" },
        { "  " .. (n.project or ""), "Title" },
        { where, "Comment" },
      }
    end,
    preview = function(ctx)
      if ctx.item.file then return Snacks.picker.preview.file(ctx) end
      return Snacks.picker.preview.preview(ctx)
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.cmd.edit(vim.fn.fnameescape(item.file))
        pcall(vim.api.nvim_win_set_cursor, 0, { item.pos[1], item.pos[2] })
      end
    end,
    actions = {
      own_done = function(picker, item)
        if not item then return end
        local all = read()
        table.remove(all, item.idx)
        write(all)
        picker:close()
        vim.notify("убрал — осталось " .. #all)
        if #all > 0 then vim.schedule(M.list) end
      end,
      own_copy = function()
        vim.fn.setreg("+", markdown(read()))
        vim.notify("все заметки в буфере обмена (markdown)")
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-x>"] = { "own_done", mode = { "n", "i" }, desc = "решено — убрать" },
          ["<C-y>"] = { "own_copy", mode = { "n", "i" }, desc = "всё в буфер обмена" },
        },
      },
    },
  })
end

function M.setup()
  vim.api.nvim_create_user_command("Notes", M.list, { desc = "Заметки о неудобствах" })
  vim.api.nvim_create_user_command("NoteAdd", M.add, { desc = "Записать неудобство" })
end

return M
