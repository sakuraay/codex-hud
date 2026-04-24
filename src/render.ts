import { RESET, bar, cyan, dim, green, percentColor, red, yellow } from './colors.js';
import type { HudConfig, HudSnapshot, ToolActivity } from './types.js';

function formatTokens(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${Math.round(value / 1_000)}k`;
  return `${value}`;
}

function formatRemaining(to?: Date): string {
  if (!to) return '';
  const diff = to.getTime() - Date.now();
  if (diff <= 0) return '';
  const mins = Math.ceil(diff / 60000);
  if (mins >= 24 * 60) {
    const d = Math.floor(mins / (24 * 60));
    const h = Math.floor((mins % (24 * 60)) / 60);
    return h > 0 ? `${d}d ${h}h` : `${d}d`;
  }
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

function detectStatusWidth(): number {
  const envWidth = Number.parseInt(process.env.CODEX_HUD_WIDTH ?? process.env.COLUMNS ?? '', 10);
  if (!Number.isNaN(envWidth) && envWidth > 0) return envWidth;
  if (process.stdout.isTTY && process.stdout.columns && process.stdout.columns > 0) return process.stdout.columns;
  return 120;
}

function shortenModel(model: string): string {
  return model
    .toLowerCase()
    .replace(/^gpt-/, 'g')
    .replace(/-codex-spark$/, 's')
    .replace(/-codex$/, 'c')
    .replace(/\s+/g, '');
}

function projectFromCwd(cwd?: string): string {
  if (!cwd) return 'project';
  const parts = cwd.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] || 'project';
}

function renderRate(label: string, usedPercent?: number): string {
  if (usedPercent === undefined) return `${label} --`;
  const percent = Math.round(usedPercent);
  return `${label} ${percentColor(percent)(bar(percent, 4))} ${percentColor(percent)(`${percent}%`)}`;
}

function trimToWidth(text: string, width: number): string {
  const visibleLen = visibleLength(text);
  if (visibleLen <= width) return `${text}${' '.repeat(Math.max(0, width - visibleLen + 2))}`;
  if (width < 6) return `${truncateVisible(text, width)}${RESET}`;

  const visibleBudget = Math.max(1, width - 1);
  const truncated = truncateVisible(text, visibleBudget);
  return `${truncated}…${RESET}`;
}

const ANSI_RE = /\x1b\[[0-9;]*m/g;

function visibleLength(text: string): number {
  return text.replace(ANSI_RE, '').length;
}

function truncateVisible(text: string, maxVisible: number): string {
  if (maxVisible <= 0) return '';
  if (visibleLength(text) <= maxVisible) return text;

  let out = '';
  let visible = 0;
  for (let i = 0; i < text.length && visible < maxVisible;) {
    if (text[i] === '\x1b') {
      const rest = text.slice(i);
      const match = rest.match(ANSI_RE);
      if (match) {
        out += match[0];
        i += match[0].length;
        continue;
      }
    }

    out += text[i];
    visible += 1;
    i += 1;
  }

  if (out.endsWith(RESET)) {
    return out;
  }
  return `${out}${RESET}`;
}

function toolPrefix(tool: ToolActivity): string {
  if (tool.status === 'running') return yellow('◐');
  if (tool.status === 'completed') return green('✓');
  return red('✗');
}

function renderPlan(snapshot: HudSnapshot): string | null {
  if (snapshot.plan.length === 0) return null;
  const completed = snapshot.plan.filter((p) => p.status === 'completed').length;
  const running = snapshot.plan.find((p) => p.status === 'in_progress');
  const title = running?.step ?? snapshot.plan[0]?.step;
  return `${cyan('Plan')} ${completed}/${snapshot.plan.length}${title ? ` • ${title}` : ''}`;
}

export function render(snapshot: HudSnapshot, config: HudConfig): string[] {
  const lines: string[] = [];

  const model = snapshot.model ?? 'unknown-model';
  const project = snapshot.cwd ? snapshot.cwd.split(/[\\/]/).filter(Boolean).slice(-2).join('/') : '(no-cwd)';
  const git = snapshot.gitBranch ? ` git:(${snapshot.gitBranch}${snapshot.gitDirty ? '*' : ''})` : '';
  const turn = snapshot.turnState === 'running' ? yellow('running') : dim('idle');

  lines.push(`${cyan('[Codex HUD]')} ${model} │ ${project}${git} │ turn ${turn}`);

  const parts: string[] = [];
  if (snapshot.contextUsedPercent !== undefined) {
    const c = percentColor(snapshot.contextUsedPercent);
    const usage = `${bar(snapshot.contextUsedPercent)} ${c(`${snapshot.contextUsedPercent}%`)}`;
    const tokens = snapshot.contextTokens !== undefined
      ? `${formatTokens(snapshot.contextTokens)}/${formatTokens(snapshot.contextWindow ?? 0)}`
      : '';
    parts.push(`Context ${usage}${tokens ? ` (${tokens})` : ''}`);
  }

  if (config.showRates && snapshot.ratePrimary) {
    const p = Math.round(snapshot.ratePrimary.usedPercent);
    const primary = `${percentColor(p)(`${p}%`)}${formatRemaining(snapshot.ratePrimary.resetsAt) ? `/${formatRemaining(snapshot.ratePrimary.resetsAt)}` : ''}`;
    const secondary = snapshot.rateSecondary
      ? `${percentColor(Math.round(snapshot.rateSecondary.usedPercent))(`${Math.round(snapshot.rateSecondary.usedPercent)}%`)}`
      : '';
    parts.push(`Usage ${primary}${secondary ? ` | ${secondary}` : ''}`);
  }

  if (parts.length > 0) {
    lines.push(parts.join(' │ '));
  }

  const toolLines = [...snapshot.activeTools, ...snapshot.recentTools]
    .slice(-(config.maxTools))
    .map((tool) => `${toolPrefix(tool)} ${tool.label}`);

  if (toolLines.length > 0) {
    lines.push(`Tools ${toolLines.join(' | ')}`);
  }

  if (config.showPlan) {
    const plan = renderPlan(snapshot);
    if (plan) lines.push(plan);
  }

  lines.push(dim(snapshot.sessionPath));

  return lines;
}

export function renderTmuxLine(snapshot: HudSnapshot): string {
  const modelRaw = snapshot.model ?? 'unknown-model';
  const modelShort = shortenModel(modelRaw);
  const badge = cyan(`[${modelShort}]`);
  const width = detectStatusWidth();
  const project = projectFromCwd(snapshot.cwd);
  const git = snapshot.gitBranch ? `git:(${snapshot.gitBranch}${snapshot.gitDirty ? '*' : ''})` : '';
  const location = git ? `${project} ${git}` : project;
  const line = [
    badge,
    location,
    renderRate('5h', snapshot.ratePrimary?.usedPercent),
    renderRate('7d', snapshot.rateSecondary?.usedPercent),
  ].join(' | ');

  return trimToWidth(line, width);
}
