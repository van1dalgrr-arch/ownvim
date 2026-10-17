-- Летающий курсор: при прыжке за ним тянется след. По умолчанию выключен.
return {
  plugins = {
    { "sphamba/smear-cursor.nvim", event = "VeryLazy", opts = { hide_target_hack = true, cursor_color = "none" } },
  },
}
