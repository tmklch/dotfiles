# C# Neovim Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a from-scratch Neovim config at `~/.config/nvim` that is a usable daily-driver editor with first-class C# support (Roslyn LSP, inlay hints, signature help, hover/go-to-definition, diagnostics).

**Architecture:** `lazy.nvim`-managed plugins, one file per plugin/subsystem under `lua/plugins/` (auto-imported), core non-plugin config under `lua/config/`. Generic editor concerns (treesitter, telescope, neo-tree, lualine, completion, LSP infra) are split from the C#-specific layer (`csharp.lua`) so the language-specific piece stays additive and isolated.

**Tech Stack:** Neovim 0.12.x, lazy.nvim, `sainnhe/everforest`, `nvim-treesitter`, `telescope.nvim`, `neo-tree.nvim`, `lualine.nvim`, `nvim-cmp` + `LuaSnip`, `mason-org/mason.nvim`, `seblyng/roslyn.nvim`, `ray-x/lsp_signature.nvim`, .NET SDK 10.

## Global Constraints

- Neovim >= 0.12.0 required by `roslyn.nvim`; `extra/neovim` on this machine provides 0.12.5 — satisfied.
- `tree-sitter-cli` (>= 0.26.1) is required by `nvim-treesitter`'s `main` branch to compile parsers (discovered during Task 4 — the original prerequisite list missed this since it's a rewrite-specific requirement). Install via `sudo pacman -S tree-sitter-cli`.
- .NET SDK required with `dotnet` on `$PATH`; `extra/dotnet-sdk` provides 10.0.12 — satisfied.
- Leader key is the spacebar: `vim.g.mapleader = " "`, set at the very top of `init.lua`, before the `lazy.nvim` bootstrap runs.
- Colorscheme is `sainnhe/everforest` with `vim.g.everforest_background = "hard"`, dark mode, italics enabled. This is a static choice — explicitly **not** coupled to Noctalia/matugen live theme generation.
- No standalone linter: diagnostics come solely from Roslyn's built-in analyzers via the LSP client. Do not add `nvim-lint`, `dotnet format`, or Roslynator.
- Out of scope for this plan: DAP/debugging integration, format-on-save.
- `~/.config/nvim` is its own git repository (already initialized). Commit after every task.
- Mason requires a **custom registry** (`github:Crashdummyy/mason-registry`) alongside the core one — the `roslyn` package is not in Mason's default registry. Without this, `:MasonInstall roslyn` fails.
- Package installs (`sudo pacman -S ...`) require an interactive sudo password and cannot be run by a subagent — Task 1 must be run by a human directly.

---

### Task 1: Install System Prerequisites

**Files:** None — this task only installs system packages; no repository files are touched.

**Interfaces:**
- Produces: `nvim`, `dotnet`, `git`, `rg`, `fd`, `unzip` executables on `$PATH`. Every later task assumes these are present.

**This task requires an interactive sudo password and must be run by you directly** (e.g. via Claude Code's `!` prefix, or in your own terminal) — do not delegate it to a subagent.

- [ ] **Step 1: Install packages**

```bash
sudo pacman -S --needed neovim dotnet-sdk git ripgrep fd unzip tree-sitter-cli
```

(`tree-sitter-cli` was added after Task 4 discovered nvim-treesitter's rewrite requires it to compile parsers — see Global Constraints.)

- [ ] **Step 2: Verify each binary and version**

```bash
nvim --version | head -1
dotnet --version
git --version
rg --version | head -1
fd --version
unzip -v | head -1
```

Expected: every command prints a version string, no "command not found" errors. `nvim --version` should report `NVIM v0.12.x` or higher. `dotnet --version` should report `10.x`.

- [ ] **Step 3: No commit** — this task makes no repository changes.

---

### Task 2: Bootstrap Core Config (options, keymaps, autocmds, lazy.nvim)

**Files:**
- Create: `init.lua`
- Create: `lua/config/options.lua`
- Create: `lua/config/keymaps.lua`
- Create: `lua/config/autocmds.lua`
- Create: `lua/config/lazy.lua`

**Interfaces:**
- Consumes: `nvim` binary from Task 1.
- Produces: `vim.g.mapleader == " "`; `lazy.nvim` bootstrapped and available via `require("lazy")`; `lua/plugins/` established as the auto-imported plugin-spec directory (`{ import = "plugins" }`). Every later task drops exactly one new file into `lua/plugins/` — no existing file needs editing to register a new plugin.

There is no automated test framework for Lua editor config in this project. "Testing" throughout this plan means running Neovim headlessly and asserting on printed output / exit codes — this is the real equivalent of a test suite here.

- [ ] **Step 1: Write `lua/config/options.lua`**

```lua
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.wrap = false
opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = "yes"
opt.updatetime = 250
opt.termguicolors = true
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.undofile = true
opt.swapfile = false
```

- [ ] **Step 2: Write `lua/config/keymaps.lua`**

```lua
local keymap = vim.keymap.set

keymap("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

keymap("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })
```

- [ ] **Step 3: Write `lua/config/autocmds.lua`**

```lua
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  group = vim.api.nvim_create_augroup("user-highlight-yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})
```

- [ ] **Step 4: Write `lua/config/lazy.lua`**

```lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  install = { colorscheme = { "everforest" } },
  checker = { enabled = false },
})
```

- [ ] **Step 5: Write `init.lua`**

```lua
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
```

- [ ] **Step 6: Run the headless smoke test**

```bash
nvim --headless -c "lua print('LEADER_OK:' .. (vim.g.mapleader == ' ' and 'yes' or 'no'))" -c "qa" 2>&1
```

Expected: output includes `LEADER_OK:yes` and no Lua error traceback. The first run also clones `lazy.nvim` into `~/.local/share/nvim/lazy/lazy.nvim` — that clone output is expected, not an error.

If this errors with something like `module 'plugins' not found`: create the empty directory with `mkdir -p lua/plugins` and re-run — Task 3 will populate it immediately after anyway.

- [ ] **Step 7: Commit**

```bash
cd ~/.config/nvim
git add init.lua lua/config
git commit -m "Bootstrap lazy.nvim, core options, keymaps, and autocmds"
```

---

### Task 3: Colorscheme (everforest)

**Files:**
- Create: `lua/plugins/colorscheme.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2.
- Produces: active colorscheme name `"everforest"` (read via `vim.g.colors_name`). Task 7 (lualine) references the string `"everforest"` as its statusline theme name.

- [ ] **Step 1: Write `lua/plugins/colorscheme.lua`**

```lua
return {
  {
    "sainnhe/everforest",
    priority = 1000,
    lazy = false,
    config = function()
      vim.g.everforest_background = "hard"
      vim.g.everforest_enable_italic = 1
      vim.o.background = "dark"
      vim.cmd.colorscheme("everforest")
    end,
  },
}
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua io.write(vim.g.colors_name or 'NONE')" -c "qa" 2>&1
```

Expected: the sync log shows `sainnhe/everforest` installed with no errors; the second command prints `everforest`.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/colorscheme.lua
git commit -m "Add everforest colorscheme"
```

---

### Task 4: Treesitter

**Files:**
- Create: `lua/plugins/treesitter.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2.
- Produces: Treesitter syntax highlighting/indent active for `c_sharp`, `lua`, `vim`, `vimdoc`, `bash`, `json`, `markdown`, `yaml`. No function-level interface consumed by later tasks.

**Correction (2026-09-24):** the plan originally specified nvim-treesitter's old `nvim-treesitter.configs` API. That API no longer exists — `nvim-treesitter`'s `main` branch (required for Neovim >= 0.12; the old `master` branch is frozen and caps at Neovim 0.11) is a full, incompatible rewrite. Verified against the live README on 2026-09-24. The content below reflects the current API.

- [ ] **Step 1: Write `lua/plugins/treesitter.lua`**

```lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
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
          vim.treesitter.start()
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
```

- [ ] **Step 2: Sync plugins, force-install the C# parser synchronously, and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa" 2>&1
ls ~/.local/share/nvim/site/parser/ | grep -i c_sharp
```

Expected: the sync log shows `nvim-treesitter` installed with no errors; the `:wait(300000)` call blocks (up to 5 minutes) until the parser is compiled; the final `ls` prints a `c_sharp.so` file.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/treesitter.lua
git commit -m "Add treesitter with C# parser"
```

---

### Task 5: Telescope + fzf-native

**Files:**
- Create: `lua/plugins/telescope.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2.
- Produces: `:Telescope` command; `<leader>ff`/`<leader>fg`/`<leader>fb`/`<leader>fh` keymaps. **Task 9 depends on this** — its `gd`/`gr` keymaps call `<cmd>Telescope lsp_definitions<cr>` / `<cmd>Telescope lsp_references<cr>`, which require this task to be installed first.

- [ ] **Step 1: Write `lua/plugins/telescope.lua`**

```lua
return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({})
      telescope.load_extension("fzf")
    end,
  },
}
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua require('lazy').load({plugins = {'telescope.nvim'}})" -c "lua print(vim.fn.exists(':Telescope'))" -c "qa" 2>&1
nvim --headless -c "lua require('lazy').load({plugins = {'telescope.nvim'}})" -c "lua print(require('telescope').extensions.fzf ~= nil)" -c "qa" 2>&1
```

**Correction (2026-09-24):** the plugin is lazy-loaded via `keys` only (no `cmd`), so lazy.nvim does not stub the `:Telescope` command ahead of time — checking `vim.fn.exists(':Telescope')` *without* forcing a load first returns `0`, not `2`. Both checks above force the load first (`require('lazy').load(...)`), matching how the plugin actually behaves once a keymap is pressed. Expected: first check prints `2`, second prints `true`.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/telescope.lua
git commit -m "Add telescope with fzf-native"
```

---

### Task 6: Neo-tree

**Files:**
- Create: `lua/plugins/neo-tree.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2.
- Produces: `:Neotree` command, `<leader>ee` keymap. `<leader>ee` (not `<leader>e`) is used deliberately — `<leader>e` is reserved for the diagnostics-float keymap defined in Task 9.

- [ ] **Step 1: Write `lua/plugins/neo-tree.lua`**

```lua
return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>ee", "<cmd>Neotree toggle<cr>", desc = "Toggle file explorer" },
    },
    opts = {},
  },
}
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua require('lazy').load({plugins = {'neo-tree.nvim'}})" -c "lua print(vim.fn.exists(':Neotree'))" -c "qa" 2>&1
```

Expected: prints `2`.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/neo-tree.lua
git commit -m "Add neo-tree file explorer"
```

---

### Task 7: Lualine

**Files:**
- Create: `lua/plugins/lualine.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2; the string `"everforest"` as a lualine built-in theme name (Task 3).
- Produces: statusline rendered via lualine. No other task depends on this one.

- [ ] **Step 1: Write `lua/plugins/lualine.lua`**

```lua
return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "everforest",
      },
    },
  },
}
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua print(require('lualine').get_config().options.theme)" -c "qa" 2>&1
```

Expected: prints `everforest`. (No `keys`/`event`/`cmd` trigger is set on this plugin, so lazy.nvim loads it eagerly at startup — no forced `lazy.load` needed for this check.)

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/lualine.lua
git commit -m "Add lualine statusline themed to everforest"
```

---

### Task 8: Completion (nvim-cmp)

**Files:**
- Create: `lua/plugins/completion.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2.
- Produces: `nvim-cmp` configured with `nvim_lsp` and `luasnip` sources, wired to activate on `InsertEnter`. Task 10's Roslyn LSP client is automatically picked up as a completion source once it attaches — no additional wiring needed in `csharp.lua`.

- [ ] **Step 1: Write `lua/plugins/completion.lua`**

```lua
return {
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      require("luasnip.loaders.from_vscode").lazy_load()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }),
      })
    end,
  },
}
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua require('lazy').load({plugins = {'nvim-cmp'}})" -c "lua print(#require('cmp').get_config().sources)" -c "qa" 2>&1
```

Expected: prints `2` (the `nvim_lsp` and `luasnip` sources).

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/completion.lua
git commit -m "Add nvim-cmp completion with LSP and snippet sources"
```

---

### Task 9: Generic LSP Infrastructure (Mason, diagnostics, LspAttach keymaps)

**Files:**
- Create: `lua/plugins/lsp.lua`

**Interfaces:**
- Consumes: `lua/plugins/` auto-import from Task 2; `:Telescope lsp_definitions` / `:Telescope lsp_references` from Task 5 (used by the `gd`/`gr` keymaps below).
- Produces:
  - `:Mason` command, with the custom `Crashdummyy/mason-registry` registry active — **Task 10 depends on this** to run `:MasonInstall roslyn`.
  - The augroup `"user-lsp-attach"`, which fires on every `LspAttach` event (any language server, though today only Roslyn attaches) and sets: `gd`, `gr`, `K`, `<leader>rn`, `<leader>ca`, `<leader>e`, `[d`, `]d`, `<leader>th`, and enables inlay hints for the attaching buffer. **Task 10 relies on this** — it does not duplicate any LSP-attach logic itself.

This is a config module, not purely a plugin declaration: it runs `vim.diagnostic.config(...)` and registers the `LspAttach` autocommand as top-level code, then returns the one real plugin spec (`mason.nvim`). This is intentional — Neovim's `vim.diagnostic`/autocmd APIs are core, not part of any plugin, and there is currently no other language server besides Roslyn to justify installing `nvim-lspconfig` as a dependency (it would configure zero servers right now).

- [ ] **Step 1: Write `lua/plugins/lsp.lua`**

```lua
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
    vim.keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<cr>", opts)
    vim.keymap.set("n", "gr", "<cmd>Telescope lsp_references<cr>", opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

    vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    vim.keymap.set("n", "<leader>th", function()
      local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf })
      vim.lsp.inlay_hint.enable(not enabled, { bufnr = event.buf })
    end, opts)
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
```

- [ ] **Step 2: Sync plugins and verify**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
nvim --headless -c "lua print(vim.fn.exists(':Mason'))" -c "qa" 2>&1
nvim --headless -c "lua print(#vim.api.nvim_get_autocmds({group = 'user-lsp-attach'}))" -c "qa" 2>&1
nvim --headless -c "lua print(vim.diagnostic.config().severity_sort)" -c "qa" 2>&1
```

Expected: `2`, `1`, `true` respectively.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/lsp.lua
git commit -m "Add Mason with custom registry, diagnostics config, and LspAttach keymaps"
```

---

### Task 10: C# Language Stack (roslyn.nvim + lsp_signature.nvim) and Full Verification

**Files:**
- Create: `lua/plugins/csharp.lua`

**Interfaces:**
- Consumes: `:MasonInstall` and the `Crashdummyy` registry from Task 9; the `LspAttach` keymaps and inlay-hint enabling from Task 9 (this file adds no LSP-attach logic of its own).
- Produces: an active `roslyn` LSP client on `.cs` files; signature-help popups via `lsp_signature.nvim`.

`roslyn.nvim` (`seblyng/roslyn.nvim`) is an actively-maintained fork that drives Microsoft's real Roslyn language server via Neovim's native `vim.lsp.config`/`vim.lsp.enable` API (Neovim >= 0.11). Confirmed against its current README and DeepWiki docs on 2026-09-24 — this is a fast-moving plugin, so if any step below doesn't match what you see, check https://github.com/seblyng/roslyn.nvim for what changed.

- [ ] **Step 1: Write `lua/plugins/csharp.lua`**

```lua
vim.lsp.config("roslyn", {
  settings = {
    ["csharp|inlay_hints"] = {
      csharp_enable_inlay_hints_for_implicit_object_creation = true,
      csharp_enable_inlay_hints_for_implicit_variable_types = true,
      csharp_enable_inlay_hints_for_lambda_parameter_types = true,
      csharp_enable_inlay_hints_for_types = true,
      dotnet_enable_inlay_hints_for_parameters = true,
      dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
    },
  },
})

return {
  {
    "seblyng/roslyn.nvim",
    ft = "cs",
    opts = {
      filewatching = "auto",
    },
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "LspAttach",
    opts = {
      hint_enable = false,
      floating_window = true,
      handler_opts = { border = "rounded" },
    },
  },
}
```

- [ ] **Step 2: Sync plugins**

```bash
nvim --headless "+Lazy! sync" +qa 2>&1
```

Expected: `seblyng/roslyn.nvim` and `ray-x/lsp_signature.nvim` installed with no errors.

- [ ] **Step 3: Install the Roslyn language server binary via Mason**

```bash
nvim --headless -c "MasonInstall roslyn" -c "qa" 2>&1
```

This downloads the actual Roslyn server binary (separate from the Lua plugin) and can take a minute or two. Expected: log ends with a successful-install message (or an already-installed message on a rerun), no "package not found" error — a "not found" error here means the custom registry from Task 9 isn't active; re-check that step.

- [ ] **Step 4: Verify the binary is present**

```bash
ls ~/.local/share/nvim/mason/bin/ | grep -i roslyn
```

Expected: a `roslyn` entry.

- [ ] **Step 5: Create a scratch C# project to test against**

```bash
mkdir -p ~/scratch/CsTest && cd ~/scratch/CsTest && dotnet new console --force
```

- [ ] **Step 6: Replace the generated `Program.cs`**

```csharp
using System;

class Program
{
    static int Add(int first, int second)
    {
        return first + second;
    }

    static void Main()
    {
        var result = Add(2, 3);
        Console.WriteLine(result);
        int unused = 5;
    }
}
```

This file deliberately exercises every feature from the spec: `Add(2, 3)` is a call site for inlay parameter hints and signature help; `var result` exercises the implicit-type inlay hint; `int unused = 5;` is an unused local that Roslyn's analyzer will flag, exercising diagnostics.

- [ ] **Step 7: Manual interactive verification (cannot be scripted headlessly — hover/signature-help are interactive UI)**

Run `nvim ~/scratch/CsTest/Program.cs` in a real terminal and confirm, in order:

1. `:checkhealth roslyn` reports no errors.
2. Within ~15 seconds, `:LspInfo` shows a `roslyn` client attached to the buffer. If it never attaches, re-check Step 1's plugin spec against the current `seblyng/roslyn.nvim` README — some versions require an explicit `vim.lsp.enable("roslyn")` call that this plan's version does not.
3. Inlay hints render inline on the `Add(2, 3)` call (parameter names `first:`/`second:`) and on `var result` (inferred type).
4. Enter insert mode with the cursor between the parens of `Add(2, 3)` — a signature-help popup shows `Add(int first, int second)` with the active parameter highlighted.
5. Move the cursor onto `Add` in normal mode and press `K` — a hover popup shows the method signature.
6. With the cursor on the `Add` call, press `gd` — it jumps to (or opens a Telescope picker pointing at) the `Add` method definition.
7. The `unused` variable is underlined; pressing `<leader>e` with the cursor on that line shows the diagnostic message in a float.
8. The buffer renders with the `everforest` palette and C# syntax highlighting is visibly active (keywords, strings, types distinctly colored).
9. Press `<leader>th` — inlay hints disappear; press it again — they return.

- [ ] **Step 8: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/csharp.lua
git commit -m "Add roslyn.nvim LSP and lsp_signature.nvim for C# support"
```

---

## Plan Self-Review Notes

- **Spec coverage:** prerequisites → Task 1; foundation/lazy.nvim → Task 2; colorscheme → Task 3; treesitter/telescope/neo-tree/lualine → Tasks 4–7; completion → Task 8; generic LSP + keymaps + diagnostics → Task 9; roslyn/inlay hints/signature help/hover/definition → Task 10; full verification walkthrough (spec §8) → Task 10 Step 7. Leader key → Task 2 Step 5. No gaps found.
- **Keymap collision check:** `<leader>e` (diagnostics float, Task 9) vs. Neo-tree's toggle — deliberately moved Neo-tree to `<leader>ee` (Task 6) to avoid the collision.
- **Cross-task dependency check:** Task 9's `gd`/`gr` keymaps call Telescope commands from Task 5 — confirmed Task 5 precedes Task 9 in execution order. Task 10 depends on Task 9's Mason registry and LspAttach autocmd — confirmed Task 9 precedes Task 10.
