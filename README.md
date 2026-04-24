# Codex HUD

Codex HUD adds a minimal single-line usage HUD to Codex CLI.

It renders:

```text
[g5.3c] | project git:(main) | 5h ██░░ 25% | 7d ███░ 80%
```

The HUD reads Codex rollout logs and injects a compact status line through a small patch to the Codex TUI.

![Codex HUD screenshot](docs/assets/hud-example.png)

## Features

- Minimal status line: model, project, Git branch, 5h usage, 7d usage
- No extra noise by default in `--status-line` mode
- Installs a patched `codex` binary to `~/.local/bin/codex`
- Keeps upstream Codex source in an isolated vendor checkout under `~/.codex-hud/vendor/openai-codex`
- Updates `~/.codex/config.toml` with `status_line_command`

## Verified Environment

- macOS arm64
- zsh / bash
- Node.js 18+
- Rust toolchain (`cargo`)

The installer still keeps the Linux source-build path, but the setup above is the one currently verified end to end.

## Install

```bash
git clone https://github.com/sakuraay/codex-hud.git
cd codex-hud
./install.sh
```

What `install.sh` does:

1. Builds this HUD with `npm ci` and `npm run build`
2. Clones `openai/codex` into `~/.codex-hud/vendor/openai-codex`
3. Checks out the pinned upstream commit `1dc3535e17666884800ada37d7eb94cf974d38fe`
4. Applies `patches/codex-statusline-command.patch`
5. Builds patched `codex`
6. Installs the binary to `~/.local/bin/codex`
7. Writes `[tui].status_line_command` into `~/.codex/config.toml`

After install, restart Codex so the new status line is loaded.

## Verify

```bash
codex --version
grep -n "status_line_command" ~/.codex/config.toml
node dist/index.js --status-line --once --no-clear
```

Expected HUD output looks like:

```text
[g5.4] | levi | 5h ██░░ 58% | 7d █░░░ 19%
```

## Scope

This repo only writes to:

- `~/.local/bin/codex`
- `~/.codex/config.toml`
- `~/.codex-hud/`
- your shell rc files for `PATH` precedence (`~/.zshrc`, `~/.bashrc`)

It does not patch or overwrite arbitrary `openai/codex` clones elsewhere on your machine.

## Development

```bash
npm run build
npm run dev
npm test
```

## Repository Layout

- `src/`: HUD parser and renderer
- `tests/`: test cases
- `scripts/`: install/config helpers
- `patches/`: Codex patch
- `docs/`: notes, analysis, and specs

## Troubleshooting

- HUD not visible: exit Codex completely and start a fresh session
- `codex` still resolves to another binary: open a new shell, or run `export PATH="$HOME/.local/bin:$PATH" && hash -r`
- Patch no longer applies: upstream Codex changed, so regenerate `patches/codex-statusline-command.patch` against a fresh vendor checkout

## Support

- Issues: `https://github.com/sakuraay/codex-hud/issues`
