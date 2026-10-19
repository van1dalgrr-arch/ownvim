-- Мультикурсоры, как Alt+J / Ctrl+G в GoLand: ctrl-n — курсор на следующем таком же слове, пробел m — меню,
-- alt+клик — поставить/убрать. Пока курсоры есть: ←/→ — переключаться, пробел x — убрать текущий, esc — все.
local M = {}

local function mc(fn, ...)
  local args = { ... }
  return function() require("multicursor-nvim")[fn](unpack(args)) end
end

function M.plugins()
  return {
    {
      "jake-stewart/multicursor.nvim",
      branch = "1.0",
      keys = {
        { "<c-n>", mc("matchAddCursor", 1), mode = { "n", "x" }, desc = "Курсор на следующем совпадении" },
        { "<leader>m", "", desc = "+мультикурсор", mode = { "n", "x" } },
        { "<leader>mn", mc("matchAddCursor", 1), mode = { "n", "x" }, desc = "Следующее совпадение" },
        { "<leader>mN", mc("matchAddCursor", -1), mode = { "n", "x" }, desc = "Предыдущее совпадение" },
        { "<leader>ms", mc("matchSkipCursor", 1), mode = { "n", "x" }, desc = "Пропустить совпадение" },
        { "<leader>ma", mc("matchAllAddCursors"), mode = { "n", "x" }, desc = "На всех совпадениях" },
        { "<leader>mj", mc("lineAddCursor", 1), mode = { "n", "x" }, desc = "Курсор строкой ниже" },
        { "<leader>mk", mc("lineAddCursor", -1), mode = { "n", "x" }, desc = "Курсор строкой выше" },
        { "<leader>ml", mc("alignCursors"), desc = "Выровнять курсоры в столбец" },
        { "<leader>mx", mc("restoreCursors"), desc = "Вернуть убранные курсоры" },
        { "<M-leftmouse>", mc("handleMouse"), desc = "Курсор по клику" },
        { "<M-leftdrag>", mc("handleMouseDrag") },
        { "<M-leftrelease>", mc("handleMouseRelease") },
      },
      config = function()
        local m = require("multicursor-nvim")
        m.setup()
        m.addKeymapLayer(function(set)
          set({ "n", "x" }, "<left>", m.prevCursor)
          set({ "n", "x" }, "<right>", m.nextCursor)
          set({ "n", "x" }, "<leader>x", m.deleteCursor)
          set("n", "<esc>", function()
            if not m.cursorsEnabled() then m.enableCursors() else m.clearCursors() end
          end)
        end)
      end,
    },
  }
end

return M
