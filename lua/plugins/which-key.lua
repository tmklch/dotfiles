return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>e", group = "Explorer" },
        { "<leader>c", group = "Code" },
        { "<leader>ca", desc = "Code action" },
        { "<leader>r", group = "Refactor" },
        { "<leader>rn", desc = "Rename symbol" },
        { "<leader>t", group = "Toggle" },
        { "<leader>th", desc = "Toggle inlay hints" },
        { "<leader>n", group = "Test" },
        { "<leader>d", group = "Debug" },
      },
    },
  },
}
