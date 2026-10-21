-- Отладчик (nvim-dap + delve для Go): точки останова переживают перезапуск, панели переменных/стека
-- открываются сами, значения переменных — серым прямо в коде. Клавиши как в GoLand: F8 шаг, F7 внутрь,
-- shift-F8 наружу, F9 дальше, ctrl-F8 точка останова; пробел d … — всё остальное.
-- Раздел "debug" в settings.jsonc:
--   "ui": true — панели сами при старте/конце; "virtual_text": true — значения в коде
--   "signs": { "breakpoint": "●", … } — значки
--   "go": { "delve": "dlv", "configurations": [ … ] } — свои конфигурации запуска (как в nvim-dap-go),
--     по умолчанию — подключение к dlv в Docker на :2345
-- Всё — после :restart, кроме значков.
local settings = require("own.settings")
local tools = require("own.tools")

local M = {}

local function d() return (settings.current or {}).debug or {} end

local SIGNS = {
  breakpoint = { "DapBreakpoint", "DiagnosticError" },
  condition = { "DapBreakpointCondition", "DiagnosticWarn" },
  rejected = { "DapBreakpointRejected", "DiagnosticError" },
  log = { "DapLogPoint", "DiagnosticInfo" },
  stopped = { "DapStopped", "DiagnosticWarn", "DapStoppedLine" },
}

local function signs()
  vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })
  for key, s in pairs(SIGNS) do
    local text = (d().signs or {})[key]
    if text then vim.fn.sign_define(s[1], { text = text, texthl = s[2], linehl = s[3], numhl = s[3] }) end
  end
end

function M.plugins()
  local o = d()
  return {
    {
      "mfussenegger/nvim-dap",
      dependencies = {
        { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
        "theHamsta/nvim-dap-virtual-text",
        "leoluz/nvim-dap-go",
      },
      lazy = true,
      config = function()
        local dap = require("dap")
        signs()
        -- панели и значения в коде — при первом запуске отладки, а не при загрузке dap (точки останова тянут dap на старте)
        local ready = false
        local function prepare()
          if ready then return end
          ready = true
          if o.ui ~= false then require("dapui").setup(o.dapui or {}) end
          if o.virtual_text ~= false then require("nvim-dap-virtual-text").setup({}) end
        end
        dap.listeners.before.launch.own = prepare
        dap.listeners.before.attach.own = prepare
        if o.ui ~= false then
          dap.listeners.after.event_initialized.own = function() require("dapui").open({}) end
          dap.listeners.before.event_terminated.own = function() require("dapui").close({}) end
          dap.listeners.before.event_exited.own = function() require("dapui").close({}) end
        end
        -- C/C++/Rust: codelldb; в конфигурациях из JSON — "${prompt:…}" и "${pick_process}" вместо функций
        local cpp = o.cpp
        if cpp ~= false then
          dap.adapters.codelldb = {
            type = "server",
            port = "${port}",
            executable = { command = "codelldb", args = { "--port", "${port}" } },
          }
          local function resolve(v)
            if type(v) == "table" then
              local out = {}
              for k, x in pairs(v) do out[k] = resolve(x) end
              return out
            end
            if type(v) ~= "string" then return v end
            if v == "${pick_process}" then return require("dap.utils").pick_process end
            local text = v:match("^%${prompt:(.*)}$")
            if text then
              return function() return vim.fn.input(text, vim.fn.getcwd() .. "/build/", "file") end
            end
            return v
          end
          local confs = resolve((cpp or {}).configurations or {})
          for _, ft in ipairs({ "c", "cpp" }) do dap.configurations[ft] = confs end
          -- Rust: собрать через cargo и отладить — путь к бинарнику из вывода cargo (и в workspace), вводить не нужно
          local function cargo_program()
            vim.notify("cargo build…")
            local r = vim.system({ "cargo", "build", "--message-format=json" }, { cwd = require("own.root").get(), text = true }):wait()
            local exe
            for line in (r.stdout or ""):gmatch("[^\n]+") do
              local ok, m = pcall(vim.json.decode, line)
              if ok and type(m) == "table" and m.reason == "compiler-artifact" and type(m.executable) == "string" then exe = m.executable end
            end
            if r.code ~= 0 or not exe then
              vim.notify("cargo build не прошёл:\n" .. vim.trim(r.stderr or ""), vim.log.levels.ERROR)
              return dap.ABORT
            end
            return exe
          end
          dap.configurations.rust = vim.list_extend({
            { name = "Rust: собрать и отладить", type = "codelldb", request = "launch", program = cargo_program,
              args = {}, cwd = "${workspaceFolder}", stopOnEntry = false },
          }, vim.deepcopy(confs))
        end
        local go = o.go or {}
        if go ~= false then
          require("dap-go").setup({
            delve = { path = go.delve or "dlv" },
            dap_configurations = go.configurations,
          })
        end
      end,
    },
    -- сохранённые точки останова — после отрисовки (тянут dap, ~6 мс), дальше — с каждым открытым файлом
    {
      "Weissle/persistent-breakpoints.nvim",
      event = "VeryLazy",
      opts = { load_breakpoints_event = { "BufReadPost" } },
      config = function(_, opts)
        require("persistent-breakpoints").setup(opts)
        require("persistent-breakpoints.api").load_breakpoints()
      end,
    },
  }
end

function M.setup()
  if (d().go or {}) ~= false then tools.ensure_bin((d().go or {}).delve or "dlv", "debug") end
  -- codelldb — когда открыт C/C++/Rust-файл (большой: ~30 МБ, не ставим всем подряд)
  if d().cpp ~= false then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("own.debug.cpp", { clear = true }),
      pattern = { "c", "cpp", "rust" },
      once = true,
      callback = function() tools.ensure_bin("codelldb", "debug", nil, nil, "cpp") end,
    })
  end
end

function M.reload()
  if package.loaded["dap"] then signs() end
end

return M
