import test from 'node:test';
import assert from 'node:assert/strict';
import { render, renderTmuxLine } from '../dist/render.js';

function stripAnsi(text) {
  return text.replace(/\x1b\[[0-9;]*m/g, '');
}

test('render emits compact HUD lines', () => {
  const lines = render(
    {
      sessionPath: '/tmp/rollout.jsonl',
      cwd: '/repo/project',
      model: 'gpt-5-codex',
      gitBranch: 'main',
      gitDirty: true,
      turnState: 'running',
      contextUsedPercent: 82,
      contextTokens: 210000,
      contextWindow: 258000,
      ratePrimary: { usedPercent: 40 },
      rateSecondary: { usedPercent: 71 },
      activeTools: [{
        id: '1',
        label: 'npm test',
        status: 'running',
        startTime: new Date('2026-01-01T00:00:00Z'),
      }],
      recentTools: [],
      plan: [
        { status: 'completed', step: 'A' },
        { status: 'in_progress', step: 'B' },
      ],
    },
    {
      refreshMs: 700,
      maxTools: 3,
      showPlan: true,
      showRates: true,
    },
  );

  assert.ok(lines.length >= 4);
  assert.ok(lines[0].includes('gpt-5-codex'));
  assert.ok(lines.some((line) => line.includes('Context')));
  assert.ok(lines.some((line) => line.includes('Tools')));
  assert.ok(lines.some((line) => line.includes('Plan')));
});

test('renderTmuxLine emits minimal single-line status output', () => {
  const line = stripAnsi(renderTmuxLine({
    sessionPath: '/tmp/rollout.jsonl',
    cwd: '/repo/project',
    model: 'gpt-5.3-codex',
    gitBranch: 'main',
    gitDirty: true,
    turnState: 'running',
    ratePrimary: { usedPercent: 25 },
    rateSecondary: { usedPercent: 80 },
    activeTools: [],
    recentTools: [],
    plan: [],
  }));

  assert.match(line, /\[g5\.3c\] \| project git:\(main\*\) \| 5h [█░]+ 25% \| 7d [█░]+ 80%/);
});

test('renderTmuxLine trims to width instead of switching layouts', () => {
  const previousWidth = process.env.CODEX_HUD_WIDTH;
  process.env.CODEX_HUD_WIDTH = '30';

  try {
    const line = stripAnsi(renderTmuxLine({
      sessionPath: '/tmp/rollout.jsonl',
      cwd: '/very/long/project-name',
      model: 'gpt-5.3-codex',
      gitBranch: 'feature/super-long-branch',
      gitDirty: false,
      turnState: 'idle',
      ratePrimary: { usedPercent: 25 },
      rateSecondary: { usedPercent: 80 },
      activeTools: [],
      recentTools: [],
      plan: [],
    }));

    assert.ok(line.length <= 30);
    assert.ok(line.endsWith('…'));
  } finally {
    if (previousWidth === undefined) {
      delete process.env.CODEX_HUD_WIDTH;
    } else {
      process.env.CODEX_HUD_WIDTH = previousWidth;
    }
  }
});
