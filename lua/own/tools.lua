-- Программы для серверов, форматтеров и линтеров: есть в PATH — берём, нет — ставит mason
-- (если "tools": { "install": "mason" }), иначе — замечание в settings.jsonc, что поставить.
local settings = require("own.settings")

local M = {}

function M.mason() return ((settings.current or {}).tools or {}).install ~= "system" end

--- Папка программ mason — в PATH сразу, без загрузки самого mason (он тянет реестр — ~6 мс на старте)
function M.add_path()
  if not M.mason() then return end
  local bin = vim.fn.stdpath("data") .. "/mason/bin"
  if not (vim.env.PATH or ""):find(bin, 1, true) then vim.env.PATH = bin .. ":" .. vim.env.PATH end
end

-- реестр mason: пакет по имени сервера (neovim.lspconfig) и по программе (bin)
local by_lsp, by_bin
local function index()
  if by_lsp then return end
  by_lsp, by_bin = {}, {}
  for _, spec in ipairs(require("mason-registry").get_all_package_specs()) do
    local l = spec.neovim and spec.neovim.lspconfig
    if l then by_lsp[l] = spec.name end
    for bin in pairs(spec.bin or {}) do by_bin[bin] = by_bin[bin] or spec.name end
  end
end

function M.package_for_lsp(name) index(); return by_lsp[name] end
function M.package_for_bin(bin) index(); return by_bin[bin] end

local waiting = {} -- пакет → { колбэки }, пока ставится

--- Поставить пакет mason; done() — когда готов (сразу, если уже стоит)
function M.install(pkg_name, label, done)
  local registry = require("mason-registry")
  registry.refresh(function()
    if not registry.has_package(pkg_name) then
      return settings.warn(label, ("в mason нет пакета %q — поставь сам или задай имя пакета"):format(pkg_name))
    end
    local pkg = registry.get_package(pkg_name)
    if pkg:is_installed() then return vim.schedule(done) end
    if waiting[pkg_name] then return table.insert(waiting[pkg_name], done) end
    waiting[pkg_name] = { done }
    vim.notify(("ставлю %s (%s)…"):format(label, pkg_name))
    pkg:install({}, function(ok, err)
      local cbs = waiting[pkg_name]
      waiting[pkg_name] = nil
      vim.schedule(function()
        if not ok then return vim.notify(("%s не поставился: %s"):format(label, tostring(err)), vim.log.levels.ERROR) end
        vim.notify(label .. " поставлен")
        for _, cb in ipairs(cbs) do cb() end
      end)
    end)
  end)
end

--- Нужна программа bin (для label в настройках). Есть — done() сразу; нет — mason или замечание.
--- hint — что сказать, если взять неоткуда (например, «поставь rustup»); key — где в настройках подсветить (по умолчанию label)
function M.ensure_bin(bin, label, done, hint, key)
  done = done or function() end
  if vim.fn.executable(bin) == 1 then return done() end
  local pkg = M.mason() and M.package_for_bin(bin)
  if pkg then return M.install(pkg, label, done) end
  settings.warn(key or label, hint or (M.mason() and ("нет программы %q ни в PATH, ни в mason — поставь её"):format(bin)
    or ("нет программы %q в PATH — поставь её или \"tools\": { \"install\": \"mason\" }"):format(bin)))
end

return M
