---
title: Getting Started with Nuo
summary: What Nuo is, system requirements, and how to find your way around.
order: 10
---

# Getting Started with Nuo

Nuo is a free, open-source macOS AI app: agents, memory, tools, and identity that live on your Mac. It runs fully offline with local models, and connects to cloud providers only when you choose. MIT licensed, built in native Swift for Apple Silicon.

## Requirements

- macOS 15.5 or newer, Apple Silicon (M-series) Mac.
- Download from the GitHub releases page.
- Docs: https://docs.osaurus.ai · Models: https://huggingface.co/OsaurusAI · Community: Discord (invite on the website/repo).

## Finding your way around

- Chat window: global hotkey (default ⌘;) or launch Nuo from Spotlight.
- Settings… (⌘,) opens the Management window. The sidebar has every area: General, Conversation, Voice, Themes, Credits, Workspaces, Identity, Permissions, Privacy, Local Models, Providers, Images, Orchestrator, Agents, Channels, Web Search, Knowledge, Memory, Tools & MCP, Skills, Commands, Schedules, Watchers, Computer Use, Browser Use, Server, Sandbox, Insights. Type a setting name in the sidebar search to jump to it.
- CLI (install from Settings… (⌘,) → Server → Overview → Command Line Tool → Install CLI): `nuo ui`, `nuo serve`, `nuo status`.

## First steps

1. Download a local model (Local Models tab) or add a cloud provider (Providers tab).
2. Open chat and talk to the default Nuo assistant — it can configure the app for you (download models, add providers, change settings) and answer questions about any feature.
3. Create custom agents (Agents tab) for real work: coding, research, files, web — each with its own prompt, tools, memory, and theme.

## The default Nuo assistant

The built-in "Nuo" agent in chat is the front door for setup: ask it "what's configured?", "download a model", "add a provider", "change a setting", or any "how does X work?" question. For tasks beyond configuring Nuo (coding, web research, file work), it will offer to create or switch to a fitting agent.

## Where data lives

Everything is stored locally under `~/.nuo/` (chats, memory, agents, config). Local models live in `~/MLXModels` by default. Nothing leaves your Mac unless you connect a cloud provider or enable network exposure.
