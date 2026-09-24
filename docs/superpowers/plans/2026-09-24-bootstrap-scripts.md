# Cross-Platform Bootstrap Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two standalone scripts (`scripts/bootstrap-linux.sh`, `scripts/bootstrap-windows.ps1`) that install every prerequisite and deploy this Neovim config from a git remote on a fresh Linux (Arch/Debian/Fedora) or Windows machine.

**Architecture:** Each script resolves a repo URL (arg → env var → in-script placeholder), installs OS-specific prerequisites, clones-or-pulls the config into place (backing up any conflicting existing config), then runs the same three headless Neovim sync commands used throughout this project's own development. The Linux script's distro-detection and GitHub-fallback-download logic is written to be unit-testable in isolation (parameterized, sourceable without side effects) since there's no CI and only one of the three target distros is available to test against directly.

**Tech Stack:** bash (`set -euo pipefail`), PowerShell, git, curl, winget.

## Global Constraints

- Config repo URL resolution order (both scripts): (1) script argument, (2) `NVIM_CONFIG_REPO` env var, (3) an in-script placeholder variable (`NVIM_CONFIG_REPO_DEFAULT` in bash, `$DefaultRepo` in PowerShell), initially empty. Empty after all three → exit with a clear error, not a git failure.
- Both scripts must be idempotent: rerunning after a successful run should `pull`, not re-clone or re-backup. An existing config directory is only backed up (`<dir>.bak.<timestamp>`) when it does NOT already track the resolved repo URL.
- No destructive git operations anywhere (no `--force`, no `reset --hard`).
- Config directory resolution respects `XDG_CONFIG_HOME` when set (both scripts), falling back to `~/.config/nvim` (Linux) / `$env:LOCALAPPDATA\nvim` (Windows) — this also lets tests isolate a run without touching the real config.
- Verified package/method table (Linux), exact values, 2026-09-24:

  | Tool | Arch/CachyOS | Fedora | Debian/Ubuntu |
  |---|---|---|---|
  | Neovim ≥0.12.0 | `pacman -S neovim` | `dnf install neovim` + version check, fallback to GitHub tarball if <0.12 | Always GitHub tarball `nvim-linux-x86_64.tar.gz` |
  | .NET SDK 10 | `pacman -S dotnet-sdk` | `dnf install dotnet-sdk-10.0` | `apt install dotnet-sdk-10.0`, fallback to `dotnet-install.sh --channel 10.0` |
  | git | `pacman -S git` | `dnf install git` | `apt install git` |
  | ripgrep | `pacman -S ripgrep` | `dnf install ripgrep` | `apt install ripgrep` |
  | fd | `pacman -S fd` | `dnf install fd-find` (binary already `fd`) | `apt install fd-find` (binary `fdfind`) + symlink to `fd` |
  | unzip | `pacman -S unzip` | `dnf install unzip` | `apt install unzip` |
  | compiler+make | `pacman -S base-devel` | `dnf group install "Development Tools"` (fallback `dnf install @development-tools`) | `apt install build-essential` |
  | tree-sitter-cli ≥0.26.1 | `pacman -S tree-sitter-cli` | `dnf install tree-sitter-cli` + version check, fallback to GitHub zip if <0.26.1 | Always GitHub zip `tree-sitter-cli-linux-x64.zip` |

- Verified winget package IDs (Windows), exact values, 2026-09-24: `Neovim.Neovim`, `Microsoft.DotNet.SDK.10`, `Git.Git` (explicit `-e --id` to avoid the `Microsoft.Git` collision), `BurntSushi.ripgrep.MSVC`, `sharkdp.fd`, `tree-sitter.tree-sitter-cli`, `Kitware.CMake`, `Microsoft.VisualStudio.2022.BuildTools` with `--override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`.
- GitHub release URLs (exact, verified 2026-09-24): Neovim Linux x86_64 = `https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz`; tree-sitter-cli Linux x64 = `https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-cli-linux-x64.zip`; Microsoft's install script = `https://dot.net/v1/dotnet-install.sh`.
- `lua/plugins/telescope.lua`'s `telescope-fzf-native.nvim` build command must branch on `vim.fn.has("win32")`: `"make"` on Unix, the documented CMake invocation on Windows (exact string in Task 1).

---

### Task 1: Cross-platform build command for telescope-fzf-native

**Files:**
- Modify: `lua/plugins/telescope.lua:6`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — this is a self-contained one-line fix. No other task depends on it.

- [ ] **Step 1: Edit the build command**

Change line 6 from:
```lua
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
```
to:
```lua
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = vim.fn.has("win32") == 1
            and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install"
          or "make",
      },
```

- [ ] **Step 2: Verify Lua syntax and that the Linux branch is unaffected**

```bash
nvim --headless -c "lua dofile('lua/plugins/telescope.lua')" -c "qa" 2>&1
nvim --headless -c "lua local spec = dofile('lua/plugins/telescope.lua'); print(spec[1].dependencies[2].build)" -c "qa" 2>&1
```

Expected: no errors from the first command; the second prints `make` (since `vim.fn.has("win32")` is `0` on this Linux machine, confirming the conditional correctly falls through to the Unix branch).

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add lua/plugins/telescope.lua
git commit -m "Make telescope-fzf-native build command cross-platform"
```

---

### Task 2: Linux bootstrap script — skeleton, help, distro detection, config deployment, and download-based fallback installers

**Files:**
- Create: `scripts/bootstrap-linux.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the functions `print_help`, `resolve_repo_url`, `detect_distro`, `install_nvim_from_github`, `ensure_nvim_min_version`, `install_tree_sitter_cli_from_github`, `ensure_tree_sitter_cli_min_version`, `deploy_config`, `sync_plugins`, and the `main` entrypoint. **Tasks 3, 4, and 5 each replace exactly one of three stub functions** (`install_arch`, `install_fedora`, `install_debian`) that this task defines with a deterministic "not implemented" body — no other part of this file changes in those later tasks.
- The script is written with `source "${BASH_SOURCE[0]}" != "$0"` guard so later tasks (and this task's own tests) can `source` it to test individual functions without triggering a full run.

- [ ] **Step 1: Create `scripts/bootstrap-linux.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# bootstrap-linux.sh — install prerequisites and deploy the C# Neovim config
# on Arch/CachyOS, Debian/Ubuntu, or Fedora.
# ---------------------------------------------------------------------------

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
NVIM_CONFIG_REPO_DEFAULT=""   # fill in once the config repo has a remote
LOCAL_BIN="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

print_help() {
  cat <<EOF
${SCRIPT_NAME} — bootstrap the C# Neovim config on Arch/CachyOS, Debian/Ubuntu, or Fedora.

Usage:
  ${SCRIPT_NAME} [REPO_URL]

The config repo URL is resolved in this order:
  1. The REPO_URL argument, if given.
  2. The NVIM_CONFIG_REPO environment variable, if set.
  3. The NVIM_CONFIG_REPO_DEFAULT placeholder near the top of this script.

Examples:
  ${SCRIPT_NAME} git@github.com:youruser/nvim-config.git
  NVIM_CONFIG_REPO=git@github.com:youruser/nvim-config.git ${SCRIPT_NAME}
EOF
}

resolve_repo_url() {
  local arg_url="${1:-}"
  if [[ -n "$arg_url" ]]; then
    echo "$arg_url"
  elif [[ -n "${NVIM_CONFIG_REPO:-}" ]]; then
    echo "$NVIM_CONFIG_REPO"
  else
    echo "$NVIM_CONFIG_REPO_DEFAULT"
  fi
}

detect_distro() {
  local os_release_file="${1:-/etc/os-release}"
  if [[ ! -f "$os_release_file" ]]; then
    echo "unknown"
    return
  fi
  local id="" id_like=""
  # shellcheck disable=SC1090
  source "$os_release_file"
  id="${ID:-}"
  id_like="${ID_LIKE:-}"
  case "$id $id_like" in
    *arch*) echo "arch" ;;
    *fedora*) echo "fedora" ;;
    *debian*|*ubuntu*) echo "debian" ;;
    *) echo "unknown" ;;
  esac
}

install_nvim_from_github() {
  local install_root="${1:-$HOME/.local}"
  local bin_dir="${2:-$LOCAL_BIN}"
  echo "==> Installing Neovim from GitHub release into $install_root..."
  mkdir -p "$install_root" "$bin_dir"
  local tmp_tarball
  tmp_tarball="$(mktemp)"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" -o "$tmp_tarball"
  tar -C "$install_root" -xzf "$tmp_tarball"
  rm -f "$tmp_tarball"
  ln -sf "$install_root/nvim-linux-x86_64/bin/nvim" "$bin_dir/nvim"
}

ensure_nvim_min_version() {
  local bin_dir="${1:-$LOCAL_BIN}"
  local version major minor
  version="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
  major="$(echo "$version" | cut -d. -f1)"
  minor="$(echo "$version" | cut -d. -f2)"
  if (( major == 0 && minor < 12 )); then
    echo "==> System Neovim ($version) is older than 0.12, installing from GitHub instead"
    install_nvim_from_github "$HOME/.local" "$bin_dir"
  fi
}

install_tree_sitter_cli_from_github() {
  local bin_dir="${1:-$LOCAL_BIN}"
  echo "==> Installing tree-sitter-cli from GitHub release into $bin_dir..."
  mkdir -p "$bin_dir"
  local tmp_zip
  tmp_zip="$(mktemp).zip"
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-cli-linux-x64.zip" -o "$tmp_zip"
  unzip -o "$tmp_zip" -d "$bin_dir"
  rm -f "$tmp_zip"
  chmod +x "$bin_dir/tree-sitter"
}

ensure_tree_sitter_cli_min_version() {
  local bin_dir="${1:-$LOCAL_BIN}"
  local version major minor
  version="$(tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
  major="$(echo "$version" | cut -d. -f1)"
  minor="$(echo "$version" | cut -d. -f2)"
  if (( major == 0 && minor < 26 )); then
    echo "==> System tree-sitter-cli ($version) is older than 0.26.1, installing from GitHub instead"
    install_tree_sitter_cli_from_github "$bin_dir"
  fi
}

deploy_config() {
  local repo_url="$1"
  local target_dir="${2:-$CONFIG_DIR}"

  if [[ -d "$target_dir/.git" ]]; then
    local current_origin
    current_origin="$(git -C "$target_dir" remote get-url origin 2>/dev/null || echo "")"
    if [[ "$current_origin" == "$repo_url" ]]; then
      echo "==> Existing config at $target_dir already tracks $repo_url, pulling latest..."
      git -C "$target_dir" pull
      return
    fi
  fi

  if [[ -e "$target_dir" ]]; then
    local backup
    backup="${target_dir}.bak.$(date +%s)"
    echo "==> Backing up existing config to $backup"
    mv "$target_dir" "$backup"
  fi

  echo "==> Cloning $repo_url into $target_dir"
  git clone "$repo_url" "$target_dir"
}

sync_plugins() {
  echo "==> Syncing plugins..."
  nvim --headless "+Lazy! sync" +qa
  echo "==> Installing Roslyn via Mason..."
  nvim --headless -c "MasonInstall roslyn" -c "qa"
  echo "==> Installing C# treesitter parser..."
  nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa"
}

install_arch() {
  echo "ERROR: install_arch not yet implemented" >&2
  exit 1
}

install_fedora() {
  echo "ERROR: install_fedora not yet implemented" >&2
  exit 1
}

install_debian() {
  echo "ERROR: install_debian not yet implemented" >&2
  exit 1
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_help
    exit 0
  fi

  local repo_url
  repo_url="$(resolve_repo_url "${1:-}")"
  if [[ -z "$repo_url" ]]; then
    echo "ERROR: No config repo URL given. Pass it as an argument, set NVIM_CONFIG_REPO, or edit NVIM_CONFIG_REPO_DEFAULT in this script." >&2
    print_help
    exit 1
  fi

  local distro
  distro="$(detect_distro)"
  case "$distro" in
    arch) install_arch ;;
    fedora) install_fedora ;;
    debian) install_debian ;;
    *)
      echo "ERROR: Unsupported or undetected Linux distro. This script supports Arch/CachyOS, Fedora, and Debian/Ubuntu." >&2
      exit 1
      ;;
  esac

  export PATH="$LOCAL_BIN:$PATH"

  deploy_config "$repo_url"
  sync_plugins

  echo ""
  echo "==> Done. Open a .cs file in nvim to verify (e.g. nvim path/to/file.cs)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/bootstrap-linux.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/bootstrap-linux.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Test `--help` and argument-less error path**

```bash
./scripts/bootstrap-linux.sh --help
echo "exit: $?"
./scripts/bootstrap-linux.sh 2>&1; echo "exit: $?"
```

Expected: `--help` prints the usage text and exits 0. The no-argument run prints the "No config repo URL given" error (since `NVIM_CONFIG_REPO_DEFAULT` is empty) and exits 1.

- [ ] **Step 5: Test `resolve_repo_url` precedence in isolation**

```bash
source scripts/bootstrap-linux.sh   # the source-guard prevents main from running

result="$(resolve_repo_url "https://example.com/arg.git")"
[[ "$result" == "https://example.com/arg.git" ]] && echo "PASS: arg wins" || echo "FAIL: got $result"

result="$(NVIM_CONFIG_REPO="https://example.com/env.git" resolve_repo_url "")"
[[ "$result" == "https://example.com/env.git" ]] && echo "PASS: env wins over default" || echo "FAIL: got $result"

result="$(resolve_repo_url "")"
[[ "$result" == "" ]] && echo "PASS: empty when nothing set" || echo "FAIL: got $result"
```

Expected: all three print `PASS`.

- [ ] **Step 6: Test `detect_distro` against fixture files**

```bash
tmp_os_release="$(mktemp)"

printf 'ID=arch\n' > "$tmp_os_release"
result="$(detect_distro "$tmp_os_release")"
[[ "$result" == "arch" ]] && echo "PASS: arch" || echo "FAIL: got $result"

printf 'ID=fedora\n' > "$tmp_os_release"
result="$(detect_distro "$tmp_os_release")"
[[ "$result" == "fedora" ]] && echo "PASS: fedora" || echo "FAIL: got $result"

printf 'ID=ubuntu\nID_LIKE=debian\n' > "$tmp_os_release"
result="$(detect_distro "$tmp_os_release")"
[[ "$result" == "debian" ]] && echo "PASS: debian (ubuntu via ID_LIKE)" || echo "FAIL: got $result"

printf 'ID=debian\n' > "$tmp_os_release"
result="$(detect_distro "$tmp_os_release")"
[[ "$result" == "debian" ]] && echo "PASS: debian (direct)" || echo "FAIL: got $result"

rm -f "$tmp_os_release"
result="$(detect_distro "/etc/os-release")"
echo "This machine's real detection: $result"
```

Expected: four `PASS` lines, and the real-machine check prints `arch` (this is a CachyOS/Arch machine).

- [ ] **Step 7: Test the GitHub-fallback installers for real, in isolated temp directories**

```bash
tmp_install_root="$(mktemp -d)"
tmp_bin_dir="$(mktemp -d)"
install_nvim_from_github "$tmp_install_root" "$tmp_bin_dir"
"$tmp_bin_dir/nvim" --version | head -1
rm -rf "$tmp_install_root" "$tmp_bin_dir"

tmp_bin_dir2="$(mktemp -d)"
install_tree_sitter_cli_from_github "$tmp_bin_dir2"
"$tmp_bin_dir2/tree-sitter" --version
rm -rf "$tmp_bin_dir2"
```

Expected: the nvim command prints `NVIM v0.12.x` or higher (no local system files touched — everything happened in the temp dirs); the tree-sitter command prints a version `0.26.x` or higher.

- [ ] **Step 8: Test `deploy_config`'s three real scenarios against a throwaway local repo**

```bash
tmp_remote="$(mktemp -d)"
git clone --bare "$PWD" "$tmp_remote/repo.git" >/dev/null 2>&1
tmp_target="$(mktemp -d)/nvim"

# Scenario 1: fresh clone (target doesn't exist yet)
deploy_config "file://$tmp_remote/repo.git" "$tmp_target"
[[ -d "$tmp_target/.git" ]] && echo "PASS: cloned" || echo "FAIL: no .git in target"

# Scenario 2: already tracking the same remote -> pull, no backup created
deploy_config "file://$tmp_remote/repo.git" "$tmp_target"
ls "${tmp_target}".bak.* 2>/dev/null && echo "FAIL: unexpected backup created" || echo "PASS: no backup on matching pull"

# Scenario 3: existing dir NOT tracking this remote -> backup then clone
rm -rf "$tmp_target/.git"
git init -q "$tmp_target"
deploy_config "file://$tmp_remote/repo.git" "$tmp_target"
ls -d "${tmp_target}".bak.* >/dev/null 2>&1 && echo "PASS: backup created for mismatched remote" || echo "FAIL: no backup created"
[[ -d "$tmp_target/.git" ]] && echo "PASS: re-cloned after backup" || echo "FAIL: target missing after backup+clone"

rm -rf "$tmp_remote" "$tmp_target" "${tmp_target}".bak.* 2>/dev/null
```

Expected: five `PASS` lines total across the three scenarios.

- [ ] **Step 9: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-linux.sh
git commit -m "Add Linux bootstrap script skeleton with tested distro detection and config deployment"
```

---

### Task 3: Arch/CachyOS install implementation

**Files:**
- Modify: `scripts/bootstrap-linux.sh` (the `install_arch` function body only)

**Interfaces:**
- Consumes: the `install_arch` stub from Task 2 (same function name/signature — no arguments, no return value, called from `main`).
- Produces: nothing new for later tasks — Tasks 4 and 5 are independent siblings, not consumers of this one.

This exact `pacman` command (with the same package list) was already run successfully multiple times during this machine's own C# Neovim setup earlier in this project — `neovim`, `dotnet-sdk`, `git`, `ripgrep`, `fd`, `unzip`, and `tree-sitter-cli` are all confirmed installed and working on this machine right now, and `base-devel` is the standard Arch group providing `gcc`/`make` (already present on this machine, confirmed via `which gcc cc` during that earlier work).

- [ ] **Step 1: Replace the `install_arch` stub**

```bash
install_arch() {
  echo "==> Installing prerequisites via pacman..."
  sudo pacman -S --needed --noconfirm \
    neovim dotnet-sdk git ripgrep fd unzip tree-sitter-cli base-devel
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n scripts/bootstrap-linux.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Verify by inspection against prior evidence**

Confirm the package list (`neovim dotnet-sdk git ripgrep fd unzip tree-sitter-cli base-devel`) is character-for-character the same as the commands already run successfully on this machine (Task 1 of the original C# config plan installed `neovim dotnet-sdk git ripgrep fd unzip`, and `tree-sitter-cli` was added separately during that plan's Task 4). `base-devel` is added here because it wasn't needed as a separate install then (gcc/make were already present) but is the correct group to request on a genuinely fresh Arch machine.

- [ ] **Step 4 (optional, requires your sudo password): run the real installer**

This step needs an interactive terminal and cannot be run by an automated agent. If you want to double-check it end-to-end yourself:

```bash
./scripts/bootstrap-linux.sh --help   # sanity check first
```

Since every package is already installed on this machine, running `install_arch` for real would be a safe no-op (`--needed` skips anything already present) — this is optional and not required to consider this task complete, since the command is already proven.

- [ ] **Step 5: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-linux.sh
git commit -m "Implement Arch/CachyOS prerequisite installation"
```

---

### Task 4: Fedora install implementation

**Files:**
- Modify: `scripts/bootstrap-linux.sh` (the `install_fedora` function body only)

**Interfaces:**
- Consumes: the `install_fedora` stub from Task 2; the `ensure_nvim_min_version` and `ensure_tree_sitter_cli_min_version` functions from Task 2 (called with no arguments, using their defaults).
- Produces: nothing new for later tasks.

No Fedora machine is available to execute this against — verification is `bash -n` plus careful manual tracing against the researched package table (Global Constraints above). Fedora 44/45 ship Neovim 0.12.5 and tree-sitter-cli 0.26.11 (both satisfy the version floors), so the fallback branches only trigger on Fedora ≤43.

- [ ] **Step 1: Replace the `install_fedora` stub**

```bash
install_fedora() {
  echo "==> Installing prerequisites via dnf..."
  sudo dnf install -y neovim git ripgrep fd-find unzip dotnet-sdk-10.0 tree-sitter-cli
  sudo dnf group install -y "Development Tools" || sudo dnf install -y @development-tools

  ensure_nvim_min_version
  ensure_tree_sitter_cli_min_version
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n scripts/bootstrap-linux.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Manual trace against the verified table**

Confirm each line against the Global Constraints table: `neovim`/`git`/`ripgrep`/`unzip`/`dotnet-sdk-10.0`/`tree-sitter-cli` are all real dnf package names (verified 2026-09-24); `fd-find` on Fedora installs a binary already named `fd` (no symlink needed, unlike Debian — confirm no symlink logic was added here); the `dnf group install` / `@development-tools` fallback pair handles both dnf5 (default since Fedora 41, no `groupinstall` alias) and older dnf4 syntax; `ensure_nvim_min_version` and `ensure_tree_sitter_cli_min_version` (both already tested for real in Task 2 against temp directories) correctly cover the Fedora ≤43 case without needing Fedora-specific fallback code of their own.

- [ ] **Step 4: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-linux.sh
git commit -m "Implement Fedora prerequisite installation"
```

---

### Task 5: Debian/Ubuntu install implementation

**Files:**
- Modify: `scripts/bootstrap-linux.sh` (the `install_debian` function body only)

**Interfaces:**
- Consumes: the `install_debian` stub from Task 2; `install_nvim_from_github` and `install_tree_sitter_cli_from_github` from Task 2 (already real-tested against temp directories in Task 2 Step 7 — called here unconditionally, not just as a fallback, since apt never has a modern-enough Neovim or any tree-sitter-cli package at all).
- Produces: nothing new for later tasks.

No Debian/Ubuntu machine is available to execute this against — verification is `bash -n` plus manual trace. The two GitHub-fallback installer functions this calls were already proven to work for real in Task 2; only the apt-specific commands and the `fdfind`→`fd` symlink are unverified by execution here.

- [ ] **Step 1: Replace the `install_debian` stub**

```bash
install_debian() {
  echo "==> Installing prerequisites via apt..."
  sudo apt-get update
  sudo apt-get install -y git ripgrep fd-find unzip build-essential

  mkdir -p "$LOCAL_BIN"
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
  fi

  if ! sudo apt-get install -y dotnet-sdk-10.0; then
    echo "==> apt's dotnet-sdk-10.0 unavailable, falling back to dotnet-install.sh"
    local tmp_installer
    tmp_installer="$(mktemp)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp_installer"
    bash "$tmp_installer" --channel 10.0 --install-dir "$HOME/.dotnet"
    rm -f "$tmp_installer"
    export PATH="$HOME/.dotnet:$PATH"
    if ! grep -q '.dotnet' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.dotnet:$PATH"' >> "$HOME/.bashrc"
    fi
  fi

  install_nvim_from_github
  install_tree_sitter_cli_from_github
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n scripts/bootstrap-linux.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Manual trace against the verified table**

Confirm: `git`/`ripgrep`/`fd-find`/`unzip`/`build-essential` are real apt package names (2026-09-24); the `fdfind`→`fd` symlink only runs if `fdfind` exists and `fd` doesn't, matching Debian/Ubuntu's actual naming clash (confirmed different from Fedora, which needs no symlink — see Task 4); the `apt-get install -y dotnet-sdk-10.0` / `dotnet-install.sh` fallback pair matches Microsoft's current guidance (native package works on Ubuntu 24.04+/25.04+, script fallback for older/unknown versions); `install_nvim_from_github` and `install_tree_sitter_cli_from_github` are called unconditionally (not behind a version check) since apt never has a suitable version of either on any current Debian/Ubuntu release.

- [ ] **Step 4: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-linux.sh
git commit -m "Implement Debian/Ubuntu prerequisite installation"
```

---

### Task 6: Windows bootstrap script — skeleton, help, config deployment, and PATH refresh

**Files:**
- Create: `scripts/bootstrap-windows.ps1`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the functions `Show-Help`, `Resolve-RepoUrl`, `Update-EnvPath`, `Deploy-Config`, `Sync-Plugins`, and the `Main` entrypoint, plus an `Install-Prerequisites` stub. **Task 7 replaces only the `Install-Prerequisites` function body** — no other part of this file changes.

No PowerShell interpreter is available on this development machine (confirmed: `pwsh`/`powershell` both absent). Verification for this task and Task 7 is careful manual syntax/logic review only, as anticipated in the design spec's Verification Plan — there is no way to execute-test this file in this environment.

- [ ] **Step 1: Create `scripts/bootstrap-windows.ps1`**

```powershell
<#
.SYNOPSIS
Bootstraps the C# Neovim config on Windows.

.DESCRIPTION
Installs Neovim, .NET SDK 10, git, ripgrep, fd, a C++ compiler, and CMake via
winget, then clones (or pulls) the Neovim config repo into place and syncs
plugins/LSP.

.PARAMETER RepoUrl
The git URL of the Neovim config repo. If omitted, falls back to the
NVIM_CONFIG_REPO environment variable, then to the $DefaultRepo placeholder
near the top of this script.

.PARAMETER Help
Show this help text.

.EXAMPLE
.\bootstrap-windows.ps1 https://github.com/youruser/nvim-config.git

.EXAMPLE
$env:NVIM_CONFIG_REPO = "https://github.com/youruser/nvim-config.git"
.\bootstrap-windows.ps1
#>

param(
    [Parameter(Position = 0)]
    [string]$RepoUrl,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

$DefaultRepo = ""  # fill in once the config repo has a remote
$ConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "nvim" } else { "$env:LOCALAPPDATA\nvim" }

function Show-Help {
    Get-Help $PSCommandPath -Full
}

function Resolve-RepoUrl {
    param([string]$ArgUrl)

    if ($ArgUrl) { return $ArgUrl }
    if ($env:NVIM_CONFIG_REPO) { return $env:NVIM_CONFIG_REPO }
    return $DefaultRepo
}

function Update-EnvPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Install-Prerequisites {
    throw "Install-Prerequisites not yet implemented"
}

function Deploy-Config {
    param([string]$RepoUrl, [string]$TargetDir)

    if (Test-Path (Join-Path $TargetDir ".git")) {
        $currentOrigin = (git -C $TargetDir remote get-url origin 2>$null)
        if ($currentOrigin -eq $RepoUrl) {
            Write-Host "==> Existing config at $TargetDir already tracks $RepoUrl, pulling latest..."
            git -C $TargetDir pull
            return
        }
    }

    if (Test-Path $TargetDir) {
        $backup = "$TargetDir.bak.$(Get-Date -Format yyyyMMddHHmmss)"
        Write-Host "==> Backing up existing config to $backup"
        Move-Item -Path $TargetDir -Destination $backup
    }

    Write-Host "==> Cloning $RepoUrl into $TargetDir"
    git clone $RepoUrl $TargetDir
}

function Sync-Plugins {
    Write-Host "==> Syncing plugins..."
    nvim --headless "+Lazy! sync" +qa
    Write-Host "==> Installing Roslyn via Mason..."
    nvim --headless -c "MasonInstall roslyn" -c "qa"
    Write-Host "==> Installing C# treesitter parser..."
    nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa"
}

function Main {
    if ($Help) {
        Show-Help
        return
    }

    $resolvedUrl = Resolve-RepoUrl -ArgUrl $RepoUrl
    if (-not $resolvedUrl) {
        Write-Error "No config repo URL given. Pass it as an argument, set NVIM_CONFIG_REPO, or edit `$DefaultRepo in this script."
        exit 1
    }

    Install-Prerequisites
    Update-EnvPath
    Deploy-Config -RepoUrl $resolvedUrl -TargetDir $ConfigDir
    Sync-Plugins

    Write-Host ""
    Write-Host "==> Done. Open a .cs file in nvim to verify (e.g. nvim path\to\file.cs)."
}

Main
```

- [ ] **Step 2: Manual review checklist**

Read through the file and confirm:
- Every `{`/`}` pair is balanced (count them if unsure — there should be exactly one open/close pair per function plus the `param()` block and the comment-help block's `<# #>` delimiters).
- Every string is properly quoted — note the escaped backtick before `$DefaultRepo` inside the `Write-Error` message (`` `$DefaultRepo ``), which is required so PowerShell prints the literal variable name rather than interpolating it.
- `$ConfigDir` is computed once at script scope (not inside `Main`), matching the bash script's `CONFIG_DIR` being set once at the top level.
- `Resolve-RepoUrl`'s precedence order (arg → env var → `$DefaultRepo`) matches `resolve_repo_url` in `bootstrap-linux.sh` exactly.
- `Deploy-Config`'s three branches (matching remote → pull; existing non-matching dir → backup then clone; nothing existing → clone) mirror `deploy_config` in the bash script line-for-line in behavior.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-windows.ps1
git commit -m "Add Windows bootstrap script skeleton with config deployment"
```

---

### Task 7: Windows winget install implementation

**Files:**
- Modify: `scripts/bootstrap-windows.ps1` (the `Install-Prerequisites` function, and adding one new helper function `Install-Prerequisite` above it)

**Interfaces:**
- Consumes: the `Install-Prerequisites` stub from Task 6, called with no arguments from `Main`.
- Produces: nothing new for later tasks — this is the last task in the plan.

As in Task 6, no PowerShell interpreter is available to execute this — verification is manual review against the verified winget package table in Global Constraints. Rather than rely on a specific winget exit code for "already installed" (winget's own exit codes for this case are inconsistently documented and have open bug reports against them), this checks actual installed state via `winget list` afterward — more robust than trusting a magic number.

- [ ] **Step 1: Add the `Install-Prerequisite` helper and replace `Install-Prerequisites`**

Insert this function immediately before `Install-Prerequisites` in the file:

```powershell
function Install-Prerequisite {
    param(
        [string]$Id,
        [string[]]$ExtraArgs = @()
    )
    Write-Host "==> Installing $Id via winget..."
    $installArgs = @("install", "--id", $Id, "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements") + $ExtraArgs
    & winget @installArgs
    $installExit = $LASTEXITCODE

    if ($installExit -ne 0) {
        $listResult = & winget list --id $Id --source winget 2>$null
        if ($LASTEXITCODE -ne 0 -or -not ($listResult -match [regex]::Escape($Id))) {
            throw "winget install of $Id failed (exit $installExit) and it is not already installed."
        }
        Write-Host "==> $Id is already installed, continuing."
    }
}
```

Then replace the `Install-Prerequisites` stub body with:

```powershell
function Install-Prerequisites {
    Install-Prerequisite -Id "Neovim.Neovim"
    Install-Prerequisite -Id "Microsoft.DotNet.SDK.10"
    Install-Prerequisite -Id "Git.Git"
    Install-Prerequisite -Id "BurntSushi.ripgrep.MSVC"
    Install-Prerequisite -Id "sharkdp.fd"
    Install-Prerequisite -Id "tree-sitter.tree-sitter-cli"
    Install-Prerequisite -Id "Kitware.CMake"
    Install-Prerequisite -Id "Microsoft.VisualStudio.2022.BuildTools" -ExtraArgs @(
        "--override", "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    )
}
```

- [ ] **Step 2: Manual review checklist**

Confirm against the Global Constraints winget table: all 8 package IDs are typed exactly as verified (`Neovim.Neovim`, `Microsoft.DotNet.SDK.10`, `Git.Git`, `BurntSushi.ripgrep.MSVC`, `sharkdp.fd`, `tree-sitter.tree-sitter-cli`, `Kitware.CMake`, `Microsoft.VisualStudio.2022.BuildTools`); the `Git.Git` install uses `-e --id` (via `Install-Prerequisite`'s fixed `-e` flag) to avoid ambiguity with the separate `Microsoft.Git` package; the BuildTools call's `--override` string matches exactly (including the `--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended` value verified earlier); `Install-Prerequisite` checks real installed state via `winget list` rather than a hardcoded exit code.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/nvim
git add scripts/bootstrap-windows.ps1
git commit -m "Implement Windows prerequisite installation via winget"
```

---

## Plan Self-Review Notes

- **Spec coverage:** telescope.lua cross-platform fix → Task 1; Linux distro detection/help/URL resolution/config deployment/download fallbacks → Task 2; Arch/Fedora/Debian install logic → Tasks 3/4/5; Windows skeleton/help/config deployment → Task 6; Windows winget installs → Task 7. All sections of the design spec are covered.
- **Testability gap, disclosed honestly:** Tasks 4, 5, 6, and 7 cannot be executed in this environment (no Fedora/Debian/Windows machine, no PowerShell interpreter here) — their verification is `bash -n` (where applicable) plus deliberate manual tracing against package names/methods that were independently verified via research before this plan was written, not invented during implementation. Task 2's distro-detection and config-deployment logic (the parts common to every distro) and Task 3's Arch path (matching commands already proven earlier in this project) are the parts that get real execution evidence.
- **Cross-task consistency check:** `install_arch`/`install_fedora`/`install_debian` function names and zero-argument call signature are fixed in Task 2 and never change in Tasks 3-5. `Install-Prerequisites` (Windows) likewise fixed in Task 6, only its body changes in Task 7. `resolve_repo_url`/`Resolve-RepoUrl` precedence order is identical across both scripts by design.
