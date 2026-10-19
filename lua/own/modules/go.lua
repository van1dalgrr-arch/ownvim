-- Go как в GoLand: ▶ у main и тестов, действия с превью (alt-enter), рефакторинги, «реализует: io.Reader»,
-- генерация (теги, интерфейс, тесты, if err), peek без перехода, покрытие тестами. Раздел "go":
--   "run_marks": true — ▶ слева от func main / TestX (пробел r x — запустить, пробел r X — в отладчике)
--   "implements": true — «реализует: …» рядом с типом
--   "coverage_file": "/tmp/cover.out"
local settings = require("own.settings")

local M = {}

local function g() return (settings.current or {}).go or {} end

function M.plugins()
  local o = g()
  return {
    -- меню действий с превью: что поменяется, видно до применения (delta)
    { "rachartier/tiny-code-action.nvim", dependencies = { "nvim-lua/plenary.nvim" }, event = "LspAttach", opts = { backend = "delta", picker = "snacks" } },
    {
      "maxandron/goplements.nvim",
      ft = "go",
      enabled = o.implements ~= false,
      opts = { prefix = { interface = "реализуют: ", struct = "реализует: " }, display_package = true, highlight = "Goplements" },
    },
    {
      "olexsmir/gopher.nvim",
      ft = "go",
      dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
      build = function() require("gopher").install_deps({ sync = true }) end,
      opts = {},
    },
    { "dnlhc/glance.nvim", cmd = "Glance", opts = { border = { enable = true }, theme = { enable = true, mode = "auto" } } },
    {
      "andythigpen/nvim-coverage",
      dependencies = { "nvim-lua/plenary.nvim" },
      cmd = { "Coverage", "CoverageLoad", "CoverageShow", "CoverageHide", "CoverageToggle", "CoverageSummary" },
      opts = {
        auto_reload = true,
        lang = { go = { coverage_file = o.coverage_file or "/tmp/cover.out" } },
        signs = { covered = { text = "▎" }, uncovered = { text = "▎" }, partial = { text = "▎" } },
      },
    },
  }
end

function M.coverage()
  vim.notify("go test -cover ./… — жду тесты")
  vim.system({ "go", "test", "-coverprofile=" .. (g().coverage_file or "/tmp/cover.out"), "./..." },
    { cwd = require("own.root").get(), text = true }, vim.schedule_wrap(function(res)
      if res.code ~= 0 then vim.notify("часть тестов упала — покрытие по тем, что прошли", vim.log.levels.WARN) end
      require("coverage").load(true)
    end))
end

--- Go-черновик: модуль в данных nvim, main.go — сразу запускать (пробел r x)
function M.scratch()
  local dir = vim.fn.stdpath("data") .. "/go-scratch"
  local file = dir .. "/main.go"
  if not vim.uv.fs_stat(file) then
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "module scratch", "", "go " .. (vim.fn.system({ "go", "env", "GOVERSION" }):match("go([%d%.]+)") or "1.24") }, dir .. "/go.mod")
    vim.fn.writefile({ "package main", "", 'import "fmt"', "", "func main() {", '\tfmt.Println("черновик")', "}" }, file)
  end
  vim.cmd.edit(file)
end

function M.setup()
  if g().run_marks ~= false then require("own.tools.run").setup() end
end

return M
