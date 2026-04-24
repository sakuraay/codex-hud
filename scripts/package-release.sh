#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: scripts/package-release.sh --version <tag>

Builds:
  build/codex-hud-dist.tar.gz
  build/codex-hud-macos-arm64-release.tar.gz
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Missing required --version" >&2
  exit 1
fi

# shellcheck source=../install.sh
source "$REPO_DIR/install.sh"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This packaging script currently targets macOS arm64 only." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_DIR/release" "$BUILD_DIR/dist-package"

codex_repo="$(ensure_codex_repo)"
apply_patch_if_needed "$codex_repo"
build_hud
build_patched_codex_binary "$codex_repo"

mkdir -p "$BUILD_DIR/dist-package"
cp -R "$REPO_DIR/dist" "$BUILD_DIR/dist-package/dist"
cp "$REPO_DIR/README.md" "$BUILD_DIR/dist-package/README.md"
cp "$REPO_DIR/package.json" "$BUILD_DIR/dist-package/package.json"
tar -czf "$BUILD_DIR/codex-hud-dist.tar.gz" -C "$BUILD_DIR/dist-package" .

mkdir -p "$BUILD_DIR/release/codex-hud-macos-arm64-release/bin"
mkdir -p "$BUILD_DIR/release/codex-hud-macos-arm64-release/scripts"
cp -R "$REPO_DIR/dist" "$BUILD_DIR/release/codex-hud-macos-arm64-release/dist"
cp "$INSTALL_BIN_DIR/codex" "$BUILD_DIR/release/codex-hud-macos-arm64-release/bin/codex"
cp "$REPO_DIR/scripts/configure-codex-statusline.sh" "$BUILD_DIR/release/codex-hud-macos-arm64-release/scripts/configure-codex-statusline.sh"
printf '%s\n' "$VERSION" > "$BUILD_DIR/release/codex-hud-macos-arm64-release/VERSION"
tar -czf "$BUILD_DIR/codex-hud-macos-arm64-release.tar.gz" -C "$BUILD_DIR/release" codex-hud-macos-arm64-release

printf 'Created:\n  %s\n  %s\n' \
  "$BUILD_DIR/codex-hud-dist.tar.gz" \
  "$BUILD_DIR/codex-hud-macos-arm64-release.tar.gz"
