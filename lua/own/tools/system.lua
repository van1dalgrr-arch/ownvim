-- Связь nvim с остальной системой: база проекта (dadbod), контейнеры (orbstack), dot.
local M = {}
local function root() return require("own.root").get() end

-- База проекта для dadbod (пробел D): как команда `db` — DATABASE_URL из .env,
-- иначе postgres://postgres:<DB_PASSWORD>@localhost:5432/<папка проекта>
function M.project_db()
  local dir = root()
  local env = {}
  local f = io.open(dir .. "/.env")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then env[k] = v:gsub('^"(.*)"$', "%1") end
    end
    f:close()
  end
  local url = env.DATABASE_URL
  if not url and (env.DB_PASSWORD or vim.uv.fs_stat(dir .. "/go.mod")) then
    url = ("postgres://postgres:%s@localhost:5432/%s?sslmode=disable"):format(env.DB_PASSWORD or "postgres", vim.fn.fnamemodify(dir, ":t"))
  end
  if url then vim.g.dbs = { [vim.fn.fnamemodify(dir, ":t")] = url } end
end

-- ◆ kinoza-back 1ч12м — режим dot work, как в промпте (читается файл, без процессов)
local work = { mtime = -1, text = "" }
function M.work_status()
  local path = vim.fn.expand("~/.config/dotfiles/work")
  local st = vim.uv.fs_stat(path)
  if not st then return "" end
  if st.mtime.sec ~= work.mtime then
    local lines = vim.fn.readfile(path)
    work = { mtime = st.mtime.sec, name = lines[1] or "", start = tonumber(lines[2] or "") or os.time() }
  end
  local s = os.time() - work.start
  local age = s >= 3600 and ("%dч%dм"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) or ("%dм"):format(math.floor(s / 60))
  return "◆ " .. work.name .. " " .. age
end

-- команда dot в плавающем терминале (закрыть — q или esc, как lazygit)
function M.dot(args)
  return function() Snacks.terminal("dot " .. args, { cwd = root(), interactive = false, win = { position = "float" } }) end
end

-- orbstack — своя панель контейнеров (berth): таблица, логи, события, всё на клавишах
-- то же нажатие внутри окна закрывает его: toggle, а в окне клавиша работает и в режиме терминала
function M.containers()
  Snacks.terminal.toggle("orbstack", {
    cwd = root(),
    win = { position = "float", width = 0.9, height = 0.85, border = "rounded",
      keys = { hide = { "<M-o>", "hide", mode = { "n", "t" } } } },
  })
end

-- gw (github-watcher) — PR, Actions, логи CI проекта; alt-w в окне прячет его, gw продолжает работать
function M.gw()
  Snacks.terminal.toggle("gw", {
    cwd = root(),
    win = { position = "float", width = 0.9, height = 0.85, border = "rounded",
      keys = { hide = { "<M-w>", "hide", mode = { "n", "t" } }, hide_ru = { "<M-ц>", "hide", mode = { "n", "t" } } } },
  })
end

return M
