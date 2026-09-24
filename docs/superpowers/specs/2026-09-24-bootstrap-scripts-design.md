# Cross-Platform Bootstrap Scripts — Design

## Goal

Two standalone scripts that fully replicate the C# Neovim setup (from `docs/superpowers/specs/2026-09-24-csharp-nvim-config-design.md`) on a fresh Linux or Windows machine: install every prerequisite, clone this config repo into place, and sync plugins/LSP so Neovim is immediately usable for C# development.

## Context

- The config repo (`~/.config/nvim`) currently has no remote — the user will push it to a git host and provide the URL later. The scripts must not hardcode a URL; they must accept it as a parameter.
- The current config was built and verified only on CachyOS (Arch). Windows needs one real code change (below) to work at all.
- No CI/test harness for shell/PowerShell scripts exists in this repo — verification is manual, run against real machines when available, and via careful reasoning/dry-run inspection otherwise.

## Scope

Two scripts, each self-contained and independently runnable:
- `scripts/bootstrap-linux.sh` (bash) — Arch/CachyOS, Debian/Ubuntu, Fedora.
- `scripts/bootstrap-windows.ps1` (PowerShell) — winget-based.

Neither script embeds the Neovim config content itself — both `git clone`/`git pull` it from a URL supplied by the user. Installing the *prerequisites* (Neovim, .NET SDK, git, ripgrep, fd, a compiler, tree-sitter-cli) is scripted per-OS using the verified package names/methods below.

## Repository URL Parameterization

Both scripts resolve the config repo URL in this order:
1. A positional script argument, if given.
2. The `NVIM_CONFIG_REPO` environment variable, if set.
3. A placeholder variable near the top of the script (`NVIM_CONFIG_REPO_DEFAULT` in bash, `$DefaultRepo` in PowerShell) — initially empty, meant to be filled in once the user creates the remote, at which point the script needs no argument at all for routine reruns.

If none of the three resolve to a non-empty value, the script exits immediately with a clear error message (not a confusing git failure) — e.g. "No config repo URL given. Pass it as an argument, set NVIM_CONFIG_REPO, or edit the placeholder in this script."

## Help Sections

- **Linux**: `-h`/`--help` prints: script purpose, usage line, the three ways to supply the repo URL (in precedence order), and one example invocation. Any other unrecognized flag also triggers the help text and a non-zero exit.
- **Windows**: standard PowerShell comment-based help block (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER RepoUrl`, `.EXAMPLE`) at the top of the file, so `Get-Help .\bootstrap-windows.ps1 -Full` and `-?` work natively. An explicit `-Help` switch parameter also prints the same content for discoverability, in case a user doesn't know about `Get-Help`/`-?`.

## Linux Script (`bootstrap-linux.sh`)

**Distro detection**: read `/etc/os-release`, branch on `ID`/`ID_LIKE` into `arch`, `debian`/`ubuntu`, or `fedora`. Unknown distros print a clear "unsupported distro" error and exit — no silent best-effort attempt.

**Prerequisite installation**, per distro (all package names/methods verified against current sources on 2026-09-24):

| Tool | Arch/CachyOS | Fedora | Debian/Ubuntu |
|---|---|---|---|
| Neovim (≥0.12.0) | `pacman -S neovim` | `dnf install neovim`, then verify version; if too old (Fedora ≤43) fall back to GitHub release tarball | Always GitHub release tarball (`nvim-linux-x86_64.tar.gz`) — apt's version is always too old |
| .NET SDK 10 | `pacman -S dotnet-sdk` | `dnf install dotnet-sdk-10.0` | `apt install dotnet-sdk-10.0` (works on 24.04+/25.04+); on failure fall back to Microsoft's `dotnet-install.sh --channel 10.0` |
| git | `pacman -S git` | `dnf install git` | `apt install git` |
| ripgrep | `pacman -S ripgrep` | `dnf install ripgrep` | `apt install ripgrep` |
| fd | `pacman -S fd` | `dnf install fd-find` (binary is already named `fd`) | `apt install fd-find` (binary is `fdfind`) + symlink `~/.local/bin/fd -> fdfind` |
| unzip | `pacman -S unzip` | `dnf install unzip` | `apt install unzip` |
| C compiler + make | `pacman -S base-devel` | `dnf group install "Development Tools"` | `apt install build-essential` |
| tree-sitter-cli (≥0.26.1) | `pacman -S tree-sitter-cli` | `dnf install tree-sitter-cli`, then verify version; if too old (Fedora ≤43) fall back to prebuilt binary | Always prebuilt binary (`tree-sitter-cli-linux-x64.zip` from GitHub releases) — not in apt |

Direct-download fallbacks (Neovim tarball, tree-sitter-cli zip) install into `~/.local` and add `~/.local/bin` to PATH in the current shell session (and note that the user's shell rc file should already have `~/.local/bin` on PATH, or the script appends it if missing).

**Config deployment**: resolve the repo URL (see above). If `~/.config/nvim/.git` exists and its `origin` remote matches the resolved URL, run `git -C ~/.config/nvim pull`. Otherwise, if `~/.config/nvim` exists at all (git repo or not), rename it to `~/.config/nvim.bak.<unix-timestamp>` first. Then `git clone <url> ~/.config/nvim`.

**Sync**: `nvim --headless "+Lazy! sync" +qa`, `nvim --headless -c "MasonInstall roslyn" -c "qa"`, `nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa"`.

**Output**: a final summary of what was installed/skipped/backed-up, and the one remaining manual step (opening a real `.cs` file to confirm).

## Windows Script (`bootstrap-windows.ps1`)

**Prerequisite installation via winget** (verified package IDs, 2026-09-24):

| Tool | winget ID |
|---|---|
| Neovim | `Neovim.Neovim` |
| .NET SDK 10 | `Microsoft.DotNet.SDK.10` |
| git | `Git.Git` (explicit `-e --id` to avoid the `Microsoft.Git` naming collision) |
| ripgrep | `BurntSushi.ripgrep.MSVC` |
| fd | `sharkdp.fd` |
| tree-sitter-cli | `tree-sitter.tree-sitter-cli` |
| C++ compiler | `Microsoft.VisualStudio.2022.BuildTools` with the VCTools workload override |
| CMake | `Kitware.CMake` |

Each `winget install` uses `--accept-package-agreements --accept-source-agreements` for non-interactive runs, and treats "already installed" as success (winget's own exit code for that case), not a failure.

**PATH refresh**: after installs, re-read `PATH` from both `HKLM` and `HKCU` registry environment keys and merge into `$env:PATH` for the current process — otherwise the same script session won't see newly-installed binaries.

**Config deployment**: same clone/pull/backup logic as Linux, targeting `$env:LOCALAPPDATA\nvim`.

**Sync**: identical three headless commands as Linux.

## Required Code Change: `lua/plugins/telescope.lua`

`telescope-fzf-native.nvim`'s build step is hardcoded to `build = "make"`, which doesn't exist on Windows. Per the plugin's own README, the Windows-supported build is a CMake invocation. Fix:

```lua
{
  "nvim-telescope/telescope-fzf-native.nvim",
  build = vim.fn.has("win32") == 1
      and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install"
    or "make",
},
```

This lands in the actual repo now (not just the bootstrap scripts), since the scripts will simply clone whatever is there.

## Safety

- Never overwrite an existing `~/.config/nvim` (or `$env:LOCALAPPDATA\nvim`) without backing it up first, unless it's already tracking the same remote (then `pull`, not overwrite).
- No destructive `git` operations (no `--force`, no `reset --hard`) anywhere in either script.
- Both scripts are safe to re-run (idempotent): re-running after a successful run should just `pull` and re-sync, not re-clone or re-back-up.

## Out of Scope

- No CI/automated test harness for these scripts themselves (no test runner for bash/PowerShell in this repo).
- No creation of the `~/scratch/CsTest` verification project — that was a one-time development-time check, not part of routine bootstrapping.
- No support for distros/package managers beyond Arch, Debian/Ubuntu, and Fedora.
- No handling of Neovim on macOS (not requested).

## Verification Plan

Since there's no CI and no second physical Linux/Windows machine available in this session:
1. Syntax-check both scripts (`bash -n` for the Linux script; `powershell -NoProfile -Command "Get-Command -Syntax"` or a PSScriptAnalyzer pass, if available, for the Windows one — otherwise careful manual read for balanced quotes/braces).
2. Dry-run the distro-detection and URL-resolution logic in isolation (these don't require installing anything) to confirm branching is correct.
3. Manually trace each per-distro install path against the verified package table above.
4. Full end-to-end execution is deferred until the user has pushed the repo and has (or can access) a real Linux/Windows machine to run it on.
