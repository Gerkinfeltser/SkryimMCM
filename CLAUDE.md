# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Skyrim MCP Server — a Model Context Protocol server that lets AI assistants (Claude, OpenAI, etc.) interact with Skyrim SE/AE via an SKSE plugin. The SKSE plugin runs inside Skyrim's process and exposes game state/actions over a named pipe. The C# MCP server relays between Claude Desktop (stdio) and the plugin (pipe). **Windows only.**

## Architecture

```
Claude Desktop <--stdio/MCP--> C# MCP Server <--named pipe--> SKSE Plugin (inside Skyrim)
```

### SKSE Plugin (`SkyrimMCPPlugin/` — C++)
- **Main.cpp** — SKSE entry point, starts pipe server + event system on kDataLoaded
- **PipeServer.h/cpp** — Named pipe server (`\\.\pipe\SkyrimMCP`) on background thread
- **Protocol.h/cpp** — Command registry (std::unordered_map) routing ~50 actions
- **Helpers.h** — Shared utilities: ParseFormId, ResolveActor, ActorValue resolution, console command execution, game safety checker, console output capture
- **PlayerQueries.h/cpp** — Player state: info, inventory, skills, perks, spells, shouts, appearance, blueprint, toggles (god mode, immortal), combat status
- **NPCManager.h/cpp** — NPC operations: nearby NPCs, actor info, followers, detection, factions, move/kill/crosshair targeting
- **InventoryManager.h/cpp** — Item operations: add, remove, equip, unequip
- **QuestManager.h/cpp** — Quest operations: info, stages, aliases, items, start/stop/complete
- **WorldManager.h/cpp** — World interaction: weather, time, cells, objects, doors, containers, merchants, bounties, collision, teleport
- **CombatAnalysis.h/cpp** — Combat: state, damage stats, threat assessment
- **UIManager.h/cpp** — Menu state queries
- **UtilityManager.h/cpp** — Notifications, form search, SKSE plugins, save/load, load order
- **PapyrusBridge.h/cpp** — Runtime .psc scanner, Papyrus VM call bridge, function catalog
- **EventSystem.h/cpp** — 17 game event sinks with noise filtering
- **TaskQueue.h/cpp** — Marshals pipe-thread calls to game thread via SKSE task interface

Uses source-built MinLL/CommonLibVR v4.39.5 at `550cc4fb9114649dcf526d1f3d73d710c5d7003b` in `SkyrimMCPPlugin/extern/CommonLibVR`, nlohmann-json, spdlog, fmt and DirectXTK. Static CRT and `x64-windows-static`. SE/AE enabled; VR, SDK tests, Xbyak and prebuilt SDK routes disabled.

### C# MCP Server (`SkyrimMCP/` — .NET 10)
- **Program.cs** — MCP server host, registers IPipeClient singleton, auto-discovers tools
- **IPipeClient.cs** — Interface for pipe communication (testability)
- **PipeClient.cs** — Named pipe client implementation
- **SkyrimOffsets.cs** — FormID database (30+ items, 20+ locations) for name→ID resolution
- **Tools/ToolBase.cs** — Base class with DeserializeResponse(), NotifyInGame(), PageResponse() helpers
- **Tools/PlayerTools.cs** — 15 tools: player info, skills, perks, spells, shouts, appearance, factions, blueprint, toggles
- **Tools/InventoryTools.cs** — 6 tools: inventory (paged), equipped, add/remove, bulk add
- **Tools/QuestTools.cs** — 4 tools: quest info, stages, aliases, items
- **Tools/NPCTools.cs** — 7 tools: nearby NPCs, NPC detail, inventory, followers, detection, crosshair, kill
- **Tools/WorldTools.cs** — 15 tools: weather, cell, objects, doors, containers, merchants, bounties, teleport, collision, loot scan
- **Tools/CombatTools.cs** — 3 tools: combat state, damage stats, threats
- **Tools/UtilityTools.cs** — 12 tools: console commands, notifications, search, load order, save/load, events, menu state, game safety
- **Tools/PapyrusTools.cs** — 4 tools: catalog, function lookup, VM call, rescan

## Build Commands

```powershell
# From repository root; VS2022 Community C++ workload and .NET 10 SDK.
$env:VCPKG_ROOT = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg"

# One-time pinned checkout, preserving any existing user-owned checkout.
git clone --depth 1 --branch v4.39.5 --recurse-submodules --shallow-submodules https://github.com/MinLL/CommonLibVR.git SkyrimMCPPlugin/extern/CommonLibVR

Push-Location SkyrimMCPPlugin
cmake --preset default -B build/minll-candidate
cmake --build build/minll-candidate --config Release --parallel 2
Pop-Location

# Requires an owner-local SkyrimMCP/SkyrimMCP.snk; never overwrite/publish the key.
dotnet build .\SkyrimMCP -c Release

# Uses the default build tree and a new output directory; never installs.
.\build_release.ps1 -Version "1.0.0" -OutputDir "release-minll-candidate"
```

**Native profile:** VS2022 Community selected by the preset; CMake pins vcpkg to that instance before `project()` so regeneration cannot select a newer VS installation. Both SDK and plugin use flags-off Release `/Od /Ob0 /DNDEBUG`, static CRT, and C++23 (fixed where available, `/std:c++23preview` otherwise). vcpkg baseline is `ee12231b20c95013c6638d845d04c91559a1d1ff`.

**ABI/provenance:** require the exact clean MIT SDK checkout, no imported/prebuilt library, and the fingerprint-guarded non-VR `TESObjectREFR` overlay in SDK/PCH/plugin/PCH include views. `src/PCH.h` supplies the SDK context and string-view literal required by generated metadata. Do not edit the dependency header in place or disable optimization for only one native target.

**Acceptance:** owner-approved initial candidate/runtime acceptance is 1.7.104.0 only. Offline gates passed; candidate ready for separately authorized installation/testing, not runtime-verified. Earlier 1.7.99.0/1.6.x checkpoints are deferred/unverified, not current blockers; preserve existing selector behavior without adding a whitelist. No VR/future-version claim. See README's evidence. Never install, launch the game or publish verified compatibility without corresponding authorization and acceptance.

**Fork signing:** the upstream private key is not in source. A fresh fork can use an owner-local 2048-bit key from `sn -k 2048 SkyrimMCP/SkyrimMCP.snk`; check absence first and preserve an existing key. `.snk` files are already ignored. The resulting strong-name identity is fork-local; the stdio/MCP and pipe contracts are unchanged.

## Protocol

JSON over named pipe `\\.\pipe\SkyrimMCP`, newline-delimited.

Request: `{"id":"uuid","action":"...","params":{}}`
Response: `{"id":"uuid","success":bool,"data":{},"error":"..."}`

## Key Technical Decisions

- **Console commands:** keep the historical MIT ConsoleUtilSSE-style `CompileAndRunImpl` and `RELOCATION_ID(21416, ConsoleCompilerAEId(version))`. Compare the complete `REL::Version` with 1.6.1130.0, not its patch component: AE ID 21890 before that boundary, 441582 afterward. The original patch-only predicate incorrectly selected 21890 on 1.7.x. Static assertions prove selector logic, not executable mapping or runtime behavior.
- **NPC targeting:** Use dot-notation `refId.command` (e.g., `FE124B0E.kill`). The `prid` command does NOT persist between separate ExecuteConsoleCommand calls.
- **Thread safety:** All game API calls go through TaskQueue to run on the game thread. Only `ping`, `poll_events`, and Papyrus catalog operations are handled directly on the pipe thread.
- **Papyrus VM calls:** DispatchStaticCall must NOT go through TaskQueue (deadlock). Called from pipe thread, callback fires on game thread.
- **SEH crash protection:** `__try/__except` around CompileAndRun catches access violations safely.
- **Static linking:** `x64-windows-static` vcpkg triplet required — dynamic linking causes SKSE load failure (0x0000007E).
- **CommonLib includes:** must come BEFORE Windows API headers; the plugin PCH enforces the SDK context first. Use `void*` for HANDLE in headers and include `<windows.h>` only in .cpp files after CommonLib.
- **Async save:** Fire-and-forget from Protocol layer — BGSSaveLoadManager::Save() blocks game thread for 10+ seconds with heavy mod lists.
- **Actor polymorphism:** `Helpers::ResolveActor(refId)` returns player if empty, specific actor by FormID otherwise. Used by GetInventory, GetFactions, SetActorValue.
- **Game safety checker:** `Helpers::CheckGameSafety()` detects loading, kill moves, saves. Functions like ToggleImmortalMode use it for fallback strategies.

## Key API Patterns (pinned MinLL/CommonLibVR v4.39.5)

- Actor values: `AsActorValueOwner()->GetActorValue()`, not `Actor::GetActorValue()`
- Base actor value: `GetBaseActorValue()`, not `GetPermanentActorValue()`
- Quest objectives: use `state` field, not `IsCompleted()`
- Quest aliases: use `GetVMTypeID() == BGSRefAlias::VMTYPEID` with `static_cast`, not `dynamic_cast`
- Plugin metadata: one declaration generated by `add_commonlibsse_plugin(... USE_ADDRESS_LIBRARY ...)`, Independent layout, raw compatibility fields `0x1`/`0x3`, minimum SKSE 0. Retain `SKSEPluginLoad()` in Main; derive log version from `PluginDeclaration::GetSingleton()`.
- Logging: needs `#include <spdlog/sinks/basic_file_sink.h>`
- Papyrus VM implementation: `vm->GetImpl()`, not the removed direct `vm->impl`; preserve pipe-thread dispatch and callback/timeout behavior.
- Armor slot mask: `GetSlotMask().underlying()` preserves the unsigned 32-bit JSON field.
- HUD notifications: `RE::SendHUDMessage::ShowHUDMessage()`, not `RE::DebugNotification()`.
- Inspect actual headers under `SkyrimMCPPlugin/extern/CommonLibVR/include/` when in doubt. `openspec/` is intentionally ignored by the owner; do not unignore or force-add it. Durable candidate evidence belongs in README and project tracking.

## Project Tracking

- **`project_work_items.json`** — Single source of truth for all features, bugs, and status (72+ items, 12 phases)
- **`ROADMAP.md`** — Human-readable feature roadmap
- **`CHARACTER_BLUEPRINT_SPEC.json`** — Character export/import specification
- **`project_dashboard.html`** — Visual dashboard for project_work_items.json

## Git Workflow

- **`main`** — Release-ready code only (README + .gitignore currently)
- **`develop`** — Active development branch
- **Feature branches:** `feature/XXX-name` for new features
- **Bugfix branches:** `bugfix/XXX-description` for bug fixes
- **Refactor branches:** `refactor/description` for code restructuring
- All branches merge to develop via `--no-ff`

## Prerequisites for Running
- SKSE64 installed in Skyrim
- Address Library for SKSE (SE or AE version)
- SkyrimMCPPlugin.dll in `<Skyrim>/Data/SKSE/Plugins/`
- .NET 10 Runtime
- Claude Desktop config pointing to the C# MCP server
