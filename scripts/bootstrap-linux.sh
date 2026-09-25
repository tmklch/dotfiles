#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# bootstrap-linux.sh — install prerequisites and deploy the C# Neovim config
# on Arch/CachyOS, Debian/Ubuntu, or Fedora.
# ---------------------------------------------------------------------------

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
NVIM_CONFIG_REPO_DEFAULT="git@github.com:tmklch/dotfiles.git"
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
  version="$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
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
  tmp_zip="$(mktemp --suffix=.zip)"
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-cli-linux-x64.zip" -o "$tmp_zip"
  unzip -o "$tmp_zip" -d "$bin_dir"
  rm -f "$tmp_zip"
  chmod +x "$bin_dir/tree-sitter"
}

ensure_tree_sitter_cli_min_version() {
  local bin_dir="${1:-$LOCAL_BIN}"
  local version major minor patch
  version="$(tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
  major="$(echo "$version" | cut -d. -f1)"
  minor="$(echo "$version" | cut -d. -f2)"
  patch="$(echo "$version" | cut -d. -f3)"
  if (( major == 0 && (minor < 26 || (minor == 26 && patch < 1)) )); then
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
  echo "==> Installing netcoredbg via Mason..."
  nvim --headless -c "MasonInstall netcoredbg" -c "qa"
  echo "==> Installing C# treesitter parser..."
  nvim --headless -c "lua require('nvim-treesitter').install({'c_sharp'}):wait(300000)" -c "qa"
}

install_arch() {
  echo "==> Installing prerequisites via pacman..."
  sudo pacman -S --needed --noconfirm \
    neovim dotnet-sdk git ripgrep fd unzip tree-sitter-cli base-devel
}

install_fedora() {
  echo "==> Installing prerequisites via dnf..."
  sudo dnf install -y neovim git ripgrep fd-find unzip dotnet-sdk-10.0 tree-sitter-cli curl
  sudo dnf group install -y "Development Tools" || sudo dnf install -y @development-tools

  ensure_nvim_min_version
  ensure_tree_sitter_cli_min_version
}

install_debian() {
  echo "==> Installing prerequisites via apt..."
  sudo apt-get update
  sudo apt-get install -y git ripgrep fd-find unzip build-essential curl ca-certificates

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

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_help
    exit 0
  fi

  if [[ "${1:-}" == -* && "${1:-}" != "-h" && "${1:-}" != "--help" ]]; then
    echo "ERROR: unknown option: $1" >&2
    print_help
    exit 1
  fi

  local repo_url
  repo_url="$(resolve_repo_url "${1:-}")"
  if [[ -z "$repo_url" ]]; then
    echo "ERROR: No config repo URL given. Pass it as an argument, set NVIM_CONFIG_REPO, or edit NVIM_CONFIG_REPO_DEFAULT in this script." >&2
    print_help
    exit 1
  fi

  export PATH="$LOCAL_BIN:$PATH"
  if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
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

  deploy_config "$repo_url"
  sync_plugins

  echo ""
  echo "==> Done. Open a .cs file in nvim to verify (e.g. nvim path/to/file.cs)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
