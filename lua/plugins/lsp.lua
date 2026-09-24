vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded" },
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("user-lsp-attach", { clear = true }),
  callback = function(event)
    local opts = { buffer = event.buf }
    vim.keymap.set(
      "n",
      "gd",
      "<cmd>Telescope lsp_definitions<cr>",
      vim.tbl_extend("force", opts, { desc = "Go to definition" })
    )
    vim.keymap.set(
      "n",
      "gr",
      "<cmd>Telescope lsp_references<cr>",
      vim.tbl_extend("force", opts, { desc = "Find references" })
    )
    vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
    vim.keymap.set(
      "n",
      "<leader>rn",
      vim.lsp.buf.rename,
      vim.tbl_extend("force", opts, { desc = "Rename symbol" })
    )
    vim.keymap.set(
      "n",
      "<leader>ca",
      vim.lsp.buf.code_action,
      vim.tbl_extend("force", opts, { desc = "Code action" })
    )
    vim.keymap.set(
      "n",
      "<leader>e",
      vim.diagnostic.open_float,
      vim.tbl_extend("force", opts, { desc = "Show line diagnostics" })
    )

    vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    vim.keymap.set("n", "<leader>th", function()
      local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf })
      vim.lsp.inlay_hint.enable(not enabled, { bufnr = event.buf })
    end, vim.tbl_extend("force", opts, { desc = "Toggle inlay hints" }))
  end,
})

return {
  {
    "mason-org/mason.nvim",
    opts = {
      -- the roslyn LSP package isn't in Mason's core registry
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
      },
    },
  },
}
