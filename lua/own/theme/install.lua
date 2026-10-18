-- :ThemeInstall — тема из VS Code в ownvim:
--   :ThemeInstall dracula-theme.theme-dracula   — расширение по id (как в VS Code: издатель.имя) с Open VSX,
--                                                 если там нет — с Visual Studio Marketplace
--   :ThemeInstall https://…/theme.vsix | .json  — по ссылке; или путь к .vsix / .json на диске
-- Каждая тема из расширения конвертируется (lua/own/theme/vscode.lua) в themes/<имя>.json — дальше это
-- обычная тема ownvim: alt-s, :ThemeEdit, правки в "colors".
local jsonc = require("own.jsonc")
local vscode = require("own.theme.vscode")
local engine = require("own.theme")

local M = {}

local function notify(msg, level) vim.schedule(function() vim.notify(msg, level) end) end

local function slug(s) return (s:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")) end

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- curl → файл; done(ok, err)
local function download(url, out, done)
  vim.system({ "curl", "-fsSL", "--compressed", "-o", out, url }, {}, function(r)
    -- дальше — vim.fn и буферы: только из основного цикла
    vim.schedule(function() done(r.code == 0, vim.trim(r.stderr or "")) end)
  end)
end

-- тема VS Code с include (базовая тема в том же расширении): colors и tokenColors складываются
local function load_vscode(path, seen)
  seen = seen or {}
  if seen[path] then return {} end
  seen[path] = true
  local t, err = jsonc.decode(read(path) or "")
  if not t then return nil, ("%s: %s"):format(vim.fn.fnamemodify(path, ":t"), err.message) end
  if t.include then
    local base = load_vscode(vim.fs.normalize(vim.fs.dirname(path) .. "/" .. t.include), seen) or {}
    t.colors = vim.tbl_extend("force", base.colors or {}, t.colors or {})
    t.tokenColors = vim.list_extend(vim.deepcopy(base.tokenColors or {}), t.tokenColors or {})
    t.semanticTokenColors = vim.tbl_extend("force", base.semanticTokenColors or {}, t.semanticTokenColors or {})
  end
  return t
end

-- записать сконвертированную тему; вернуть имя
local function save(theme, label, source)
  local name = slug(label)
  local body = vim.json.encode(theme)
  -- json для человека: с отступами (jq есть почти везде; нет — одной строкой, тоже работает)
  local pretty = vim.fn.executable("jq") == 1 and vim.fn.system({ "jq", "." }, body) or body
  local f = assert(io.open(engine.dir .. "/" .. name .. ".json", "w"))
  f:write(("// %s — из VS Code (%s), сконвертирована :ThemeInstall. Править можно как свою.\n"):format(label, source))
  f:write(pretty)
  f:close()
  return name
end

-- готовые темы → поставить первую (или выбрать), записать в settings.jsonc
local function finish(names)
  vim.schedule(function()
    engine.sync_shims()
    if #names == 0 then return vim.notify("тем в расширении не нашлось", vim.log.levels.WARN) end
    local function use(name)
      local s = require("own.settings")
      local cur = (s.current or {}).theme
      if type(cur) == "table" then
        cur = vim.deepcopy(cur)
        cur[vim.o.background] = name
      else
        cur = name
      end
      s.set("theme", cur)
      vim.cmd.colorscheme(name)
      vim.notify(("тема %s поставлена и записана в settings.jsonc"):format(name))
    end
    if #names == 1 then return use(names[1]) end
    vim.ui.select(names, { prompt = ("Поставлено %d тем — какую включить?"):format(#names) }, function(choice)
      if choice then use(choice) else vim.notify("темы поставлены: " .. table.concat(names, ", ") .. " — alt-s") end
    end)
  end)
end

local function from_vsix(vsix, source)
  local dir = vim.fn.tempname()
  vim.system({ "unzip", "-q", "-o", vsix, "-d", dir }, {}, function(r)
    if r.code ~= 0 then return notify("не распаковалось: " .. (r.stderr or ""), vim.log.levels.ERROR) end
    vim.schedule(function()
      local root = dir .. "/extension"
      local pkg = jsonc.decode(read(root .. "/package.json") or "") or {}
      local themes = ((pkg.contributes or {}).themes) or {}
      local names = {}
      for _, th in ipairs(themes) do
        local path = vim.fs.normalize(root .. "/" .. th.path)
        if path:match("%.json$") then
          local t, err = load_vscode(path)
          if t then
            local kind = (th.uiTheme == "vs" or th.uiTheme == "hc-light") and "light" or "dark"
            local label = th.label or th.id or vim.fn.fnamemodify(path, ":t:r")
            names[#names + 1] = save(vscode.convert(t, label, kind), label, source)
          else
            vim.notify("пропустил: " .. err, vim.log.levels.WARN)
          end
        else
          vim.notify(("пропустил %s: формат .tmTheme не поддерживается"):format(th.label or th.path), vim.log.levels.WARN)
        end
      end
      finish(names)
    end)
  end)
end

local function from_json(path, source)
  vim.schedule(function()
    local t, err = load_vscode(path)
    if not t then return vim.notify(err, vim.log.levels.ERROR) end
    local label = t.name or vim.fn.fnamemodify(source, ":t:r")
    finish({ save(vscode.convert(t, label, t.type), label, source) })
  end)
end

function M.install(arg)
  if not arg or arg == "" then
    return vim.notify("ThemeInstall <издатель.расширение | ссылка на .vsix/.json | путь>", vim.log.levels.WARN)
  end
  vim.fn.mkdir(engine.dir, "p")
  local local_path = vim.fn.expand(arg)
  if vim.uv.fs_stat(local_path) then
    return local_path:match("%.vsix$") and from_vsix(local_path, arg) or from_json(local_path, arg)
  end
  local tmp = vim.fn.tempname()
  if arg:match("^https?://") then
    vim.notify("качаю " .. arg .. "…")
    return download(arg, tmp, function(ok, err)
      if not ok then return notify("не скачалось: " .. err, vim.log.levels.ERROR) end
      if arg:match("%.json") then from_json(tmp, arg) else from_vsix(tmp, arg) end
    end)
  end
  local publisher, name = arg:match("^([%w%-_]+)%.([%w%-_%.]+)$")
  if not publisher then return vim.notify("ждал id расширения вида издатель.имя", vim.log.levels.ERROR) end
  vim.notify(("ищу %s на Open VSX…"):format(arg))
  local meta = vim.fn.tempname()
  download(("https://open-vsx.org/api/%s/%s"):format(publisher, name), meta, function(ok)
    local url
    if ok then
      local info = vim.json.decode(read(meta) or "{}", { luanil = { object = true } }) or {}
      url = info.files and info.files.download
    end
    local source = "Open VSX"
    if not url then
      source = "VS Marketplace"
      url = ("https://marketplace.visualstudio.com/_apis/public/gallery/publishers/%s/vsextensions/%s/latest/vspackage")
        :format(publisher, name)
      notify("на Open VSX нет — качаю с VS Marketplace…")
    end
    download(url, tmp, function(ok2, err)
      if not ok2 then return notify(("%s не скачалось (%s): %s"):format(arg, source, err), vim.log.levels.ERROR) end
      from_vsix(tmp, arg .. ", " .. source)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("ThemeInstall", function(a) M.install(a.args) end, {
    nargs = 1,
    complete = "file",
    desc = "Тема из VS Code: id расширения, ссылка или файл",
  })
end

return M
