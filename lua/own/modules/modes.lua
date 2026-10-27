-- Режим видно сразу: курсор, строка и номер зеленеют во вставке, фиолетовые в выделении.
-- Не печатаешь auto_normal_ms миллисекунд — сам выходит из вставки (0 — никогда; пробел u I — выкл на время).
-- Выход из вставки быстрым jk (и ол в русской раскладке): j сразу становится текстом, а если следом
-- за escape_ms пришла k — j стирается и вставка закончена. (Обычная привязка «i jk» держит j «в ожидании»
-- до timeoutlen: на экране она видна, но дополнение и автокоманды её ещё не видят; и «ол» так не сделать —
-- langmap во вставке не действует.) "escape": [] — выключить.
-- Сама логика — lua/own/modes.lua.
local M = {}

local seqs, window_ms = {}, 200
local last = { char = nil, at = 0, row = -1, col = -1 }

local function on_char()
  local c = vim.v.char
  local now = vim.uv.hrtime() / 1e6
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  for _, s in ipairs(seqs) do
    if c == s[2] and last.char == s[1] and now - last.at <= window_ms and row == last.row and col == last.col + #s[1] then
      last.char = nil
      vim.v.char = ""
      -- в InsertCharPre буфер менять нельзя — стереть первую букву и выйти клавишами
      vim.api.nvim_feedkeys(vim.keycode("<BS><Esc>"), "n", false)
      return
    end
  end
  last = { char = c, at = now, row = row, col = col }
end

function M.setup(opts)
  M.reload(opts)
  require("own.modes").setup()
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = vim.api.nvim_create_augroup("own.escape", { clear = true }),
    callback = function() if #seqs > 0 and vim.fn.reg_executing() == "" then on_char() end end,
  })
end

function M.reload(opts)
  local ms = opts.auto_normal_ms or 5000
  vim.g.auto_normal_ms = ms > 0 and ms or nil
  if ms <= 0 then vim.g.auto_normal = false end
  seqs = {}
  for _, s in ipairs(opts.escape or { "jk", "ол" }) do
    if vim.fn.strchars(s) == 2 then seqs[#seqs + 1] = { vim.fn.strcharpart(s, 0, 1), vim.fn.strcharpart(s, 1, 1) } end
  end
  window_ms = opts.escape_ms or 200
  if package.loaded["own.modes"] then require("own.modes").reload() end -- appearance.cursor_by_mode
end

return M
