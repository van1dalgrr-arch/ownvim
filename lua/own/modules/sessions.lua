-- Сессии проектов, как в VS Code: закрыл ownvim в проекте — открыл там же без файлов — вернулись вкладки,
-- разбиения и места курсора. Сессия своя у каждой папки. Раздел "sessions":
--   "auto_save": true — сохранять при выходе; "auto_restore": true — восстанавливать, если ownvim открыт без файлов
--   "ignore": ["~", "/tmp"] — папки, где сессии не нужны
-- пробел q s — вернуть сессию папки, пробел q S — выбрать из всех, пробел q d — не сохранять эту.
local settings = require("own.settings")

local M = {}

local DIR = vim.fn.stdpath("state") .. "/sessions/"
local skip_save = false

local function o() return (settings.current or {}).sessions or {} end

local function file_for(dir)
  return DIR .. (dir or vim.uv.cwd()):gsub("[/\\:]", "%%") .. ".vim"
end

local function ignored(dir)
  for _, p in ipairs(o().ignore or { "~", "/tmp", "/" }) do
    if vim.fs.normalize(vim.fn.expand(p)) == vim.fs.normalize(dir) then return true end
  end
  return false
end

-- есть ли что сохранять: хоть один обычный файл
local function has_files()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then return true end
  end
  return false
end

function M.save()
  local dir = vim.uv.cwd()
  if skip_save or ignored(dir) or not has_files() then return end
  vim.fn.mkdir(DIR, "p")
  local saved = vim.o.sessionoptions
  vim.o.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,skiprtp"
  pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(file_for(dir)))
  vim.o.sessionoptions = saved
end

function M.load(file)
  file = file or file_for()
  if not vim.uv.fs_stat(file) then return vim.notify("для этой папки сессии нет", vim.log.levels.WARN) end
  -- служебные окна (дерево, терминал, Claude) в сессии не нужны — закрыть до загрузки
  pcall(vim.cmd, "silent! %bwipeout!")
  vim.cmd("silent! source " .. vim.fn.fnameescape(file))
end

function M.pick()
  local items = {}
  for name in vim.fs.dir(DIR) do
    if name:match("%.vim$") then
      local dir = name:gsub("%.vim$", ""):gsub("%%", "/")
      items[#items + 1] = { text = vim.fn.fnamemodify(dir, ":~"), file = DIR .. name, dir = dir }
    end
  end
  vim.ui.select(items, { prompt = "Сессия", format_item = function(i) return i.text end }, function(i)
    if not i then return end
    vim.cmd.cd(vim.fn.fnameescape(i.dir))
    M.load(i.file)
  end)
end

function M.stop()
  skip_save = true
  vim.notify("сессия этой папки при выходе не сохранится")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.sessions", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() if o().auto_save ~= false then M.save() end end,
  })
  -- открыл ownvim без файлов (и не из stdin) — вернуть сессию папки, если она есть
  if o().auto_restore ~= false and vim.fn.argc(-1) == 0 then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      nested = true,
      once = true,
      callback = function()
        if vim.g.own_stdin or ignored(vim.uv.cwd()) or not vim.uv.fs_stat(file_for()) then return end
        M.load()
      end,
    })
    vim.api.nvim_create_autocmd("StdinReadPre", { group = group, callback = function() vim.g.own_stdin = true end })
  end
end

return M
