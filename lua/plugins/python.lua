vim.lsp.config("basedpyright", {
  settings = {
    basedpyright = {
      -- ruff owns import organizing
      disableOrganizeImports = true,
      analysis = {
        typeCheckingMode = "standard",
        diagnosticMode = "openFilesOnly",
        inlayHints = {
          variableTypes = true,
          callArgumentNames = true,
          functionReturnTypes = true,
          genericTypes = false,
        },
      },
    },
  },
})

vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Leave hover to basedpyright when ruff is attached alongside it",
  group = vim.api.nvim_create_augroup("user-ruff-attach", { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end
  end,
})

vim.lsp.enable({ "basedpyright", "ruff" })

local function debugpy_python()
  local venv = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv"
  if vim.fn.has("win32") == 1 then
    return venv .. "/Scripts/python.exe"
  end
  return venv .. "/bin/python"
end

return {
  -- server definitions (cmd, filetypes, root markers) for vim.lsp.enable()
  { "neovim/nvim-lspconfig", lazy = false },
  {
    "mfussenegger/nvim-dap-python",
    ft = "python",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      require("dap-python").setup(debugpy_python())
    end,
  },
}
