local inlay_hints = {
  parameterNames = { enabled = "literals" },
  parameterTypes = { enabled = true },
  variableTypes = { enabled = true },
  propertyDeclarationTypes = { enabled = true },
  functionLikeReturnTypes = { enabled = true },
  enumMemberValues = { enabled = true },
}

vim.lsp.config("vtsls", {
  settings = {
    vtsls = { autoUseWorkspaceTsdk = true },
    typescript = { inlayHints = inlay_hints },
    javascript = { inlayHints = inlay_hints },
  },
})

vim.lsp.enable({ "vtsls", "eslint" })

-- the pwa-node DAP adapter lives with the other adapters in neotest.lua
return {}
