-- Подключение к базе проекта — одно на всех: dadbod (пробел D), сервер SQL (дополнение по таблицам), миграции.
--   1. DATABASE_URL из .env в корне проекта
--   2. сервис postgres из compose-файла: POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB (${VAR} — из .env)
--      и опубликованный порт («5433:5432» → localhost:5433)
--   3. есть DB_PASSWORD или go.mod — postgres://postgres:<DB_PASSWORD>@localhost:5432/<папка проекта>
-- Локальная база (localhost) без sslmode — дописывается sslmode=disable: migrate без него не подключится.
local M = {}

local COMPOSE = { "compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml" }

local function env_of(dir) return require("own.modules.tasks").read_env(dir .. "/.env") end

local function subst(v, env)
  return (v:gsub("%${([%w_]+)[^}]*}", function(k) return env[k] or vim.env[k] or "" end)
    :gsub("%$([%w_]+)", function(k) return env[k] or vim.env[k] or "" end))
end

local function unquote(v) return (vim.trim(v):gsub("^['\"](.*)['\"]$", "%1")) end

-- сервис postgres из compose-файла: { user, password, db, port }
local function from_compose(dir, env)
  for _, name in ipairs(COMPOSE) do
    local f = io.open(dir .. "/" .. name)
    if f then
      local lines = {}
      for l in f:lines() do lines[#lines + 1] = l end
      f:close()
      -- блоки сервисов: строка с отступом 2 и «имя:» — начало сервиса
      local svc, cur = {}, nil
      for _, l in ipairs(lines) do
        local ind = l:match("^(%s*)[%w_.-]+:%s*$")
        if ind and #ind == 2 then
          cur = { lines = {} }
          svc[#svc + 1] = cur
        elseif l:match("^%S") then
          cur = nil
        elseif cur then
          table.insert(cur.lines, l)
        end
      end
      for _, s in ipairs(svc) do
        local body = table.concat(s.lines, "\n")
        local image = body:match("image:%s*([^\n]+)") or ""
        if image:find("postgres") or image:find("postgis") or image:find("timescale") then
          local out = { port = "5432" }
          for _, l in ipairs(s.lines) do
            local k, v = l:match("^%s*%-?%s*(POSTGRES_[%u_]+)%s*[:=]%s*(.-)%s*$")
            if k then out[k] = subst(unquote(v), env) end
            local host = l:match("^%s*%-%s*['\"]?[%d.]*:?(%d+):5432")
            if host then out.port = host end
          end
          return out
        end
      end
    end
  end
end

local function local_ssl(url)
  if url:match("@localhost[:/]") or url:match("@127%.0%.0%.1[:/]") then
    if not url:find("sslmode=", 1, true) then url = url .. (url:find("?", 1, true) and "&" or "?") .. "sslmode=disable" end
  end
  return url
end

--- URL базы проекта в папке dir (по умолчанию — корень проекта) и имя подключения. nil — не нашлось
function M.project_url(dir)
  dir = dir or require("own.root").get()
  local name = vim.fn.fnamemodify(dir, ":t")
  local env = env_of(dir)
  if env.DATABASE_URL and env.DATABASE_URL ~= "" then return local_ssl(subst(env.DATABASE_URL, env)), name end
  local c = from_compose(dir, env)
  if c then
    local user = c.POSTGRES_USER ~= nil and c.POSTGRES_USER ~= "" and c.POSTGRES_USER or "postgres"
    local pass = c.POSTGRES_PASSWORD ~= nil and c.POSTGRES_PASSWORD ~= "" and c.POSTGRES_PASSWORD or env.DB_PASSWORD or "postgres"
    local db = c.POSTGRES_DB ~= nil and c.POSTGRES_DB ~= "" and c.POSTGRES_DB or user
    return ("postgres://%s:%s@localhost:%s/%s?sslmode=disable"):format(user, pass, c.port, db), name
  end
  if env.DB_PASSWORD or vim.uv.fs_stat(dir .. "/go.mod") then
    return ("postgres://postgres:%s@localhost:5432/%s?sslmode=disable"):format(env.DB_PASSWORD or "postgres", name), name
  end
end

return M
