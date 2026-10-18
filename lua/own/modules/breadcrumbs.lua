-- Хлебные крошки в верхней строке окна, как в VS Code: папка › файл › тип › функция под курсором.
-- Символы — по дереву разбора (treesitter), без языкового сервера: работает сразу и в любом языке.
-- Раздел "breadcrumbs": { "path": true, "symbols": true, "separator": " › ", "max_depth": 3 } — на лету.
local settings = require("own.settings")

local M = {}

local function o() return (settings.current or {}).breadcrumbs or {} end

-- узлы, которые считаются «символами», и вид для значка
local KINDS = {
  function_declaration = "Function", function_definition = "Function", function_item = "Function",
  method_declaration = "Method", method_definition = "Method", func_literal = "Function",
  type_spec = "Struct", type_declaration = "Struct", struct_item = "Struct", impl_item = "Class",
  class_definition = "Class", class_declaration = "Class", interface_declaration = "Interface",
  trait_item = "Interface", enum_item = "Enum", module = "Module", mod_item = "Module",
}

local function name_of(node, buf)
  local n = node:field("name")[1]
  if not n and node:type() == "impl_item" then n = node:field("type")[1] end
  if not n then return node:type() == "func_literal" and "func" or nil end
  return vim.treesitter.get_node_text(n, buf):gsub("%s+", " ")
end

local function symbols(win, buf)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { vim.api.nvim_win_get_cursor(win)[1] - 1, vim.api.nvim_win_get_cursor(win)[2] } })
  if not ok or not node then return {} end
  local out = {}
  while node do
    local kind = KINDS[node:type()]
    if kind then
      local name = name_of(node, buf)
      if name then table.insert(out, 1, { kind = kind, name = name }) end
    end
    node = node:parent()
  end
  return out
end

local function esc(s) return (s:gsub("%%", "%%%%")) end

function M.render()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local opts = o()
  local sep = "%#OwnCrumbSep#" .. (opts.separator or " › ") .. "%#OwnCrumb#"
  local parts = {}
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then return "" end
  local ok, icons = pcall(require, "mini.icons")
  if opts.path ~= false then
    local rel = vim.fn.fnamemodify(path, ":~:.")
    local dirs = vim.split(vim.fs.dirname(rel), "/", { trimempty = true })
    local depth = opts.max_depth or 3
    if #dirs > depth then dirs = vim.list_extend({ "…" }, vim.list_slice(dirs, #dirs - depth + 1, #dirs)) end
    for _, d in ipairs(dirs) do
      if d ~= "." then parts[#parts + 1] = esc(d) end
    end
  end
  local file = esc(vim.fn.fnamemodify(path, ":t"))
  if ok then
    local glyph, group = icons.get("file", path)
    file = "%#" .. group .. "#" .. glyph .. " %#OwnCrumbFile#" .. file .. "%#OwnCrumb#"
  end
  parts[#parts + 1] = file
  if opts.symbols ~= false then
    for _, s in ipairs(symbols(win, buf)) do
      local glyph, group = "", "OwnCrumb"
      if ok then glyph, group = icons.get("lsp", s.kind) end
      parts[#parts + 1] = "%#" .. group .. "#" .. glyph .. " %#OwnCrumb#" .. esc(s.name)
    end
  end
  return "%#OwnCrumb# " .. table.concat(parts, sep)
end

local function define()
  local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end
  local bg = c("Normal", "bg")
  vim.api.nvim_set_hl(0, "OwnCrumb", { fg = c("Comment"), bg = bg })
  vim.api.nvim_set_hl(0, "OwnCrumbFile", { fg = c("Normal"), bg = bg, bold = true })
  vim.api.nvim_set_hl(0, "OwnCrumbSep", { fg = c("NonText") or c("Comment"), bg = bg })
end

local WINBAR = "%{%v:lua.require'own.modules.breadcrumbs'.render()%}"

local function attach(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local cfg = vim.api.nvim_win_get_config(win)
  local normal = cfg.relative == "" and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
  if normal and vim.wo[win].winbar == "" then
    vim.wo[win].winbar = WINBAR
  elseif not normal and vim.wo[win].winbar == WINBAR then
    vim.wo[win].winbar = ""
  end
end

function M.setup()
  define()
  local group = vim.api.nvim_create_augroup("own.breadcrumbs", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define })
  -- курсор ушёл в другую функцию — крошки поменялись (не чаще раза в 100 мс)
  local pending = false
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if pending then return end
      pending = true
      vim.defer_fn(function() pending = false; vim.cmd("redrawstatus") end, 100)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "BufFilePost", "FileType" }, {
    group = group,
    callback = function() attach(vim.api.nvim_get_current_win()) end,
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do attach(win) end
end

function M.reload() vim.cmd("redraw!") end

return M
