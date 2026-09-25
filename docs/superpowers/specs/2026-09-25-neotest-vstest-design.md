# Design: .NET test running & debugging via neotest-vstest

## Problem

The C# nvim config (LSP, completion, treesitter) has no way to discover, run, or
debug .NET tests from inside the editor. `docs/superpowers/specs/2026-09-24-csharp-nvim-config-design.md`
explicitly deferred DAP/debugging as "not requested; can be added later." That
time has come: add https://github.com/Nsidorenco/neotest-vstest as a
[neotest](https://github.com/nvim-neotest/neotest) adapter for VSTest-based
.NET test running, with full debugging support.

## Requirements

- Discover and run xUnit/NUnit/MSTest tests in `.cs`/`.fsproj` projects via the
  `dotnet` CLI (already installed by both bootstrap scripts for Roslyn).
- Run nearest test, run current file's tests, re-run last test, view a summary
  panel and per-test output.
- Debug a failing/target test with breakpoints, step commands, and variable
  inspection — not just print-style output.
- Fresh-machine bootstrap must still produce a fully working setup with no
  extra manual steps, matching how Roslyn is pre-installed today.

## Components

### `lua/plugins/neotest.lua` (new)

```lua
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
    },
    opts = {
      adapters = {
        require("neotest-vstest"),
      },
    },
  },
  {
    "mfussenegger/nvim-dap",
    config = function()
      require("dap").adapters.netcoredbg = {
        type = "executable",
        -- Mason prepends its bin dir to $PATH, so this resolves without a hardcoded path.
        command = "netcoredbg",
        args = { "--interpreter=vscode" },
      }
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    opts = {},
  },
}
```

- `neotest-vstest` reads its config from `vim.g.neotest_vstest`, not a `setup()`
  call. `dap_settings = { type = "netcoredbg" }` is what `run.run({strategy =
  "dap"})` passes to `nvim-dap` when debugging a test.
- The C# treesitter parser is already installed (`lua/plugins/treesitter.lua`);
  no change needed there.
- `sdk_path` / `solution_selector` / `discovery_directory_filter` etc. are left
  at their defaults (auto-discovery) — no evidence yet that auto-discovery
  fails in this setup; can be tuned later if it does.

### `lua/config/keymaps.lua` additions

```lua
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
```

The existing `<leader>t` "Toggle" group (`<leader>th` for inlay hints) is left
untouched, per user preference — test keymaps live under a new `<leader>n`
group instead.

### `lua/plugins/which-key.lua` additions

```lua
{ "<leader>n", group = "Test" },
{ "<leader>d", group = "Debug" },
```

(`<leader>d` doesn't currently exist as a group; adding it fresh.)

### Bootstrap scripts

Both scripts already pre-install Roslyn via Mason in headless mode. Add the
same pattern for `netcoredbg` immediately after, in both:

- `scripts/bootstrap-linux.sh`: after `nvim --headless -c "MasonInstall roslyn" -c "qa"`
- `scripts/bootstrap-windows.ps1`: after the equivalent `MasonInstall roslyn` line

```
nvim --headless -c "MasonInstall netcoredbg" -c "qa"
```

No new system package or PATH changes are needed — `dotnet`, git, and the
treesitter C# parser are already provisioned by the existing bootstrap steps,
and Mason downloads the `netcoredbg` binary itself (works identically on
Linux and Windows).

## Out of scope

- Custom `neotest-vstest` tuning (`sdk_path`, `solution_selector`,
  `discovery_directory_filter`, `timeout_ms`) — defaults are used; revisit if
  discovery/build issues appear against a real solution.
- F# support beyond what neotest-vstest provides out of the box (this config
  has no F# tooling installed elsewhere either).
- Format-on-save, code coverage integration — unrelated to this addition.

## Testing approach

There's no automated test framework for Lua editor config in this project
(consistent with the original C# config plan). "Testing" means:

1. Headless smoke test: `nvim --headless -c "lua require('neotest')" -c "lua require('dap')" -c "lua require('dapui')" -c "qa"` exits 0 with no errors, confirming all new plugins load and require cleanly.
2. Against the existing `~/scratch/CsTest` scaffold (or a new one with an actual test project, e.g. `dotnet new xunit`): confirm `<leader>nt` discovers and runs a test, shows pass/fail in the summary panel, and `<leader>no` shows output.
3. Set a breakpoint in a test body, run `<leader>nd`, confirm execution stops at the breakpoint and `<leader>du` shows variables/stack via dap-ui.
4. Re-run the bootstrap script's Mason-install step (or just `MasonInstall netcoredbg` manually) and confirm it succeeds, matching the Roslyn install pattern.
