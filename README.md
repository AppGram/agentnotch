<p align="center">
  <img src="https://raw.githubusercontent.com/AppGram/agentnotch/main/icon.png" width="128" height="128" alt="AgentNotch Icon">
</p>

<h1 align="center">AgentNotch</h1>

<p align="center">
  <strong>Real-time AI coding assistant telemetry in your Mac's notch</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#requirements">Requirements</a>
</p>

---

## What is AgentNotch?

AgentNotch is a sleek macOS menu bar app that lives in your Mac's notch, providing real-time visibility into your AI coding assistants. Watch as **Claude Code** and **OpenAI Codex** think, read files, and execute tools — all without leaving your editor.

## Features

### 🎯 **Real-Time Tool Tracking**
See every tool call as it happens — file reads, code edits, shell commands, and more. Know exactly what your AI assistant is doing at any moment.

### 📊 **Token & Cost Monitoring**
Track token usage (input/output) and estimated costs in real-time. Never be surprised by API bills again.

### 🎨 **Source-Aware Design**
- **Orange** indicator for Claude Code
- **Blue** indicator for Codex
- **Light blue** for unknown sources

Visual distinction lets you know which AI is active at a glance.

### 🔔 **Completion Detection**
Get notified when your AI assistant finishes a task. No more wondering "is it still thinking?"

### ⚡ **Lightweight & Native**
- Lives in your Mac's notch — zero screen real estate used
- Native macOS app — fast, efficient, battery-friendly
- Expands on hover to show details

### ⚙️ **Configurable**
- Show/hide token counts
- Show/hide cost estimates
- Filter by source (Claude/Codex)
- Toggle menu bar icon

## Installation

### Homebrew (Recommended)

```bash
brew tap AppGram/tap
brew install --cask agentnotch
```

### Manual Download

1. Download `AgentNotch-1.0.0.zip` from [Releases](https://github.com/AppGram/agentnotch/releases)
2. Unzip and drag `AgentNotch.app` to `/Applications`
3. Open AgentNotch

## Usage

### Setup with Claude Code

Add to your Claude Code configuration to send telemetry:

```bash
# Set OTEL endpoint to AgentNotch (default port 4318)
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
```

### Setup with Codex

AgentNotch listens for **OTLP/HTTP** on port **4318** by default, and currently decodes **OTLP logs** (`/v1/logs`) and **metrics** (`/v1/metrics`).

Codex CLI (v0.79+) uses `~/.codex/config.toml` with an `[otel]` section (not `[telemetry]`). Add:

```toml
[analytics]
enabled = true

[otel]
# AgentNotch currently does not decode OTLP traces, so disable trace export to avoid noisy errors.
trace_exporter = "none"

[otel.exporter.otlp-http]
endpoint = "http://localhost:4318/v1/logs"
protocol = "binary"
```

### Using the App

1. **Launch** — AgentNotch appears in your notch (or menu bar on non-notch Macs)
2. **Hover** — Expand to see recent tool calls with details
3. **Click** — Open full view with token breakdown and settings
4. **Settings** — Configure display options via the gear icon

## Screenshots

| Collapsed | Expanded |
|-----------|----------|
| Minimal notch indicator | Full tool call history |

## Requirements

- macOS 14.0 (Sonoma) or later
- Mac with notch (MacBook Pro 14"/16" 2021+) or any Mac (falls back to menu bar)

## Privacy

AgentNotch runs **100% locally**. No data is sent anywhere — it only receives telemetry from your local AI tools.

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ for developers who love AI coding assistants
</p>
