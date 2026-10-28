-- Тесты (neotest): запуск теста под курсором, файла, всех; результат значками у теста, упавшая
-- проверка — ошибкой на её строке, вывод — по пробел t o. Раздел "test" в settings.jsonc:
--   "adapters": { "neotest-golang": { "go_test_args": […] }, "neotest-python": false } —
--     имя адаптера → его настройки (true — по умолчанию, false — выкл). Свой адаптер: { "repo": "автор/плагин", … }
--   "status": { "virtual_text": true }, "output": { "open_on_run": false } — как в neotest
--   "diagnostic": { "enabled": true, "severity": "error" } — упавшая проверка на строке, каким уровнем
--   "failed_as_error": true — в упавшем Go-тесте его сообщения — ошибки (а не подсказки, как решает neotest-golang)
-- Адаптеры и их настройки — после :restart.
local settings = require("own.settings")

local M = {}

-- известные адаптеры: имя → репозиторий
local REPOS = {
  ["neotest-golang"] = "fredrikaverpil/neotest-golang",
  ["neotest-python"] = "nvim-neotest/neotest-python",
  ["neotest-rust"] = "rouge8/neotest-rust",
  ["neotest-vitest"] = "marilari88/neotest-vitest",
  ["neotest-jest"] = "nvim-neotest/neotest-jest",
}

local function t() return (settings.current or {}).test or {} end

local function adapters()
  local list = {}
  for name, v in pairs(t().adapters or {}) do
    if v ~= false then
      local o = type(v) == "table" and vim.deepcopy(v) or {}
      local repo = o.repo or REPOS[name]
      o.repo = nil
      -- Python тестов — окружения проекта (модуль python), если свой не задан
      if name == "neotest-python" and o.python == nil and settings.enabled(settings.current or {}, "python") then
        o.python = function(dir) return require("own.modules.python").python(dir) end
      end
      if repo then
        list[#list + 1] = { name = name, repo = repo, opts = o }
      else
        settings.warn(name, ("не знаю, где адаптер %q — задай \"repo\": \"автор/плагин\""):format(name))
      end
    end
  end
  return list
end

function M.plugins()
  local deps = { "nvim-neotest/nvim-nio", "nvim-lua/plenary.nvim" }
  for _, a in ipairs(adapters()) do
    deps[#deps + 1] = a.name == "neotest-golang" and { a.repo, version = "*" } or a.repo
  end
  return {
    {
      "nvim-neotest/neotest",
      dependencies = deps,
      cmd = "Neotest",
      config = function()
        local o = t()
        local list = {}
        for _, a in ipairs(adapters()) do
          local ok, adapter = pcall(require, a.name)
          if ok then
            list[#list + 1] = next(a.opts) and adapter(a.opts) or adapter
          else
            settings.warn(a.name, "адаптер не загрузился: " .. tostring(adapter))
          end
        end
        -- сообщения упавших тестов — в одну строку
        vim.diagnostic.config({
          virtual_text = { format = function(d) return (d.message:gsub("%s+", " ")) end },
        }, vim.api.nvim_create_namespace("neotest"))
        -- neotest-golang считает t.Errorf подсказкой (угадывает по тексту) — в упавшем тесте это ошибка
        local okd, gd = pcall(require, "neotest-golang.lib.diagnostics")
        if okd and o.failed_as_error ~= false and not gd.own_patched then
          gd.own_patched = true
          local orig = gd.process_diagnostics
          gd.process_diagnostics = function(entry)
            local errs = orig(entry)
            if entry.result and entry.result.status == "failed" then
              for _, e in ipairs(errs) do e.severity = vim.diagnostic.severity.ERROR end
            end
            return errs
          end
        end
        local diag = vim.deepcopy(o.diagnostic or { enabled = true, severity = "error" })
        if type(diag.severity) == "string" then diag.severity = vim.diagnostic.severity[diag.severity:upper()] end
        require("neotest").setup({
          adapters = list,
          diagnostic = diag,
          status = o.status or { virtual_text = true },
          output = o.output or { open_on_run = false },
          quickfix = { open = false },
        })
      end,
    },
  }
end

return M
