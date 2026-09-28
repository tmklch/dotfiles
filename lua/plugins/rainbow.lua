return {
  {
    "HiPhish/rainbow-delimiters.nvim",
    -- Attaches on FileType via treesitter; lazy-loading would miss the first buffer.
    lazy = false,
    config = function()
      -- Use everforest's palette instead of the plugin's generic colors.
      -- Re-applied on ColorScheme since a colorscheme load clears highlights.
      local links = {
        RainbowDelimiterRed = "Red",
        RainbowDelimiterYellow = "Yellow",
        RainbowDelimiterBlue = "Blue",
        RainbowDelimiterOrange = "Orange",
        RainbowDelimiterGreen = "Green",
        RainbowDelimiterViolet = "Purple",
        RainbowDelimiterCyan = "Aqua",
      }
      local function apply()
        for group, target in pairs(links) do
          vim.api.nvim_set_hl(0, group, { link = target })
        end
      end
      apply()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("user-rainbow-delimiters", { clear = true }),
        callback = apply,
      })
    end,
  },
}
