# Public Release Repo Design

## Goal

Turn this repository into a public, reproducible Codex HUD project that can be pushed to GitHub and used by other people without relying on the current machine state.

## Release Model

Recommended release model:

- keep source code and installer in the repository
- publish prebuilt patched `codex` binaries through GitHub Releases
- make the installer prefer release assets instead of local source builds
- keep local build instructions only for contributors

This avoids fragile local builds that currently depend on external binary downloads such as WebRTC and `rusty_v8`.

## Repository Shape

The current nested `Codex-HUD/` project directory should be flattened to the git root.

After flattening:

- the main public README lives at repository root
- `src/`, `tests/`, `scripts/`, `patches/`, and `docs/` live at repository root
- tracked runtime artifacts such as `node_modules/` and `dist/` are excluded from git

## Installer Direction

The public installer should:

- build the HUD locally with `npm ci && npm run build`
- write `status_line_command` into `~/.codex/config.toml`
- install a patched `codex` binary from a release asset when available
- fail clearly when no matching release asset exists

The installer should not default to patching and compiling upstream Codex on the user machine.

## README Direction

The root README should:

- describe the project in one screen
- show the supported platform clearly
- give one primary install path
- include one quick verification command
- separate contributor/build notes from user installation

## Immediate Scope

In scope now:

- flatten repo layout
- remove tracked local artifacts
- update README and install/config scripts
- prepare git history and remote for push to `sakuraay/codex-hud`

Out of scope now:

- creating GitHub Releases automatically
- building multi-platform binaries
- CI publishing workflow
