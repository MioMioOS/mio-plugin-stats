# MioIsland Stats Plugin

[![Plugin](https://img.shields.io/badge/MioIsland-plugin-CAFF00?style=flat-square)](https://github.com/MioMioOS/MioIsland)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple)](https://github.com/MioMioOS/MioIsland)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

Editorial-style daily and weekly stats for [MioIsland](https://github.com/MioMioOS/MioIsland) — your Claude Code activity rendered as a newspaper.

This is the source for the official `stats.bundle` plugin that ships with MioIsland v2.0+. It reads `~/.claude/projects/*/*.jsonl` directly to compute focus minutes, flow blocks, project time distribution, tool/skill/MCP breakdowns, and personal records — all in a single Swift `.bundle` loaded by the host app.

## Features

- **Newspaper layout** — masthead, serif italic headlines, two-column body, hairline rules, no charts. Pure typography.
- **Day and week views** — switch via the masthead toggle. Both have their own narrative.
- **Smart insights** — auto-detects personal records, two-week longest deep stretches, streak milestones, work mode (shipping / debugging / exploring).
- **Flow blocks** — strict 15-minute, 2-minute-gap focus blocks for an honest "deep work" count, separate from cumulative focus minutes.
- **Project time split** — when you touched ≥2 projects, the body becomes a per-project time distribution.
- **Editor's Note** — opt-in Claude-powered summary and improvement suggestions. Calls your local `claude` CLI with aggregate numbers only (no source code) and caches per day/week/language.
- **Full i18n** — respects MioIsland's `appLanguage` setting (zh / en / auto).

## Build

```bash
./build.sh              # → build/stats.bundle + build/stats.zip
./build.sh install      # also copies to ~/.config/codeisland/plugins/
```

Then restart MioIsland and the new build loads on next launch.

## How it works

`AnalyticsCollector` scans `~/.claude/projects/*/*.jsonl` once per day in a parallel `TaskGroup`, bucketizes timestamps into local-day windows, and produces a 14-day report (`thisWeek` + `lastWeek` for comparison). Results are persisted to `~/Library/Application Support/CodeIsland/analytics_cache.json` so warm starts paint instantly.

`EditorsNoteService` invokes your installed `claude` CLI in non-interactive mode (`claude -p`) with an editorial-coach prompt. It looks for `claude` at `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.claude/local/claude`, and `~/.local/bin/claude`. The prompt only contains aggregate numbers (turns, focus minutes, tool counts, project names) — never source code — and the response is cached per day/week and per language so it doesn't burn credits on every view.

## License

MIT.
