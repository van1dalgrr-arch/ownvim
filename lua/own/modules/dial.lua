-- ctrl-a / ctrl-x — не только числа: true↔false, даты, и свои циклы по языкам из настроек модуля:
--   { "go": [[":=", "="], ["==", "!="], ["Error", "Fatal"], …] } — по слову (не части слова), если в паре есть буквы
local M = {}

function M.plugins(opts)
  return {
    {
      "monaqa/dial.nvim",
      keys = {
        { "<C-a>", function() return require("dial.map").inc_normal() end, expr = true, desc = "Увеличить / следующее" },
        { "<C-x>", function() return require("dial.map").dec_normal() end, expr = true, desc = "Уменьшить / предыдущее" },
        { "<C-a>", function() return require("dial.map").inc_visual() end, mode = "x", expr = true, desc = "Увеличить" },
        { "<C-x>", function() return require("dial.map").dec_visual() end, mode = "x", expr = true, desc = "Уменьшить" },
        { "g<C-a>", function() return require("dial.map").inc_gvisual() end, mode = "x", expr = true, desc = "Увеличить по порядку" },
      },
      config = function()
        local augend = require("dial.augend")
        local base = {
          augend.integer.alias.decimal_int, augend.integer.alias.hex, augend.date.alias["%Y-%m-%d"],
          augend.constant.alias.bool, augend.semver.alias.semver,
          augend.constant.new({ elements = { "and", "or" } }),
          augend.constant.new({ elements = { "&&", "||" }, word = false }),
        }
        local groups = { default = base }
        for ft, cycles in pairs(opts) do
          local list = vim.deepcopy(base)
          for _, elements in ipairs(cycles) do
            local word = elements[1]:match("%a") ~= nil
            list[#list + 1] = augend.constant.new({ elements = elements, word = word, cyclic = true })
          end
          groups[ft] = list
        end
        require("dial.config").augends:register_group(groups)
        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("own.dial", { clear = true }),
          callback = function(ev)
            if groups[ev.match] then vim.b[ev.buf].dial_group = ev.match end
          end,
        })
        -- dial.map берёт группу из b:dial_group, если есть
        local map = require("dial.map")
        for _, fn in ipairs({ "inc_normal", "dec_normal", "inc_visual", "dec_visual", "inc_gvisual", "dec_gvisual" }) do
          local orig = map[fn]
          map[fn] = function(group) return orig(group or vim.b.dial_group) end
        end
      end,
    },
  }
end

return M
