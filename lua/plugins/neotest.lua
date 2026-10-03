vim.g.neotest_vstest = {
  dap_settings = { type = "netcoredbg" },
}

return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
      "nvim-treesitter/nvim-treesitter",
      "nsidorenco/neotest-vstest",
      "nvim-neotest/neotest-python",
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-jest",
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-vstest"),
          require("neotest-python")({
            runner = "pytest",
            dap = { justMyCode = false },
          }),
          require("neotest-vitest"),
          require("neotest-jest"),
        },
      })
    end,
  },
  {
    "mfussenegger/nvim-dap",
    dependencies = { "rcarriga/nvim-dap-ui" },
    config = function()
      local dap = require("dap")

      dap.adapters.netcoredbg = {
        type = "executable",
        command = vim.fn.stdpath("data") .. "/mason/bin/netcoredbg",
        args = { "--interpreter=vscode" },
      }

      local js_debug_adapter = vim.fn.stdpath("data") .. "/mason/bin/js-debug-adapter"
      if vim.fn.has("win32") == 1 then
        js_debug_adapter = js_debug_adapter .. ".cmd"
      end
      dap.adapters["pwa-node"] = {
        type = "server",
        host = "localhost",
        port = "${port}",
        executable = { command = js_debug_adapter, args = { "${port}" } },
      }

      local js_configs = {
        {
          type = "pwa-node",
          name = "Launch current file",
          request = "launch",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
        },
        {
          type = "pwa-node",
          name = "Attach",
          request = "attach",
          processId = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
        },
      }
      for _, ft in ipairs({ "typescript", "typescriptreact", "javascript", "javascriptreact" }) do
        dap.configurations[ft] = js_configs
      end

      dap.configurations.cs = {
        {
          type = "netcoredbg",
          name = "Launch DLL",
          request = "launch",
          program = function()
            return vim.fn.input("DLL: ", vim.fn.getcwd() .. "/bin/Debug/net10.0/", "file")
          end,
        },
        {
          type = "netcoredbg",
          name = "Attach",
          request = "attach",
          processId = require("dap.utils").pick_process,
        },
      }

      local dapui = require("dapui")
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    opts = {},
  },
}
