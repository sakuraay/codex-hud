# Minimal Codex HUD Status Line Design

## Goal

Reduce the `--status-line` output to a single compact line that shows only the essential session state:

- model
- project name
- git branch
- 5-hour usage
- 7-day usage

This design intentionally removes extra labels and mode badges so the status line reads like an immediate result, not a diagnostic panel.

## Output Format

Default status-line format:

```text
[g5.3c] project git:(main) | 5h ██░░ 25% | 7d ████░ 80%
```

Rules:

- model is shortened with the existing short-model mapping
- project is the last path segment from `cwd`
- git branch uses `git:(branch)` and appends `*` when dirty
- usage windows render as short bars plus percentage
- when a value is unavailable, render `--` instead of adding new explanatory text
- when the terminal width is too small, trim the final line instead of switching to alternate layouts

## Scope

In scope:

- simplify `renderTmuxLine()` to one stable layout
- keep multi-line `render()` behavior unchanged
- update tests for the new compact format
- update README examples to match the new status-line output

Out of scope:

- changing rollout parsing
- changing install flow
- adding plan/tool/context data to the status line
- introducing multiple status-line modes

## Implementation Notes

- Keep the renderer logic in `src/render.ts`
- Reuse existing helpers for visible-width trimming, short model names, and progress bars
- Remove width-tier templates for status-line rendering
- Prefer fixed compact bars sized for one-line terminal use

## Verification

- `npm run build`
- `npm test`
- one render test should assert the minimal single-line format
- one render test should still cover width trimming behavior
