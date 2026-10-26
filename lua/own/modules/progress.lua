-- Прогресс языковых серверов в углу: gopls индексирует, rust-analyzer собирает — видно, что идёт работа и сколько
-- осталось, а не «редактор завис». Тихая строка справа внизу, над статусной строкой; закончилось — исчезает.
-- Выключить: "modules": { "progress": false }
local M = {}

function M.plugins()
  return {
    {
      "j-hui/fidget.nvim",
      event = "LspAttach",
      opts = function()
        return {
          progress = {
            display = {
              done_icon = "\u{eab2}", -- codicon check
              done_ttl = 2,
              progress_icon = { "dots" },
              group_style = "Title",
              icon_style = "Special",
              done_style = "DiagnosticOk",
              progress_style = "Comment",
            },
          },
          notification = {
            override_vim_notify = false, -- уведомления — у snacks, здесь только прогресс
            window = {
              winblend = 0,
              border = "none",
              normal_hl = "Comment",
              align = "bottom",
              relative = "editor",
              x_padding = 1,
              y_padding = 0,
            },
            view = { group_separator = "" },
          },
        }
      end,
    },
  }
end

return M
