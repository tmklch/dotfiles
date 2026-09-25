# .NET Test Running & Debugging (neotest-vstest) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add .NET test discovery, running, and debugging to the C# nvim config via neotest + neotest-vstest + nvim-dap, and pre-install the new Mason dependency (`netcoredbg`) in both bootstrap scripts.

**Architecture:** One new lazy.nvim plugin spec file (`lua/plugins/neotest.lua`) wires up `neotest` core, the `neotest-vstest` adapter, and `nvim-dap`/`nvim-dap-ui` for debugging. Keymaps land in the existing `lua/config/keymaps.lua`, with new which-key groups in `lua/plugins/which-key.lua`. Both bootstrap scripts get one new `MasonInstall netcoredbg` line next to the existing `MasonInstall roslyn` line.

**Tech Stack:** Neovim 0.10+, lazy.nvim, nvim-neotest/neotest, nsidorenco/neotest-vstest, mfussenegger/nvim-dap, rcarriga/nvim-dap-ui, mason-org/mason.nvim (already configured), dotnet CLI (already installed by bootstrap scripts).

## Global Constraints

- `neotest-vstest` is configured via `vim.g.neotest_vstest`, not a `setup()`/opts call — this is how the plugin itself expects to be configured.
- `dap.adapters.netcoredbg.command` must be the bare string `"netcoredbg"` (no hardcoded path) — Mason prepends `mason/bin` to `$PATH`, so the binary resolves from there.
- Do not touch the existing `<leader>t` "Toggle" group or `<leader>th` keymap — per explicit user decision, test keymaps live under a new `<leader>n` group instead.
- New plugin files go in `lua/plugins/` (auto-imported via `{ import = "plugins" }` in `lua/config/lazy.lua` — no manual registration needed).
- Bootstrap script changes follow the existing pattern exactly: `nvim --headless -c "MasonInstall <pkg>" -c "qa"` immediately after the existing Roslyn install line, in both `scripts/bootstrap-linux.sh` and `scripts/bootstrap-windows.ps1`.
- No automated Lua test framework exists in this repo. "Testing" means running Neovim headlessly and asserting on printed output/exit codes, exactly as used throughout `docs/superpowers/plans/2026-09-24-csharp-nvim-config.md`.

---

### Task 1: neotest + neotest-vstest + nvim-dap plugin spec

**Files:**
- Create: `lua/plugins/neotest.lua`

**Interfaces:**
- Produces: `require("neotest")`, `require("dap")`, `require("dapui")` all resolve to loaded plugin modules. `dap.adapters.netcoredbg` is registered. `vim.g.neotest_vstest.dap_settings.type == "netcoredbg"`.
- Consumes: `lua/plugins/` auto-import from `lua/config/lazy.lua` (already exists — no change needed). C# treesitter parser from `lua/plugins/treesitter.lua` (already installed — no change needed).

- [ ] **Step 1: Write `lua/plugins/neotest.lua`**

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

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua io.write(pcall(require, 'neotest') and 'NEOTEST_OK ' or 'NEOTEST_FAIL ')" -c "lua io.write(pcall(require, 'dap') and 'DAP_OK ' or 'DAP_FAIL ')" -c "lua io.write(pcall(require, 'dapui') and 'DAPUI_OK ' or 'DAPUI_FAIL ')" -c "lua io.write(pcall(require, 'neotest-vstest') and 'VSTEST_OK' or 'VSTEST_FAIL')" -c "qa" 2>&1
nvim --headless -c "lua print(vim.g.neotest_vstest.dap_settings.type)" -c "qa" 2>&1
```

Expected: the sync log shows `nvim-neotest/neotest`, `nsidorenco/neotest-vstest`, `nvim-neotest/nvim-nio`, `mfussenegger/nvim-dap`, and `rcarriga/nvim-dap-ui` installed with no errors. The second command prints `NEOTEST_OK DAP_OK DAPUI_OK VSTEST_OK`. The third prints `netcoredbg`.

- [ ] **Step 3: Verify the netcoredbg DAP adapter is registered**

```bash
nvim --headless -c "lua print(require('dap').adapters.netcoredbg.command)" -c "qa" 2>&1
```

Expected: prints `netcoredbg`.

- [ ] **Step 4: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/neotest.lua lazy-lock.json
git commit -m "Add neotest, neotest-vstest, and nvim-dap for .NET test running and debugging"
```

---

### Task 2: Keymaps and which-key groups

**Files:**
- Modify: `lua/config/keymaps.lua`
- Modify: `lua/plugins/which-key.lua`

**Interfaces:**
- Consumes: `require("neotest")`, `require("dap")`, `require("dapui")` from Task 1.
- Produces: keymaps `<leader>nt`, `<leader>nf`, `<leader>nl`, `<leader>nd`, `<leader>ns`, `<leader>no`, `<leader>db`, `<leader>dc`, `<leader>di`, `<leader>do`, `<leader>dO`, `<leader>du`.

- [ ] **Step 1: Add test and debug keymaps to `lua/config/keymaps.lua`**

Append to the end of the file:

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

- [ ] **Step 2: Add which-key groups to `lua/plugins/which-key.lua`**

In the `spec` table, add two new group entries (order doesn't matter, but keep it near the other group declarations for readability):

```lua
        { "<leader>n", group = "Test" },
        { "<leader>d", group = "Debug" },
```

The full `spec` table should now read:

```lua
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>e", group = "Explorer" },
        { "<leader>c", group = "Code" },
        { "<leader>ca", desc = "Code action" },
        { "<leader>r", group = "Refactor" },
        { "<leader>rn", desc = "Rename symbol" },
        { "<leader>t", group = "Toggle" },
        { "<leader>th", desc = "Toggle inlay hints" },
        { "<leader>n", group = "Test" },
        { "<leader>d", group = "Debug" },
      },
```

- [ ] **Step 3: Verify keymaps are registered**

```bash
nvim --headless -c "lua print(vim.fn.maparg('<leader>nt', 'n') ~= '' and 'NT_OK' or 'NT_FAIL')" -c "qa" 2>&1
nvim --headless -c "lua print(vim.fn.maparg('<leader>du', 'n') ~= '' and 'DU_OK' or 'DU_FAIL')" -c "qa" 2>&1
```

Expected: prints `NT_OK` and `DU_OK`.

- [ ] **Step 4: Commit**

```bash
cd ~/.config/nvim
git add lua/config/keymaps.lua lua/plugins/which-key.lua
git commit -m "Add test-running and debugging keymaps"
```

---

### Task 3: Bootstrap script wiring for netcoredbg

**Files:**
- Modify: `scripts/bootstrap-linux.sh`
- Modify: `scripts/bootstrap-windows.ps1`

**Interfaces:**
- Consumes: existing `MasonInstall roslyn` headless-install pattern in both scripts.
- Produces: `netcoredbg` binary available on `$PATH` via Mason after bootstrap runs, matching what Task 1's `dap.adapters.netcoredbg.command = "netcoredbg"` expects.

- [ ] **Step 1: Locate the existing Roslyn install line in `scripts/bootstrap-linux.sh`**

```bash
grep -n 'MasonInstall roslyn' scripts/bootstrap-linux.sh
```

Expected: one match, e.g. `echo "==> Installing Roslyn via Mason..."` followed by `nvim --headless -c "MasonInstall roslyn" -c "qa"`.

- [ ] **Step 2: Add the netcoredbg install immediately after it**

Edit `scripts/bootstrap-linux.sh` so the block reads:

```bash
echo "==> Installing Roslyn via Mason..."
nvim --headless -c "MasonInstall roslyn" -c "qa"

echo "==> Installing netcoredbg via Mason..."
nvim --headless -c "MasonInstall netcoredbg" -c "qa"
```

- [ ] **Step 3: Locate and edit the equivalent block in `scripts/bootstrap-windows.ps1`**

The existing block (around line 128) reads:

```powershell
    Write-Host "==> Installing Roslyn via Mason..."
    nvim --headless -c "MasonInstall roslyn" -c "qa"
    Invoke-Checked "nvim MasonInstall roslyn"
```

`Invoke-Checked` (defined at the top of the script) just checks `$LASTEXITCODE` from the command that ran immediately before it and throws using the given description if it's non-zero — it takes no other arguments. Edit the block so it reads:

```powershell
    Write-Host "==> Installing Roslyn via Mason..."
    nvim --headless -c "MasonInstall roslyn" -c "qa"
    Invoke-Checked "nvim MasonInstall roslyn"
    Write-Host "==> Installing netcoredbg via Mason..."
    nvim --headless -c "MasonInstall netcoredbg" -c "qa"
    Invoke-Checked "nvim MasonInstall netcoredbg"
```

- [ ] **Step 4: Syntax-check both scripts**

```bash
bash -n scripts/bootstrap-linux.sh && echo BASH_SYNTAX_OK
```

Expected: prints `BASH_SYNTAX_OK`. (PowerShell syntax can't be checked on this Linux machine; visually re-read the edited block against Step 3's `Invoke-Checked` pattern instead.)

- [ ] **Step 5: Run the netcoredbg Mason install for real on this machine**

Since this machine is already bootstrapped, run just the new line directly to confirm it actually installs (this is the real equivalent of a test for this step, since neither bootstrap script runs end-to-end in CI):

```bash
nvim --headless -c "MasonInstall netcoredbg" -c "qa" 2>&1
nvim --headless -c "lua print(vim.fn.executable('netcoredbg') == 1 and 'NETCOREDBG_OK' or 'NETCOREDBG_FAIL')" -c "qa" 2>&1
```

Expected: install log shows success with no errors; second command prints `NETCOREDBG_OK`.

- [ ] **Step 6: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-linux.sh scripts/bootstrap-windows.ps1
git commit -m "Pre-install netcoredbg via Mason in bootstrap scripts"
```

---

### Task 4: End-to-end verification against a real .NET test project

**Files:**
- None (no repo files change in this task — this is a manual verification pass)

**Interfaces:**
- Consumes: keymaps from Task 2, plugin setup from Task 1, `netcoredbg` from Task 3.

- [ ] **Step 1: Create a scratch xUnit test project**

```bash
mkdir -p ~/scratch/CsTestProject && cd ~/scratch/CsTestProject
dotnet new xunit --force
```

Expected: exits 0, creates `CsTestProject.csproj` and `UnitTest1.cs` with one passing test (`Test1`) in it.

- [ ] **Step 2: Open the test file and run the nearest test**

Run `nvim ~/scratch/CsTestProject/UnitTest1.cs` in a real interactive terminal (not headless — neotest/dap need a real UI).

In the buffer, place the cursor inside `Test1` and press `<leader>nt`.

Expected: neotest discovers and runs the test via `dotnet test`; a pass indicator (usually a `✓` sign in the gutter or a virtual-text summary) appears once it completes.

- [ ] **Step 3: Confirm the summary and output panels work**

Press `<leader>ns` (toggle summary) — expected: a sidebar appears listing `Test1` with a pass status.

Press `<leader>no` (show output) — expected: a floating window opens showing the `dotnet test` output for that test.

- [ ] **Step 4: Confirm debugging works**

In `UnitTest1.cs`, set a breakpoint on the assertion line inside `Test1` with `<leader>db`. Then place the cursor in `Test1` and press `<leader>nd` (debug nearest test).

Expected: execution stops at the breakpoint. Press `<leader>du` to open dap-ui — expected: variables/scopes/stack panes appear showing the paused test's local state. Press `<leader>dc` to continue — expected: the test finishes and reports pass/fail as in Step 2.

- [ ] **Step 5: Clean up the scratch project**

```bash
rm -rf ~/scratch/CsTestProject
```

This step has no commit — it's a verification pass, not a code change. If any step in this task fails, treat it as a bug against Task 1–3's implementation and fix the relevant task before considering this plan complete.

---
