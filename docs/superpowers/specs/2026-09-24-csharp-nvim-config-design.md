# Neovim Config for C# Development — Design

## Goal

Stand up a from-scratch Neovim configuration, usable as a daily-driver editor, with first-class C# support: LSP diagnostics, inline type/parameter hints, signature help while typing, and go-to-definition/hover.

## Context

- No Neovim config or Neovim installation currently exists on this machine (CachyOS/Arch, Hyprland desktop).
- No `.NET` SDK installed.
- Desktop theme is Noctalia-managed, currently rendering the **Everforest** dark palette (confirmed via `~/.config/kitty/themes/noctalia.conf`, `~/.config/alacritty/themes/noctalia.toml`, and Noctalia's cached `community-palettes/Everforest.json`). Terminal background `#1e2326` is darker than any single official Everforest variant.

## 1. System Prerequisites

Install via pacman:

- `neovim`
- `dotnet-sdk`
- `git`
- `ripgrep` (Telescope live-grep)
- `fd` (Telescope file-finding)
- `unzip` (required by Mason to unpack downloaded LSP binaries)

Nerd Font presence in the terminal is a nice-to-have for plugin icons (nvim-tree/telescope/lualine glyphs); if absent, icons degrade gracefully to plain text — not a blocker.

## 2. Foundation

- **Plugin manager:** `lazy.nvim`, bootstrapped from `init.lua` on first launch (standard self-cloning bootstrap into `~/.local/share/nvim/lazy/lazy.nvim`).
- **Repo:** `~/.config/nvim` is its own git repository.
- **Layout:**
  ```
  ~/.config/nvim/
    init.lua
    lua/config/
      options.lua      -- vim.opt settings
      keymaps.lua       -- non-LSP keymaps
      autocmds.lua
      lazy.lua           -- lazy.nvim bootstrap + plugin spec loader
    lua/plugins/
      colorscheme.lua    -- everforest
      treesitter.lua
      telescope.lua
      neo-tree.lua
      lualine.lua
      completion.lua     -- nvim-cmp + luasnip
      lsp.lua            -- mason, mason-lspconfig, generic LSP setup, diagnostics config
      csharp.lua         -- roslyn.nvim + lsp_signature.nvim, C#-specific settings
  ```
  `csharp.lua` is kept separate from the generic `lsp.lua` so adding another language later is additive (one new file), not a modification of existing ones.

## 3. Colorscheme

- Plugin: `sainnhe/everforest` — the canonical, actively-maintained implementation with built-in Treesitter, LSP semantic-token, and common-plugin highlight groups. Loaded with `priority = 1000, lazy = false` so it's active before any other UI plugin renders.
- Config:
  ```lua
  vim.g.everforest_background = "hard"
  vim.o.background = "dark"
  vim.g.everforest_enable_italic = 1
  vim.cmd.colorscheme("everforest")
  ```
- "Hard" chosen as the closest built-in contrast level to the desktop's `#1e2326` terminal background (official hard bg0 is `#272e33`; no built-in variant is a pixel-exact match).
- Static choice — no coupling to Noctalia/matugen. If the desktop theme changes later, this file is a one-line edit.

## 4. Editor Basics

- `nvim-treesitter`: parsers for `c_sharp`, `lua`, plus other commonly-needed languages (bash, json, markdown, yaml) for syntax highlighting/indent.
- `telescope.nvim` + `telescope-fzf-native.nvim`: fuzzy file/grep finding. Also used as the LSP definitions/references picker — `gd`/`gr` jump directly on a single result, open a picker on multiple.
- `neo-tree.nvim`: file tree sidebar.
- `lualine.nvim`: statusline, themed to match `everforest`.

## 5. Completion

`nvim-cmp` + `cmp-nvim-lsp` + `luasnip` + `cmp_luasnip` (+ `friendly-snippets` for baseline snippets). Standard setup, backend-agnostic — works with Roslyn like any other LSP source.

## 6. C# Language Stack

- **LSP:** `roslyn.nvim` (seblj/roslyn.nvim), which drives Microsoft's actual Roslyn language server (`Microsoft.CodeAnalysis.LanguageServer`) — the same engine behind VS/VS Code. The binary is fetched through Mason's `roslyn` package.
- **Inlay hints:** enabled through Roslyn's LSP settings (parameter-name hints + inferred-type hints), turned on globally via `vim.lsp.inlay_hint.enable(true)` on `LspAttach`, with `<leader>th` to toggle them off if visually noisy.
- **Param hints (signature help):** `lsp_signature.nvim`, configured to pop up automatically while typing inside a call's parentheses, highlighting the active parameter.
- **Definition/hover:**
  - `K` → `vim.lsp.buf.hover()` — floating window with the symbol's signature/docs.
  - `gd` → go-to-definition (Telescope picker on ambiguous results).
- **Diagnostics:** native `vim.diagnostic`, populated by Roslyn's built-in analyzers — virtual text inline, gutter signs, `<leader>e` for a floating detail view, `[d`/`]d` to jump between them. No separate linter process; this was an explicit scope decision (C# doesn't have a standalone linter the way JS/Python do — diagnostics come from the compiler/analyzer layer inside the LSP itself).

## 7. Keymaps

Set on `LspAttach` (only active in buffers with a running LSP):

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gr` | References |
| `K` | Hover |
| `<leader>rn` | Rename |
| `<leader>ca` | Code action |
| `<leader>e` | Line diagnostics (float) |
| `[d` / `]d` | Prev/next diagnostic |
| `<leader>th` | Toggle inlay hints |

## 8. Verification Plan

1. Install system packages.
2. Launch `nvim`; let `lazy.nvim` sync plugins and Mason install the `roslyn` package.
3. Create a scratch `.csproj` + `.cs` file (e.g. `~/scratch/CsTest/`).
4. Confirm against a real Roslyn session: hover, go-to-definition, inlay hints, signature help while typing a call, and at least one intentional diagnostic (e.g. unused variable) surfacing correctly.
5. Confirm `everforest` renders and Treesitter highlighting is active for `.cs` files.

## Out of Scope

- Debugging (DAP) integration — not requested; can be added later as an additive `lua/plugins/dap.lua` if needed.
- Formatting-on-save / `dotnet format` integration — explicitly declined; diagnostics-only for now.
- Dynamic Noctalia/matugen color sync — explicitly declined in favor of a static `everforest` plugin.
