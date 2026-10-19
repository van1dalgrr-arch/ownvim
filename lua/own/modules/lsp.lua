-- Языковые серверы: ошибки на строках, переход к определению, ссылки, переименование, подсказки типов.
-- Всё — из settings.jsonc:
--   "lsp": { "servers": { "gopls": { "settings": {…} }, "rust_analyzer": true, "basedpyright": false } }
--     true — с настройками по умолчанию (из nvim-lspconfig), объект — свои (cmd, filetypes, settings,
--     init_options, root_markers… — как vim.lsp.config), false — выключить
--   "diagnostics": { … } — как vim.diagnostic.config: virtual_text, signs, underline, float…
--   "tools": { "install": "mason" } — недостающие серверы ставятся сами; "system" — только из PATH (brew)
-- Сохранил settings.jsonc — серверы включились/выключились, новые settings ушли в работающие серверы.
local settings = require("own.settings")
local tools = require("own.tools")

local M = {}

local enabled = {} -- имя сервера → true, что включили в прошлый раз

local function current() return settings.current or {} end
local function lsp_opts() return current().lsp or {} end

-- "error"/"WARN" → vim.diagnostic.severity.ERROR в любом месте настроек ошибок
local function severities(v, key)
  if type(v) == "string" and (key == "severity" or key == "min" or key == "max") then
    return vim.diagnostic.severity[v:upper()] or v
  end
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do
    local nk = k
    if key == "text" or key == "numhl" or key == "linehl" then nk = vim.diagnostic.severity[tostring(k):upper()] or k end
    out[nk] = severities(x, k)
  end
  return out
end

local function apply_diagnostics()
  local d = severities(vim.deepcopy(current().diagnostics or {}))
  -- Error Lens рисует текст ошибок сам — встроенный не нужен, иначе каждая ошибка дважды
  if settings.enabled(current(), "error_lens") then d.virtual_text = false end
  vim.diagnostic.config(d)
end

local function executable(name)
  local cmd = vim.lsp.config[name] and vim.lsp.config[name].cmd
  if type(cmd) ~= "table" then return true end -- cmd-функция (подключение по сети и т.п.) — не проверить
  return vim.fn.executable(cmd[1]) == 1, cmd[1]
end

-- настроить и включить серверы из lsp.servers; выключить пропавшие
local function configure()
  local want = {}
  for name, v in pairs(lsp_opts().servers or {}) do
    if v ~= false and not (type(v) == "table" and v.enabled == false) then
      local cfg = type(v) == "table" and vim.deepcopy(v) or {}
      local install_name = cfg.install
      cfg.install, cfg.enabled = nil, nil
      -- присваивание (а не вызов) заменяет прошлые свои настройки целиком: удалил ключ — он ушёл
      vim.lsp.config[name] = cfg
      want[name] = true
      local ok, bin = executable(name)
      -- реестр mason читается, только если сервера нет (на старте он не нужен — экономит ~6 мс)
      local pkg = not ok and (install_name or (tools.mason() and tools.package_for_lsp(name)))
      if ok then
        vim.lsp.enable(name)
      elseif pkg then
        tools.install(pkg, name, function() vim.lsp.enable(name) end)
      else
        tools.ensure_bin(bin, name, function() vim.lsp.enable(name) end,
          name == "rust_analyzer" and "rust-analyzer берётся из rustup: brew install rustup && rustup-init" or nil)
      end
    end
  end
  for name in pairs(enabled) do
    if not want[name] then vim.lsp.enable(name, false) end
  end
  enabled = want
  -- работающим серверам — новые settings без перезапуска
  for _, client in ipairs(vim.lsp.get_clients()) do
    local cfg = want[client.name] and vim.lsp.config[client.name]
    if cfg and cfg.settings and not vim.deep_equal(cfg.settings, client.settings) then
      client.settings = cfg.settings
      client:notify("workspace/didChangeConfiguration", { settings = cfg.settings })
    end
  end
end

local function on_attach(client, buf)
  local o = lsp_opts()
  local hints = o.inlay_hints or {}
  if hints.enabled ~= false and client:supports_method("textDocument/inlayHint")
    and not vim.tbl_contains(hints.exclude or {}, vim.bo[buf].filetype) then
    vim.lsp.inlay_hint.enable(true, { bufnr = buf })
  end
  if o.codelens and client:supports_method("textDocument/codeLens") then
    vim.lsp.codelens.enable(true, { bufnr = buf })
  end
end

function M.plugins()
  local list = {
    -- только данные: lsp/<сервер>.lua с cmd, filetypes и корнем проекта для сотен серверов
    { "neovim/nvim-lspconfig", lazy = false },
  }
  if tools.mason() then
    list[#list + 1] = {
      "mason-org/mason.nvim",
      -- грузится, когда что-то ставится или открыт :Mason; PATH к его программам — own.tools.add_path()
      lazy = true,
      cmd = "Mason",
      opts = { ui = { border = "rounded" } },
    }
  end
  return list
end

function M.setup()
  tools.add_path()
  apply_diagnostics()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("own.lsp", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client then on_attach(client, ev.buf) end
    end,
  })
  configure()
end

function M.reload()
  apply_diagnostics()
  configure()
end

return M
