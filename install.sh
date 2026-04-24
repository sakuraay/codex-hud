#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$REPO_DIR/patches/codex-statusline-command.patch"
INSTALL_BIN_DIR="$HOME/.local/bin"
CODEX_VENDOR_DIR="${CODEX_HUD_VENDOR_DIR:-$HOME/.codex-hud/vendor/openai-codex}"
CODEX_CACHE_DIR="${CODEX_HUD_CACHE_DIR:-$HOME/.codex-hud/cache}"
CODEX_UPSTREAM_URL="https://github.com/openai/codex"
CODEX_UPSTREAM_COMMIT="1dc3535e17666884800ada37d7eb94cf974d38fe"
WEBRTC_URL="https://github.com/livekit/rust-sdks/releases/download/webrtc-24f6822-2/webrtc-mac-arm64-release.zip"
RUSTY_V8_URL="https://github.com/denoland/rusty_v8/releases/download/v146.4.0/librusty_v8_release_aarch64-apple-darwin.a.gz"
WEBRTC_DIR="${HOME}/.codex-hud/webrtc-prebuilt/mac-arm64-release"
RUSTY_V8_ARCHIVE="${CODEX_CACHE_DIR}/librusty_v8_release_aarch64-apple-darwin.a.gz"

print_step() {
  printf '\n[install] %s\n' "$1"
}

fatal() {
  echo "[install] ERROR: $1" >&2
  exit 1
}

ensure_command() {
  local cmd="$1"
  local hint="${2:-Install '$cmd' and rerun install.sh}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fatal "$hint"
  fi
}

download_file() {
  local url="$1"
  local target="$2"

  mkdir -p "$(dirname "$target")"
  curl -L --fail "$url" -o "$target"
}

ensure_rust_toolchain() {
  if command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  print_step "Rust toolchain not found. Installing via rustup"
  ensure_command curl "curl is required to install Rust (install curl first)"
  curl https://sh.rustup.rs -sSf | sh -s -- -y

  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
  fi
  ensure_command cargo "cargo still not found after rustup install"
}

ensure_linux_build_deps() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    return 0
  fi

  local missing=0
  command -v clang >/dev/null 2>&1 || missing=1
  command -v clang++ >/dev/null 2>&1 || missing=1
  command -v pkg-config >/dev/null 2>&1 || missing=1
  command -v cmake >/dev/null 2>&1 || missing=1
  command -v make >/dev/null 2>&1 || missing=1

  if command -v pkg-config >/dev/null 2>&1; then
    pkg-config --exists libcap || missing=1
    pkg-config --exists libseccomp || missing=1
  fi

  if [[ $missing -eq 0 ]]; then
    return 0
  fi

  print_step "Installing Linux build deps (clang/cmake/pkg-config/libcap/libseccomp)"
  local run_as_root=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      run_as_root=(sudo)
    else
      fatal "Need root or sudo to install packages. Install clang/cmake/pkg-config/libcap/libseccomp manually and rerun."
    fi
  fi

  if command -v apt-get >/dev/null 2>&1; then
    "${run_as_root[@]}" apt-get update
    "${run_as_root[@]}" apt-get install -y clang build-essential cmake pkg-config libcap-dev libseccomp-dev
  elif command -v dnf >/dev/null 2>&1; then
    "${run_as_root[@]}" dnf install -y clang clang-tools-extra gcc gcc-c++ make cmake pkgconf-pkg-config libcap-devel libseccomp-devel
  elif command -v pacman >/dev/null 2>&1; then
    "${run_as_root[@]}" pacman -Sy --noconfirm clang base-devel cmake pkgconf libcap libseccomp
  elif command -v zypper >/dev/null 2>&1; then
    "${run_as_root[@]}" zypper --non-interactive install clang gcc gcc-c++ make cmake pkg-config libcap-devel libseccomp-devel
  else
    fatal "Unsupported package manager. Install clang/cmake/pkg-config/libcap/libseccomp manually and rerun."
  fi

  command -v pkg-config >/dev/null 2>&1 || fatal "pkg-config not found after dependency install"
  pkg-config --exists libcap || fatal "libcap not visible via pkg-config after dependency install"
  pkg-config --exists libseccomp || fatal "libseccomp not visible via pkg-config after dependency install"
}

ensure_macos_build_assets() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  if [[ "$(uname -m)" != "arm64" ]]; then
    fatal "The verified macOS build target is Apple Silicon (arm64)."
  fi

  ensure_command curl "curl is required to download macOS build assets"
  ensure_command unzip "unzip is required to unpack the macOS WebRTC archive"

  if [[ ! -d "$WEBRTC_DIR" ]]; then
    local zip_path="${CODEX_CACHE_DIR}/webrtc-mac-arm64-release.zip"
    local extract_root

    print_step "Downloading WebRTC prebuilt for macOS arm64"
    download_file "$WEBRTC_URL" "$zip_path"

    extract_root="$(mktemp -d)"
    unzip -q "$zip_path" -d "$extract_root"
    mkdir -p "$(dirname "$WEBRTC_DIR")"
    rm -rf "$WEBRTC_DIR"
    mv "$extract_root/mac-arm64-release" "$WEBRTC_DIR"
    rmdir "$extract_root"
  fi

  if [[ ! -f "$RUSTY_V8_ARCHIVE" ]]; then
    print_step "Downloading rusty_v8 archive for macOS arm64"
    download_file "$RUSTY_V8_URL" "$RUSTY_V8_ARCHIVE"
  fi
}

prepare_cargo_env() {
  export CARGO_NET_GIT_FETCH_WITH_CLI=true

  if [[ "$(uname -s)" == "Darwin" ]]; then
    ensure_macos_build_assets
    export LK_CUSTOM_WEBRTC="$WEBRTC_DIR"
    export RUSTY_V8_ARCHIVE="$RUSTY_V8_ARCHIVE"
  fi
}

ensure_local_bin_precedence() {
  mkdir -p "$INSTALL_BIN_DIR"
  export PATH="$INSTALL_BIN_DIR:$PATH"

  local marker_start="# >>> codex-hud path >>>"
  local marker_end="# <<< codex-hud path <<<"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local rc_files=("$HOME/.bashrc" "$HOME/.zshrc")

  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || touch "$rc"
    if grep -Fq "$marker_start" "$rc"; then
      continue
    fi
    {
      echo ""
      echo "$marker_start"
      echo "$line"
      echo "$marker_end"
    } >> "$rc"
  done
}

ensure_codex_repo() {
  mkdir -p "$(dirname "$CODEX_VENDOR_DIR")"

  if [[ ! -d "$CODEX_VENDOR_DIR/.git" ]]; then
    print_step "Cloning openai/codex into $CODEX_VENDOR_DIR"
    git clone "$CODEX_UPSTREAM_URL" "$CODEX_VENDOR_DIR"
  fi

  local current_head=""
  current_head="$(git -C "$CODEX_VENDOR_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$current_head" == "$CODEX_UPSTREAM_COMMIT" ]]; then
    echo "$CODEX_VENDOR_DIR"
    return 0
  fi

  if [[ -n "$(git -C "$CODEX_VENDOR_DIR" status --short)" ]]; then
    fatal "Vendor repo at $CODEX_VENDOR_DIR has local changes. Clean it or remove the directory, then rerun."
  fi

  print_step "Checking out pinned openai/codex commit $CODEX_UPSTREAM_COMMIT"
  git -C "$CODEX_VENDOR_DIR" fetch --depth 1 origin "$CODEX_UPSTREAM_COMMIT"
  git -C "$CODEX_VENDOR_DIR" checkout --detach "$CODEX_UPSTREAM_COMMIT"
  echo "$CODEX_VENDOR_DIR"
}

apply_patch_if_needed() {
  local codex_repo="$1"

  if git -C "$codex_repo" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    print_step "Patch already applied at $codex_repo"
    return 0
  fi

  print_step "Applying Codex status-line command patch"
  git -C "$codex_repo" apply --check "$PATCH_FILE"
  git -C "$codex_repo" apply "$PATCH_FILE"
}

build_hud() {
  print_step "Building codex-hud"
  ensure_command npm "npm is required (install Node.js + npm first)"
  cd "$REPO_DIR"
  npm ci
  npm run build
}

configure_codex() {
  print_step "Configuring ~/.codex/config.toml"
  "$REPO_DIR/scripts/configure-codex-statusline.sh" --repo-dir "$REPO_DIR"
}

build_patched_codex_binary() {
  local codex_repo="$1"

  ensure_rust_toolchain
  ensure_linux_build_deps
  prepare_cargo_env

  print_step "Building patched Codex binary"
  cd "$codex_repo/codex-rs"
  local build_log
  build_log="$(mktemp)"

  if ! cargo build --release -p codex-cli >"$build_log" 2>&1; then
    if grep -q "COMPILER BUG DETECTED" "$build_log"; then
      print_step "Detected gcc compiler bug from aws-lc-sys. Retrying with clang"
      ensure_linux_build_deps
      CC=clang CXX=clang++ cargo build --release -p codex-cli
    else
      cat "$build_log"
      rm -f "$build_log"
      fatal "Failed to build patched Codex binary"
    fi
  fi
  rm -f "$build_log"

  local built="$codex_repo/codex-rs/target/release/codex"
  if [[ ! -x "$built" ]]; then
    fatal "Patched codex binary not found at $built"
  fi

  local target="$INSTALL_BIN_DIR/codex"
  mkdir -p "$INSTALL_BIN_DIR"

  if [[ -x "$target" && ! -L "$target" ]]; then
    local backup="$INSTALL_BIN_DIR/codex.backup.$(date +%Y%m%d%H%M%S)"
    cp "$target" "$backup"
    print_step "Backed up existing codex binary to $backup"
  fi

  cp "$built" "$target"
  chmod +x "$target"
  print_step "Installed patched codex to $target"

  ensure_local_bin_precedence
  hash -r
}

main() {
  print_step "Starting one-shot install"
  ensure_command git "git is required (install git first)"

  if [[ ! -f "$PATCH_FILE" ]]; then
    fatal "Patch file missing: $PATCH_FILE"
  fi

  local codex_repo
  codex_repo="$(ensure_codex_repo)"
  print_step "Using Codex source: $codex_repo"

  apply_patch_if_needed "$codex_repo"
  build_hud
  configure_codex
  build_patched_codex_binary "$codex_repo"

  local resolved
  resolved="$(command -v codex || true)"
  if [[ "$resolved" != "$INSTALL_BIN_DIR/codex" ]]; then
    print_step "Notice: current shell still resolves codex to: ${resolved:-<not found>}"
    print_step "Open a new shell or run: export PATH=\"$INSTALL_BIN_DIR:\$PATH\" && hash -r"
  fi

  print_step "Done"
  echo "Patched codex installed at: $INSTALL_BIN_DIR/codex"
  echo "Run Codex normally: codex"
  echo "HUD command wired in ~/.codex/config.toml via [tui].status_line_command"
}

main "$@"
