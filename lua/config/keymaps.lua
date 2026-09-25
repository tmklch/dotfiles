local keymap = vim.keymap.set

keymap("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

keymap("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Neotest
keymap("n", "<leader>nt", function() require("neotest").run.run() end, { desc = "Run nearest test" })
keymap("n", "<leader>nf", function() require("neotest").run.run(vim.fn.expand("%")) end, { desc = "Run file tests" })
keymap("n", "<leader>nl", function() require("neotest").run.run_last() end, { desc = "Run last test" })
keymap("n", "<leader>nd", function() require("neotest").run.run({ strategy = "dap" }) end, { desc = "Debug nearest test" })
keymap("n", "<leader>ns", function() require("neotest").summary.toggle() end, { desc = "Toggle test summary" })
keymap("n", "<leader>no", function() require("neotest").output.open({ enter = true }) end, { desc = "Show test output" })

-- Dap
keymap("n", "<leader>db", function() require("dap").toggle_breakpoint() end, { desc = "Toggle breakpoint" })
keymap("n", "<leader>dc", function() require("dap").continue() end, { desc = "Continue/start debugging" })
keymap("n", "<leader>di", function() require("dap").step_into() end, { desc = "Step into" })
keymap("n", "<leader>do", function() require("dap").step_over() end, { desc = "Step over" })
keymap("n", "<leader>dO", function() require("dap").step_out() end, { desc = "Step out" })
keymap("n", "<leader>du", function() require("dapui").toggle() end, { desc = "Toggle debug UI" })
