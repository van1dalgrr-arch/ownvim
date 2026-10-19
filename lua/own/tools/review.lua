-- Ревью от Claude прямо в коде: пробел a R — Claude читает diff ветки против main (и незакоммиченное),
-- замечания встают на свои строки, как ошибки линтера (плашка справа), и списком — пробел x x.
-- Пока Claude думает (полминуты–минута), работать можно дальше. Убрать замечания — пробел a X.
local M = {}
local ns = vim.api.nvim_create_namespace("own.review")

local function git(root, args)
  local r = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
  return r.code == 0 and vim.trim(r.stdout) or ""
end

local prompt = [[
Ты — внимательный ревьюер кода. Ниже diff ветки. Найди настоящие проблемы: баги, гонки, утечки
горутин и ресурсов, необработанные ошибки, проблемы безопасности, неверную логику, пропущенные
проверки. Стиль и мелочи — только если они реально мешают. Не хвали и не пересказывай diff.

Ответ — только строки такого вида, по одной на замечание, не больше 15:
путь/к/файлу.go:НОМЕР_СТРОКИ: error|warn|info: коротко, что не так и как исправить
Номер строки — в НОВОЙ версии файла (после изменений). Если проблем нет — одна строка: NONE]]

local sev = { error = vim.diagnostic.severity.ERROR, warn = vim.diagnostic.severity.WARN, info = vim.diagnostic.severity.INFO }

function M.clear()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do vim.diagnostic.reset(ns, b) end
end

-- diff ветки против main + то, что ещё не закоммичено: ревью того, что уйдёт в PR
local function branch_diff(root)
  local base = git(root, { "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
  base = base ~= "" and base or "main"
  local mb = git(root, { "merge-base", base, "HEAD" })
  return git(root, { "diff", mb ~= "" and mb or base }), base
end

-- ответ Claude → { file (абсолютный), lnum, level, msg }
local function parse(stdout, root)
  local items = {}
  for line in (stdout or ""):gmatch("[^\n]+") do
    local path, lnum, level, msg = line:match("^%s*`?([^:`]+):(%d+):%s*(%a+):%s*(.+)$")
    if path and sev[level] then
      items[#items + 1] = { file = vim.fs.joinpath(root, path), lnum = tonumber(lnum), level = level, msg = msg }
    end
  end
  return items
end

function M.run()
  if vim.fn.executable("claude") == 0 then return vim.notify("нужен Claude Code: команда claude", vim.log.levels.ERROR) end
  local root = require("own.root").git()
  local diff, base = branch_diff(root)
  if diff == "" then return vim.notify("нет изменений относительно " .. base, vim.log.levels.WARN) end
  vim.notify("Claude смотрит diff против " .. base .. "…", vim.log.levels.INFO, { title = "ревью" })
  vim.system({ "claude", "-p", prompt }, { stdin = diff:sub(1, 150000), text = true, cwd = root }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return vim.notify("claude: " .. (res.stderr or ""), vim.log.levels.ERROR, { title = "ревью" })
    end
    M.clear()
    local by_buf, qf = {}, {}
    for _, it in ipairs(parse(res.stdout, root)) do
      local buf = vim.fn.bufadd(it.file)
      by_buf[buf] = by_buf[buf] or {}
      table.insert(by_buf[buf], { lnum = it.lnum - 1, col = 0, severity = sev[it.level], source = "claude", message = it.msg })
      table.insert(qf, { filename = it.file, lnum = it.lnum, text = "claude: " .. it.msg, type = it.level:sub(1, 1):upper() })
    end
    if #qf == 0 then
      local none = (res.stdout or ""):match("NONE")
      return vim.notify(none and "Claude проблем не нашёл ✓" or ("не понял ответ Claude:\n" .. (res.stdout or "")), vim.log.levels.INFO, { title = "ревью" })
    end
    for buf, diags in pairs(by_buf) do vim.diagnostic.set(ns, buf, diags) end
    vim.fn.setqflist({}, " ", { title = "Ревью Claude", items = qf })
    vim.notify(("замечаний: %d — на строках в коде, списком: пробел x q"):format(#qf), vim.log.levels.WARN, { title = "ревью" })
  end))
end

-- Для Rune (bin/rune-ide review <папка>): замечания строками путь:строка:1: уровень: текст — для locationpicker
function M.cli(dir)
  local root = git(dir, { "rev-parse", "--show-toplevel" })
  if root == "" then root = dir end
  local diff, base = branch_diff(root)
  if diff == "" then io.stdout:write("нет изменений относительно " .. base .. "\n"); return 0 end
  local res = vim.system({ "claude", "-p", prompt }, { stdin = diff:sub(1, 150000), text = true, cwd = root }):wait()
  if res.code ~= 0 then io.stderr:write("claude: " .. (res.stderr or "") .. "\n"); return 1 end
  local items = parse(res.stdout, root)
  for _, it in ipairs(items) do io.stdout:write(("%s:%d:1: %s: %s\n"):format(it.file, it.lnum, it.level, it.msg)) end
  if #items == 0 then io.stdout:write((res.stdout or ""):match("NONE") and "Claude проблем не нашёл ✓\n" or res.stdout) end
  return 0
end

return M
