return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        cs = { "csharpier" },
        python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
        typescript = { "prettierd" },
        typescriptreact = { "prettierd" },
        javascript = { "prettierd" },
        javascriptreact = { "prettierd" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },
}
