return {
  {
    "sainnhe/everforest",
    priority = 1000,
    lazy = false,
    config = function()
      vim.g.everforest_background = "hard"
      vim.g.everforest_enable_italic = 1
      vim.o.background = "dark"
      vim.cmd.colorscheme("everforest")
    end,
  },
}
