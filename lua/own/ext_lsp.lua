-- Go-расширения как языковой сервер «ownvim» внутри редактора (без отдельного процесса): их дополнение — в обычном
-- меню, описание — по K, исправления — в пробел ca, рядом с gopls и rust-analyzer. Подключается к файлам тех типов,
-- для которых в расширениях есть провайдеры (sdk.Completion, sdk.Hover, sdk.CodeActions); ответы — из Go через мост.
local M = {}

local core = require("own.core")
local providers = {} -- из манифеста

local function for_buf(buf, kind)
  local ft = vim.bo[buf].filetype
  local ext = require("own.ext")
  local out = {}
  for _, p in ipairs(providers) do
    if p.kind == kind and not ext.disabled(p.ext) and (vim.tbl_contains(p.filetypes, ft) or vim.tbl_contains(p.filetypes, "*")) then
      out[#out + 1] = p
    end
  end
  return out
end

local function ask(method, ...)
  local ok, res = pcall(core.request, method, ...)
  if not ok then
    vim.schedule(function() vim.notify("Go-расширения: " .. tostring(res), vim.log.levels.WARN) end)
    return nil
  end
  return res
end

local function triggers()
  local seen, out = {}, {}
  for _, p in ipairs(providers) do
    for _, t in ipairs(p.triggers or {}) do
      if not seen[t] then seen[t] = true; out[#out + 1] = t end
    end
  end
  return out
end

local function server(dispatchers)
  local closing, seq = false, 0
  local handlers = {}

  handlers["initialize"] = function()
    return {
      serverInfo = { name = "ownvim" },
      capabilities = {
        positionEncoding = "utf-8",
        completionProvider = { triggerCharacters = triggers() },
        hoverProvider = true,
        codeActionProvider = true,
        executeCommandProvider = { commands = { "ownvim.ext" } },
        textDocumentSync = { openClose = true, change = 2 },
      },
    }
  end

  handlers["textDocument/completion"] = function(params)
    local buf = vim.uri_to_bufnr(params.textDocument.uri)
    local pos = params.position
    local line = vim.api.nvim_buf_get_lines(buf, pos.line, pos.line + 1, false)[1] or ""
    local prefix = line:sub(1, pos.character):match("[%w_]*$") or ""
    local items = {}
    for _, p in ipairs(for_buf(buf, "completion")) do
      local ctx = require("own.ext").context_at(p.ext, buf, pos.line + 1, pos.character + 1)
      for _, it in ipairs(ask("ext.complete", p.id, ctx, prefix) or {}) do items[#items + 1] = it end
    end
    return { isIncomplete = false, items = items }
  end

  handlers["textDocument/hover"] = function(params)
    local buf = vim.uri_to_bufnr(params.textDocument.uri)
    local texts = {}
    for _, p in ipairs(for_buf(buf, "hover")) do
      local ctx = require("own.ext").context_at(p.ext, buf, params.position.line + 1, params.position.character + 1)
      local t = ask("ext.hover", p.id, ctx)
      if type(t) == "string" and t ~= "" then texts[#texts + 1] = t end
    end
    if #texts == 0 then return vim.NIL end
    return { contents = { kind = "markdown", value = table.concat(texts, "\n\n---\n\n") } }
  end

  handlers["textDocument/codeAction"] = function(params)
    local buf = vim.uri_to_bufnr(params.textDocument.uri)
    local r = params.range
    local out = {}
    for _, p in ipairs(for_buf(buf, "actions")) do
      local ctx = require("own.ext").context_at(p.ext, buf, r.start.line + 1, r.start.character + 1)
      if r["end"].line > r.start.line then ctx.sel_start, ctx.sel_end = r.start.line + 1, r["end"].line + 1 end
      for _, a in ipairs(ask("ext.actions", p.id, ctx) or {}) do
        out[#out + 1] = { title = a.title, kind = a.kind,
          command = { title = a.title, command = "ownvim.ext", arguments = { a.id, ctx } } }
      end
    end
    return out
  end

  handlers["workspace/executeCommand"] = function(params)
    if params.command == "ownvim.ext" then
      local args = params.arguments or {}
      require("own.ext").dispatch(args[1], args[2])
    end
    return vim.NIL
  end

  handlers["shutdown"] = function() return vim.NIL end

  return {
    request = function(method, params, callback)
      seq = seq + 1
      local h = handlers[method]
      if not h then
        callback({ code = -32601, message = "ownvim: " .. method .. " не поддерживается" })
      else
        local ok, res = pcall(h, params)
        if ok then callback(nil, res) else callback({ code = -32603, message = tostring(res) }) end
      end
      return true, seq
    end,
    notify = function(method)
      if method == "exit" then dispatchers.on_exit(0, 15) end
    end,
    is_closing = function() return closing end,
    terminate = function() closing = true end,
  }
end

local function attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local any = #for_buf(buf, "completion") + #for_buf(buf, "hover") + #for_buf(buf, "actions") > 0
  if not any then return end
  vim.lsp.start({ name = "ownvim", cmd = server, root_dir = require("own.root").get() }, { bufnr = buf })
end

--- Новый манифест (пересобрали ядро): перезапустить «сервер» с новыми провайдерами
function M.refresh(manifest)
  providers = manifest.providers or {}
  for _, c in ipairs(vim.lsp.get_clients({ name = "ownvim" })) do c:stop(true) end
  vim.schedule(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then attach(buf) end
    end
  end)
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("own.ext_lsp", { clear = true }),
    callback = function(ev) attach(ev.buf) end,
  })
end

return M
