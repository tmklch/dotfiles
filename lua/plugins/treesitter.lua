return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup({
        install_dir = vim.fn.stdpath("data") .. "/site",
      })
      require("nvim-treesitter").install({
        "c_sharp", "lua", "vim", "vimdoc", "bash", "json", "markdown", "yaml",
      })

      -- main-branch rewrite: highlighting/indent are enabled per-filetype,
      -- not via a setup() table. Note pattern uses Neovim filetype names
      -- (e.g. "cs", "help", "sh"), not treesitter parser names (e.g. "c_sharp", "vimdoc", "bash").
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "cs", "lua", "vim", "help", "sh", "json", "markdown", "yaml" },
        callback = function()
          pcall(vim.treesitter.start)
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
