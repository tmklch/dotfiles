vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  group = vim.api.nvim_create_augroup("user-highlight-yank", { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  desc = "C# indentation: cindent with lambda fix, 4 spaces to match csharpier",
  group = vim.api.nvim_create_augroup("user-cs-indent", { clear = true }),
  pattern = "cs",
  callback = function()
    vim.bo.shiftwidth = 4
    vim.bo.tabstop = 4
    vim.bo.cindent = true
    -- One shiftwidth for continuation args; ")" on its own line closes at the call's level.
    vim.bo.cinoptions = "(s,m1"
    vim.bo.indentexpr = "v:lua.require'config.cs_indent'.get(v:lnum)"
  end,
})
