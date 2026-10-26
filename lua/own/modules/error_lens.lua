-- Ошибки как Error Lens в VS Code: аккуратная плашка справа от строки, длинное сообщение — в несколько строк;
-- ошибки видны и во вставке — пока печатаешь, без выхода в обычный режим ("insert": false — прятать во вставке).
-- Встроенный текст ошибок — выключается.
-- Настройки модуля: { "preset": "frame" | "modern" | "classic" | "minimal" | "ghost" | "simple" | "nonerdfont" | "amongus",
--   "frame" — рамкой, как всё в ownvim: ──[  undefined: foo ]  (значок — из diagnostics.signs, без плашки)
--                     "all_on_cursorline": true, "break_after": 60, "insert": true }
local M = {}

-- пресет «frame» — поверх «minimal» плагина: свои края и значки уровня из diagnostics.signs
local FRAME = {
  signs = { left = "[", right = "]", diag = "", arrow = " ──", up_arrow = " ──", vertical = "  │", vertical_end = "  └" },
  blend = { factor = 0 },
}

function M.plugins(opts)
  local frame = (opts.preset or "frame") == "frame"
  return {
    {
      "rachartier/tiny-inline-diagnostic.nvim",
      event = "LspAttach",
      priority = 1000,
      opts = {
        transparent_bg = frame or nil, -- без плашки: рамка — скобками
        preset = frame and "minimal" or opts.preset,
        signs = frame and FRAME.signs or nil,
        blend = frame and FRAME.blend or nil,
        options = {
          use_icons_from_diagnostic = frame, -- значки уровня — те же, что на полях (diagnostics.signs)
          set_arrow_to_diag_color = frame, -- линия к ошибке — цветом ошибки
          show_source = { enabled = false },
          multilines = { enabled = true, always_show = false },
          enable_on_insert = opts.insert ~= false,
          show_all_diags_on_cursorline = opts.all_on_cursorline ~= false,
          break_line = { enabled = true, after = opts.break_after or 60 },
        },
      },
      config = function(_, o)
        require("tiny-inline-diagnostic").setup(o)
        vim.diagnostic.config({ virtual_text = false })
        if frame then
          -- скобки плагин рисует «инвертированным» цветом — цветом фона плашки, без плашки они невидимы: красим цветом уровня
          local function brackets()
            for name in pairs(vim.api.nvim_get_hl(0, {})) do
              local level = type(name) == "string" and name:match("^TinyInlineInvDiagnosticVirtualText(%u%l+)")
              if level then
                local fg = vim.api.nvim_get_hl(0, { name = "Diagnostic" .. level, link = false }).fg
                if fg then vim.api.nvim_set_hl(0, name, { fg = fg }) end
              end
            end
          end
          brackets()
          vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("own.error_lens", { clear = true }),
            callback = function() vim.schedule(brackets) end,
          })
        end
      end,
    },
  }
end

return M
