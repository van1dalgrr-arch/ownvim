-- Эндпоинты Gin, как окно Endpoints в GoLand: все маршруты проекта с полным путём.
-- Разбор по строкам, без запуска кода: `x := y.Group("/p")` копит префиксы, `x.GET("/q", h)` — маршрут.
-- Группы и маршруты, объявленные в разных файлах, склеиваются, если переменная группы — в том же файле.
local M = {}

local methods = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true, HEAD = true, OPTIONS = true, Any = true }

-- маршруты одного файла: { method, path, handler, file, line, col (с 0, на имени хендлера) }
local function parse(file, out)
  local prefix = {} -- переменная группы → её полный префикс
  for i, line in ipairs(vim.fn.readfile(file)) do
    local var, parent, p = line:match("([%w_]+)%s*:?=%s*([%w_%.]+)%.Group%(%s*\"([^\"]*)\"")
    if var then
      prefix[var] = (prefix[parent] or "") .. p
    else
      local recv, method, path, rest = line:match("([%w_]+)%.(%u%a+)%(%s*\"([^\"]*)\"(.*)")
      if recv and methods[method] then
        -- хендлер — последний аргумент: userHandler.Register, h.List, func(c *gin.Context)…
        local handler = rest:match(",%s*([%w_%.]+)%(%)%)%s*$") -- logHandler.Create() — фабрика хендлера
          or rest:match(",%s*([%w_%.]+)%(.-%)%)%s*$") -- handler.Health(db)
          or rest:match(",%s*([%w_%.]+)%)%s*$") or rest:match(",%s*([%w_%.]+)%s*,?%s*$") or "func"
        local col = line:find(handler, 1, true)
        out[#out + 1] = {
          method = method:upper(),
          path = ((prefix[recv] or "") .. path):gsub("//+", "/"),
          handler = handler,
          file = file,
          line = i,
          col = col and (col - 1 + #handler - #(handler:match("[%w_]+$") or "")) or 0,
        }
      end
    end
  end
end

---@param root string
function M.collect(root)
  local files = vim.fn.systemlist({ "rg", "--files", "-g", "*.go", "-g", "!*_test.go", "-g", "!vendor/**", root })
  local out = {}
  for _, f in ipairs(files) do parse(f, out) end
  local order = { GET = 1, POST = 2, PUT = 3, PATCH = 4, DELETE = 5 }
  table.sort(out, function(a, b)
    if a.path ~= b.path then return a.path < b.path end
    return (order[a.method] or 9) < (order[b.method] or 9)
  end)
  return out
end


-- Запрос на запущенный API, ответ — в правой панели. Порт — PORT из .env или окружения, иначе 8080.
-- Токен: если ответ содержит access_token / accessToken / token, он запоминается и уходит
-- в Authorization: Bearer для следующих запросов (сбросить — :let g:api_token = v:null).
local bodies = {} -- последнее тело запроса для каждого маршрута

local function port(root)
  local f = io.open((root or require("own.root").get()) .. "/.env")
  if f then
    for line in f:lines() do
      local p = line:match("^%s*PORT%s*=%s*(%d+)")
      if p then f:close(); return p end
    end
    f:close()
  end
  return vim.env.PORT or "8080"
end

local function show(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "json"
  vim.bo[buf].bufhidden = "wipe"
  vim.cmd("botright vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, title .. " [" .. buf .. "]")
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "закрыть ответ" })
end

function M.send(r, body)
  local path = r.path:gsub(":([%w_]+)", "1"):gsub("%*[%w_]*", "")
  local url = "http://localhost:" .. port() .. path
  local cmd = { "curl", "-s", "-S", "--connect-timeout", "5", "--max-time", "30", "-X", r.method == "ANY" and "GET" or r.method, "-w", "\n@@%{http_code} %{time_total}", url }
  if vim.g.api_token then vim.list_extend(cmd, { "-H", "Authorization: Bearer " .. vim.g.api_token }) end
  if body and body ~= "" then vim.list_extend(cmd, { "-H", "Content-Type: application/json", "-d", body }) end
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return vim.notify((res.stderr or "") .. "\nAPI запущен? пробел r r → go run / up", vim.log.levels.ERROR, { title = url })
    end
    local out, status, secs = res.stdout:match("^(.*)\n@@(%d+) ([%d.]+)$")
    out = out or res.stdout
    local ok, decoded = pcall(vim.json.decode, out)
    if ok and type(decoded) == "table" then
      local tok = decoded.access_token or decoded.accessToken or decoded.token
        or (type(decoded.data) == "table" and (decoded.data.access_token or decoded.data.accessToken or decoded.data.token))
      if type(tok) == "string" then vim.g.api_token = tok; vim.notify("токен запомнен для следующих запросов") end
      local pretty = vim.fn.executable("jq") == 1 and vim.fn.systemlist({ "jq", "." }, out) or { out }
      out = table.concat(pretty, "\n")
    end
    local ms = (tonumber(secs) or 0) * 1000
    local head = ("// %s %s → %s · %s"):format(r.method, path, status or "?", ms < 1 and "<1 мс" or ("%d мс"):format(math.floor(ms)))
    show(vim.list_extend({ head }, vim.split(out, "\n")), r.method .. " " .. path)
  end))
end

local colors = { GET = "DiagnosticOk", POST = "DiagnosticWarn", PUT = "DiagnosticInfo", PATCH = "DiagnosticInfo", DELETE = "DiagnosticError" }

function M.pick()
  local root = require("own.root").get()
  local routes = M.collect(root)
  if #routes == 0 then
    return vim.notify("Маршрутов Gin не нашёл в " .. root, vim.log.levels.WARN)
  end
  local items = {}
  for _, r in ipairs(routes) do
    items[#items + 1] = {
      text = r.method .. " " .. r.path .. " " .. r.handler,
      file = r.file,
      pos = { r.line, r.col },
      route = r,
    }
  end
  Snacks.picker.pick({
    title = "Эндпоинты · enter — хендлер · ctrl-r — запрос · ctrl-y — curl",
    items = items,
    preview = "file",
    format = function(item)
      local r = item.route
      return {
        { ("%-7s"):format(r.method), colors[r.method] or "Special" },
        { r.path, "Title" },
        { "  → " .. r.handler, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      -- после закрытия списка: иначе текущим остаётся его окно, и gopls спрашивать не у кого
      vim.schedule(function()
        vim.cmd.edit(item.file)
        vim.api.nvim_win_set_cursor(0, item.pos)
        -- курсор на имени хендлера, дальше — к его определению через gopls.
        -- Только что открытый файл gopls подхватывает не сразу: тогда ждём, пока он подключится.
        local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
        local function jump(client)
          local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
          client:request("textDocument/definition", params, function(_, result)
            local loc = vim.islist(result) and result[1] or result
            if loc and vim.api.nvim_get_current_win() == win then
              vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true })
            end
          end, buf)
        end
        local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })[1]
        if client then return jump(client) end
        vim.api.nvim_create_autocmd("LspAttach", {
          buffer = buf,
          once = true,
          callback = function(ev)
            local c = vim.lsp.get_client_by_id(ev.data.client_id)
            if c and c:supports_method("textDocument/definition") then jump(c) end
          end,
        })
      end)
    end,
    actions = {
      send = function(picker, item)
        local r = item.route
        picker:close()
        if r.method == "GET" or r.method == "DELETE" or r.method == "HEAD" then return M.send(r) end
        vim.ui.input({ prompt = r.method .. " " .. r.path .. " · тело JSON: ", default = bodies[r.method .. r.path] or "{}" }, function(body)
          if body == nil then return end
          bodies[r.method .. r.path] = body
          M.send(r, body)
        end)
      end,
      curl = function(_, item)
        local r = item.route
        local path = r.path:gsub(":([%w_]+)", "1"):gsub("%*[%w_]*", "")
        local cmd = ("curl -s -X %s localhost:${PORT:-8080}%s | jq ."):format(r.method == "ANY" and "GET" or r.method, path)
        vim.fn.setreg("+", cmd)
        vim.notify(cmd, vim.log.levels.INFO, { title = "скопировано" })
      end,
    },
    win = { input = { keys = {
      ["<c-y>"] = { "curl", mode = { "n", "i" } },
      ["<c-r>"] = { "send", mode = { "n", "i" } },
    } } },
  })
end

-- api.http — Postman в файле: все маршруты проекта запросами (lua/dotfiles/http.lua, enter — отправить).
-- Логин получает имя login, остальные запросы берут из его ответа access_token в Authorization.
-- Готовый файл не перезаписывается: в нём твои тела запросов и правки.
function M.http_file(root, dest, no_open)
  root = root or require("own.root").get()
  dest = dest or (root .. "/api.http")
  if vim.uv.fs_stat(dest) then
    vim.notify("api.http уже есть — открываю (новый: удали файл и пробел r h)")
    return vim.cmd.edit(dest)
  end
  local routes = M.collect(root)
  if #routes == 0 then return vim.notify("Маршрутов Gin не нашёл в " .. root, vim.log.levels.WARN) end
  local login
  for _, r in ipairs(routes) do
    if r.method == "POST" and r.path:match("login$") then login = r end
  end
  local lines = {
    "# Как пользоваться: курсор на запрос → Enter — ответ справа, Esc — закрыть. Подробно: ~/dotfiles/docs/postman.ru.md",
    "# Сгенерировано из маршрутов (пробел r h); дальше файл твой — правь тела и параметры.",
    "@host = http://localhost:" .. port(root),
  }
  local function add(r)
    local path = r.path:gsub(":([%w_]+)", "1"):gsub("%*[%w_]*", "")
    vim.list_extend(lines, { "", "### " .. r.method .. " " .. r.path .. " → " .. r.handler })
    if r == login then lines[#lines + 1] = "# @name login" end
    lines[#lines + 1] = (r.method == "ANY" and "GET" or r.method) .. " {{host}}" .. path
    if login and r ~= login and not r.path:match("register$") and not r.path:match("refresh$") then
      lines[#lines + 1] = "Authorization: Bearer {{login.response.body.$.access_token}}"
    end
    if r.method == "POST" or r.method == "PUT" or r.method == "PATCH" then
      vim.list_extend(lines, { "Content-Type: application/json", "", "{}" })
    end
  end
  if login then add(login) end
  for _, r in ipairs(routes) do
    if r ~= login then add(r) end
  end
  vim.fn.writefile(lines, dest)
  if no_open then return dest end
  vim.cmd.edit(dest)
  vim.notify(("api.http: %d запросов"):format(#routes))
end

-- Для Rune (bin/rune-ide endpoints <корень>): маршруты строками путь:строка:колонка: МЕТОД /путь → хендлер
function M.cli(root)
  for _, r in ipairs(M.collect(root)) do
    io.stdout:write(("%s:%d:%d: %-6s %s → %s\n"):format(r.file, r.line, r.col + 1, r.method, r.path, r.handler))
  end
  return 0
end

return M
