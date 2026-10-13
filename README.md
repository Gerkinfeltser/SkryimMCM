# SkyLink AI

A Model Context Protocol (MCP) server that lets AI assistants (Claude, etc.) interact directly with Skyrim SE/AE's runtime engine. 87 tools for reading and modifying game state in real time — player stats, inventory, quests, NPCs, world interaction, combat, and more.

## Architecture

```
Claude Desktop <--stdio/MCP--> C# MCP Server <--named pipe--> SKSE Plugin (inside Skyrim)
```

**SKSE Plugin** (C++ DLL) — runs inside Skyrim's process via SKSE. Uses source-built [MinLL/CommonLibVR](https://github.com/MinLL/CommonLibVR) v4.39.5 for native SE/AE engine access. Exposes game actions over the unchanged named pipe (`\\.\pipe\SkyrimMCP`).

**C# MCP Server** (.NET 10) — bridges Claude Desktop (stdio MCP) and the SKSE plugin (named pipe). 87 MCP tools auto-discovered via `[McpServerTool]` attributes.

## Features

### Game Tools

| Category | Tools |
|----------|-------|
| **Player** | Info, skills, perks, spells, shouts, appearance, factions, resistances, powers, diseases, level, blueprint export |
| **Inventory** | Full inventory (paged), equipped items (32 slots), add/remove, bulk add, equip/unequip, enchantment details |
| **Quests** | Active quests, stages, aliases (resolved to NPCs), quest items, set stage, start/stop/complete |
| **NPCs** | Nearby NPCs, detailed info, NPC inventory, followers, detection level, crosshair targeting, kill, move |
| **World** | Weather (get/set/list 339 types), cell info, nearby objects, containers, lock/unlock doors, map markers, teleport |
| **Combat** | Combat state (targets + allies), damage stats (armor + weapon damage), threat assessment |
| **Economy** | Nearby merchants, merchant inventory, bounties, clear bounties |
| **Magic** | Spell details (cost/school/effects), enchantment info, magic resistances, disease/vampire/werewolf status |
| **Actions** | God mode, immortal mode, collision toggle, save/load game, set time, notifications |
| **Events** | 17 event types: combat, death, quests, location, inventory, equip, hits, spells, activate |
| **Utility** | Console commands (with output capture), form search, load order, SKSE plugin scanner, game safety check |
| **Papyrus** | Function catalog (3,389 functions from 166 scripts), script function lookup, VM call bridge |

### Smart Features

- **Paged output** — large responses (inventory, spells, perks) support page/pageSize params. `page=0` returns count-only summary
- **Character blueprint** — single-call export of entire character state (skills, perks, spells, shouts, equipment, inventory, appearance, factions, resistances)
- **Event system** — 17 event types with framework noise filtering and type/exclude filters
- **Game safety checker** — detects unsafe states (loading, kill moves, saves) before executing commands
- **HUD notifications** — in-game notifications for all actions
- **Loot scanner** — finds and ranks nearby container contents by value
- **Snapshot** — exports blueprint + saves game with matching timestamped names

## Requirements

- **Windows 10 or 11**
- **Skyrim SE/AE 1.7.104.0** — required runtime acceptance passed for the recorded installed candidate; supplemental 1.6.1170.0 basic smoke is not full-version certification
- **SKSE64** ([skse.silverlock.org](https://skse.silverlock.org/))
- **Address Library for SKSE** ([Nexus](https://www.nexusmods.com/skyrimspecialedition/mods/32444))
- **.NET 10 Runtime** ([download](https://dotnet.microsoft.com/download/dotnet/10.0))
- **Claude Desktop** ([claude.ai/desktop](https://claude.ai/desktop))

This branch is not an installed or runtime-certified release. VR, future 1.7.x versions, and older runtimes that metadata may permit loading are not covered by its support claim. Installation and game testing require separate authorization; loader acceptance is not evidence of compatibility.

## Installation

1. Extract the `Data` folder into your Skyrim directory (or install via MO2/Vortex)
2. Install .NET 10 Runtime if not already installed
3. Configure Claude Desktop (see below)
4. Launch Skyrim via SKSE, then open Claude Desktop

## Claude Desktop Configuration

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "skyrim": {
      "command": "dotnet",
      "args": ["<SKYRIM_PATH>\\Data\\SKSE\\Plugins\\SkyLinkAI_Server\\SkyrimMCP.dll"]
    }
  }
}
```

Replace `<SKYRIM_PATH>` with your Skyrim installation path.

## Usage

1. Launch Skyrim via SKSE
2. Open Claude Desktop
3. Just ask. Anything.

```
"Give me 5000 gold and teleport me to Solitude"
"What's the strongest NPC nearby and what are they carrying?"
"Export my character blueprint to a file"
"Scan for valuable loot in nearby containers"
"Make it snow, then toggle god mode"
"Find the Remiel quest and show me who fills each alias"
"Spawn 5 bandits and monitor the combat"
"What Papyrus functions does the Experience mod expose?"
```

With 87 tools covering player state, inventory, quests, NPCs, world interaction, combat, economy, magic, events, and a Papyrus VM bridge to 3,000+ mod functions — if Skyrim can do it, Claude can probably help.

See **[USAGE.md](USAGE.md)** for the full tool reference and advanced features.

## Building from Source

The audited profile is VS2022 Community, source-built SDK and plugin, SE/AE enabled, VR/tests/Xbyak disabled, static CRT/triplet, and Release `/Od /Ob0 /DNDEBUG`. C++23 is fixed where supported, otherwise `/std:c++23preview`. The preset selects the same VS instance for vcpkg even during automatic regeneration.

```powershell
# Prerequisites: VS2022 Community C++ workload, CMake 3.21+, .NET 10 SDK
$env:VCPKG_ROOT = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg"

# One-time clone; do not overwrite a user-owned checkout.
git clone --depth 1 --branch v4.39.5 --recurse-submodules --shallow-submodules https://github.com/MinLL/CommonLibVR.git SkyrimMCPPlugin/extern/CommonLibVR

# Configure/build an isolated native candidate; no installed-game copy.
Push-Location SkyrimMCPPlugin
cmake --preset default -B build/minll-candidate
cmake --build build/minll-candidate --config Release --parallel 2
Pop-Location

# Companion server requires an owner-local SkyrimMCP/SkyrimMCP.snk (ignored).
dotnet build .\SkyrimMCP -c Release

# Full package requires that signing key and a fresh output directory.
# Configures/builds the default build tree, checks DLL hashes, bundles notices.
.\build_release.ps1 -Version "1.0.0" -OutputDir "release-minll-candidate"
```

Use a local fork signing identity, not an invented copy of the upstream private key. In a VS Developer command prompt, `sn -k 2048 SkyrimMCP/SkyrimMCP.snk` provisions a key for a fresh checkout; never overwrite an existing owner key or commit `.snk` files. This changes the fork's strong-name identity, not the stdio/MCP or named-pipe contracts.

Configuration requires clean MinLL revision `550cc4fb9114649dcf526d1f3d73d710c5d7003b` and vcpkg baseline `ee12231b20c95013c6638d845d04c91559a1d1ff`. It generates a SHA-256-guarded non-VR `TESObjectREFR` header overlay for the SDK, SDK PCH, plugin and plugin PCH; dependency sources remain unchanged. Preserve any old `extern/CommonLibSSE-NG` checkout, but do not use it for this branch. Do not manually patch the pinned SDK or reuse a prebuilt library.

The release script never deletes an existing output directory, rejects package/native version mismatch, stops on native-command failure, and refuses stale or hash-mismatched DLL fallback. Its outputs are local candidates, not automatic deployment or runtime certification.

## Migration evidence — 2026-10-12

**State:** offline source/build/package gates and the required runtime scenarios passed for the owner-approved **1.7.104.0-only** scope on STD/iSTD_SkyrimMCM-skylink with the installed candidate hashes below. Coverage includes startup/pipe, unchanged player/inventory/cell/NPC/quest/menu/combat queries, console/Papyrus, owner-observed HUD, independent God Mode restoration, equipment/death events, known-dead/combat/group state and bounded asynchronous save/exact reload. Positive group and quest-state checks have independent native/engine corroboration. Exact checkpoint restored the tested baseline and God Mode OFF; saves intact. This is scoped acceptance, not every tool/event or version; damage immunity and controlled single-attack timing/stance are unverified. The owner accepted the historical missing prior-installed-DLL backup as a closeout exception, not a performed backup or old-binary rollback. Future installations still require preservation before mutation. Full earlier-version acceptance remains deferred. OpenSpec stays intentionally ignored; package closeout evidence follows.

**Supplemental 1.6.1170.0 basic smoke PASS:** ADT/iADT_harness-smoke startup/basic queries/player-console reads, resumed Math.abs callback, owner-observed HUD and corrected quoted NPC GetDead passed using the same candidate. `"0001A681".getdead` returned0.00 on both ADT1.6.1170 and STD1.7.104, matching the identified living actor. The original unquoted test command was the syntax error, not an observed version-only incompatibility; no native patch needed. Basic exercised-path compatibility, not full1.6.1170 certification; no God/combat/event/save-load fixtures. Windows beep was a viewing cue, not Skyrim audio coverage.

The dated notes below preserve historical milestones and failures. Older pending/unknown statements are superseded by this current state and the later completed scenarios; they are not current operating blockers.

The paired Claude final read-only audit independently confirmed the original package hashes, loader metadata, system-only imports and unchanged C# surface; no source/ABI/package blockers were found. Its machine-specific VS2022 Community preset observation remains documented. The then-missing packaged .NET notices were completed and verified during local closeout below; that audit itself is not runtime evidence.

### Built and packaged artifacts

Runtime-tested package preserved at `SkyrimMCPPlugin/build/minll-candidate-20261012/package/`. Original native targets were source-built with MSVC 19.44.35229.0 / VS2022 Community and the pinned vcpkg baseline. Actual SDK/plugin PCH and source command records showed `/Od /Ob0 /DNDEBUG /MT /std:c++23preview`, overlay-before-SDK include order and no Xbyak definition.

| Artifact | SHA-256 |
|---|---|
| Runtime-tested package native DLL (original fresh/canonical/package equality) | `f37cafa7790b964b9f64359b1babf8525ad5f668952b1e579897f64f8c7573b3` |
| Runtime-tested package `SkyLinkAI_Server/SkyrimMCP.dll` (original publish/Release equality) | `22eb89b404057be10fe396c3c706793e1bbdfc04e7e3ca48b485107f34f5a8b3` |
| Closeout rebuild native DLL (current fresh/canonical/package equality; not installed/tested in game) | `612a090a01222fd2f9d39bebe87ccd013befd36f8b25b7641d4cb246c83aae7e` |
| Closeout rebuild server (stdio/signature verified; not installed/tested in game) | `a11dff0048894345d981ec2fd679eeff25621b7af49b1371cc0ee86246631916` |

The original runtime-tested fresh and packaged PE records export `SKSEPlugin_Load`, `SKSEPlugin_Query` and `SKSEPlugin_Version`: plugin name `SkyrimMCPPlugin`, version 1.0.0, classic compatibility `0x1`, extended compatibility `0x3`, minimum SKSE 0. Original offline import inspection found Windows system dependencies, not OpenVR or dynamic fmt/spdlog/VC-runtime DLLs. This artifact inspection alone is not a successful SKSE load.

**Local release closeout — 2026-10-13:** `SkyrimMCPPlugin/build/closeout-20261013/package-final/` was built through the actual release script. All 31 published NuGet dependencies have exact-version MIT license text and cached upstream metadata/copyright; all 29 applicable third-party notice payloads were compared with restored packages or pinned upstream files. Native notices remain bundled. Real packaged stdio initialization and all 87 tool definitions matched the runtime-tested server exactly; both owned servers exited 0 without any game tool call. Packaged strong-name signature verified. Raw proof: `SkyrimMCPPlugin/build/closeout-20261013/package-verification.json`. The rebuild's native/server hashes differ from the installed runtime-tested candidate: this new package is offline-verified only and requires installation/runtime smoke before claiming its bytes were tested. No installation, game action or publication occurred during closeout.

**OpenSpec closeout:** all 23 tasks closed, with the prior-DLL item closed solely by the accepted historical exception. Strict validation passed the change and both synced main capabilities (3 passed, 0 failed). Local archive: `openspec/changes/archive/2026-10-13-migrate-minll-commonlibvr-1-7/`, including `verification.md`; main capabilities live under `openspec/specs/`. The entire OpenSpec tree remains intentionally ignored. No publication, commit or push was performed during this closeout.

The existing signing requirement was retained. An ignored owner-local 2048-bit fork key was generated; `sn -vf` verified the published server signature. The real packaged server answered stdio `initialize` as **SkyLink AI 1.0.0**, then returned **87** tool definitions from `tools/list`, including console, God Mode, notifications, equipment, Papyrus and save input schemas. No game tool was invoked. Historical headline tool counts are not the API oracle.

### Source contracts and ABI smoke

The source oracle is `Protocol.cpp`, `GameInterface.h`, manager response/error construction, and unchanged `SkyrimMCP/Tools/*.cs` signatures/defaults. Request `{id,action,params}` and response `{id,success,data}` or `{id,success,error}` remain newline-framed over `\\.\pipe\SkyrimMCP`; log identity remains `SkyrimMCPPlugin.log`. `kDataLoaded` startup, TaskQueue game-thread routing, pipe-thread Papyrus calls/catalog work, event polling and fire-and-forget save acknowledgment remain unchanged.

Console success retains `executed`, `command` and optional `output`; caught-failure manager data retains `error`, `command`, `partialOutput` (the existing protocol promotes the error string). God Mode retains `godMode`. Native notifications retain `shown`/`message`, and equipped items retain `equipped` with unsigned armor `slotMask`. Papyrus unavailable-VM/error, arguments, callbacks and timeouts are preserved. These source contracts and the stdio metadata smoke are not an installed-game response baseline.

The five permanent console-selector assertions compile, including the rollover where the old patch-only predicate selected 21890 for 1.7.99/104 instead of 441582. A disposable MSVC `/Od /Ob0` fixture exercised the actual pinned `Actor` methods with false/true death and combat states and a known group pointer: uncorrected header exited 71 at the wrong-slot guard; corrected header passed. Linked fixture instructions confirmed:

| Consumer | Uncorrected slot | Corrected slot |
|---|---|---|
| `IsDead` | `0x9A` | `0x99` |
| `GetCombatGroup` | `0xD5` | `0xD4` |
| `IsInCombat` | `0xE4` | `0xE3` |

The fingerprint guard accepted the pinned header/transformation and rejected a changed-header fixture. A real configure rejected an untracked dirty-SDK probe, which was removed immediately. Package version mismatch and existing-output refusal were exercised; a real CMake failure with a canonical DLL present emitted no package and did not fall back to that DLL. Positive packaging verified fresh/canonical/package equality and included the SDK, historical console, OpenVR and compiled dependency notices. Disposable fixtures are removed; selector assertions remain.

`GetImpl()` replaces the removed direct Papyrus member; compiler-demonstrated API adjustments are `GetSlotMask().underlying()` and `SendHUDMessage::ShowHUDMessage()`. God Mode ID `404238` and music conversion remain unchanged; the pinned `BGSMusicType` header still places the `BSIMusicType` base at `0x20`. Runtime notification and music behavior have not been exercised.

### Offline mappings and remaining runtime gates

Decoded libraries: `D:/Modlists/STD/mods/Address Library for SKSE Plugins/SKSE/Plugins/versionlib-<version>.bin`. ID 21890 is absent in all four; compiler ID 441582 and God Mode ID 404238 are present:

| Runtime | Library format | Compiler RVA (441582) | God Mode RVA (404238) | Executable semantic inspection |
|---|---|---|---|---|
| 1.6.1130.0 | 2 | `0x33D5B0` | `0x3182666` | Missing executable evidence |
| 1.6.1170.0 | 2 | `0x33D6A0` | `0x319B9D6` | Console register/entry-point checks and `tgm` getter/setter linkage inspected |
| 1.7.99.0 | 5 | `0x343D00` | `0x3244C86` | Missing executable evidence; equal RVAs are not semantic proof |
| 1.7.104.0 | 5 | `0x343D00` | `0x3244C86` | Console register/entry-point checks and `tgm` getter/setter linkage inspected |

Library SHA-256 fingerprints:

- 1.6.1130.0: `5314ef0ece3b9300e811030329628f3917c04faa7dd600300540d74ff71a527a`
- 1.6.1170.0: `c4093c569a3c83b26587f4b9ea4c55de9ae6e73b84a2af9fb3fbd30e2fe0d452`
- 1.7.99.0: `184fca0c834e0d2523b450d18ea32c9fbf9f6295e88e936712b7360f1fccc4ec`
- 1.7.104.0: `8aab3dd251d135b849bd983f86a4a205c920fa3e81f8e30c0e63ccfef9423842`

Inspected executable identities:

- `D:/Modlists/ADT/Game Root/SkyrimSE.exe`, 1.6.1170.0: `8f2116b073d5d74713b39a2b11cd35e6b745a760e690e1f46fc7ae76a9c0f48a`
- `D:/SteamLibrary/steamapps/common/Skyrim Special Edition/SkyrimSE.exe`, 1.7.104.0: `846efccf0c1374d71f892907f46549560f2fcb0a75cb87a3eed438baa0f1402f`

No exact 1.6.1130.0 or 1.7.99.0 executable was located in completed scoped checks; machine-wide absence is not asserted. The owner subsequently approved 1.7.104.0-only initial acceptance, so these missing checkpoints are deferred rather than blocking the current candidate. Obtain exact executables before expanding acceptance; do not infer semantics solely from IDs or equal RVAs.

Follow-up offline verification on 2026-10-12 inspected actual PE file/product versions and SHA-256 values for five executable candidates, without running them. STD `GameRoot` and the Steam install are both 1.7.104.0 with the recorded `846efc…` hash; ASSOS `StockGame` and ADT `Game Root` are both 1.6.1170.0 with the recorded `8f2116…` hash. The existing Steam content depot (`C:/Program Files (x86)/Steam/steamapps/content/app_489830/depot_489833/SkyrimSE.exe`) is also 1.6.1170.0, SHA-256 `c434208894f07f604b852f29b8edc3a58c4de63de783373733e72b2b73f33be9`. None supplies the missing exact checkpoints. Version-labelled backup searches produced mod packages, not a positively identified target executable; archive contents and the whole machine were not exhaustively searched.

The pinned SDK independently corroborates the implementation in source: `src/RE/S/Script.cpp:57–61` selects AE ID 441582 at/after 1.6.1130 using full-version `AE_CHECK` and the same compiler/name/target argument order; `src/RE/P/PlayerCharacter.cpp:27–30` reads God Mode ID 404238 as `bool*`. That confirms agreement with the supported SDK, not executable-backed semantics for the missing versions. Scoped SDK/iVault/IntelEngine research found no additional original binary-backed proof closing those two gates.

The current 1.7.104.0 profile/save and prerequisites are identified, and startup/basic reads passed below. Remaining mandatory scenarios require their own bounded authorization: additional query schemas, console output, HUD notification, Papyrus callbacks, events, reversible God Mode and independently known death/combat/group states; asynchronous save/reload only when authorized. No full runtime-verified compatibility or archive until these scenarios pass. Deferred 1.7.99.0/1.6.x checks remain unverified.

### Installed background smoke — 2026-10-13

Owner-installed mod: `D:/Modlists/STD/mods/SkyLinkAI - 1.7.104 candidate`, enabled in the selected `iSTD_SkyrimMCM-skylink` MO2 profile. Process 24612 ran `D:/Modlists/STD/GameRoot/SkyrimSE.exe` and loaded that mod's native DLL plus `skse64_1_7_104.dll`; installed native/server hashes matched the candidate hashes above. .NET 10.0.3 was available. Startup log recorded successful plugin load, data-loaded initialization, 17 event sinks and the named pipe.

The exact `Skylink-test-01.ess`/`.skse` family was copied into `SkyrimMCPPlugin/build/runtime-smoke-20261013T190120Z/save-backup/` with equal source/backup hashes; originals were unchanged at handback. ESS header decoding established player `Skylink-A`, level 1, location `The Drunken Huntsman` (header metadata, not a complete save-state decoder).

The installed server initialized as SkyLink AI 1.0.0 and listed 87 tools. Actual responses: `check_connection.connected=true`; no open menus and no pause/loading/save/combat/dialogue/kill-move state; `get_player_info` matched checkpoint name/level/location; paged `get_inventory` returned item records; `get_cell_info` reported interior `000165B7`, The Drunken Huntsman, with positions equal to the player query. Inventory counts were observed, not independently verified against save contents or UI.

Raw request IDs, timestamps, schemas, responses, process identity and backup fingerprints are in `SkyrimMCPPlugin/build/runtime-smoke-20261013T190120Z/mcp-readonly-smoke.json` (local ignored evidence). The foreground HWND was the same non-game window before and after the block; no activation or input was sent, so this is a bounded background-read pass, not qualification for mutations or every UI operation. No console, Papyrus, notification, event-poll, God Mode, combat setup or save/load operation was invoked. Only the owned MCP server was disconnected (exit 0); Skyrim remained open with the same PID.

### Console and Papyrus smoke — 2026-10-13

On the same ready, connected 1.7.104 process/profile/player, the existing MCP console route executed `player.getav health` and returned `GetActorValue: Health >> 500.00`, matching the fresh player query's health 500. The live Math catalog reported a global `abs(float)` function returning float; `call_papyrus_function` with `Math.abs` and `args="[-12.5]"` returned callback result `12.5`. Both checks passed without repeating earlier assertions or changing game state.

Raw schemas/requests/responses and times are in `SkyrimMCPPlugin/build/runtime-smoke-20261013T190120Z/mcp-console-papyrus.json`. No focus/input operation was issued; foreground handles differed between baseline and handback, so continuous focus isolation is not claimed. Original save/co-save hashes remained unchanged; the owned server exited 0 and Skyrim remained open as PID 24612. The first notification at 19:20:54 UTC returned MCP success but was unobserved because the owner was not watching. The owner explicitly requested another after the expected top-left presentation was explained; following a five-second delay, `SkyLink HUD test 2` was sent once at 19:23:30 UTC. MCP returned success, the owned server exited 0, and the owner confirmed “Saw it!”: **HUD presentation PASS (owner-observed)**, not inferred from the wrapper receipt. Raw dispatch evidence: `mcp-hud-once.json` and `mcp-hud-owner-repeat.json` in the same evidence directory. Later events/God Mode/actor-state/save-reload checks remain pending.

God Mode state-test preflight at 19:27 UTC was **BLOCKED**, before any toggle: the live game reported `isPaused=true` despite `safe=true`. Read-only `ReadProcessMemory` at verified 1.7.104 image RVA `0x3244C86` (AE ID 404238) established the initial boolean byte as 0/off, but no transition/restoration is claimed. Zero toggle requests, input/focus commands, damage/combat operations or saves were sent. The blocking-step Pushover notification was delivered; the owned server exited 0, read-only process handle closed, original ESS/SKSE hashes unchanged and game PID 24612 left open. Raw evidence: `mcp-godmode-preflight-blocked.json` in the same evidence directory. Pause cause was not established; resume only after a fresh agreed readiness checkpoint.

After the owner explicitly requested a five-second delay followed by on/off and in-game notifications, fresh 19:31 UTC preflight reported unpaused/ready. Two `toggle_god_mode` requests returned On/true then Off/false, and independent read-only engine observations at RVA `0x3244C86` confirmed byte sequence `0 → 1 → 0`; initial off state was restored. The tool automatically issued its On/Off notifications; this block's visible presentation awaits owner observation. State-transition/restoration **PASS**, not damage-immunity proof. The game HWND was foreground at both endpoints (owner-controlled); no activation or keyboard input was issued, and this is not an unfocused-mutation qualification. ESS/SKSE hashes unchanged, server exit 0, read handle closed and game left open. Raw evidence: `mcp-godmode-on-off.json` in the same evidence directory. The earlier paused preflight remains historical, not a current blocker.

At the owner's explicit staged-test request, a fresh 19:36 UTC check found the game unpaused and non-foreground; one God Mode toggle changed the independently read engine byte `0 → 1`. All nine foreground samples across the bounded preflight/on/observation window were non-game HWNDs; no activation/input commands were issued. **Background-on state change PASS for this operation/build/profile only**, not qualification for all mutations or HUD visibility. After owner `ready for off`, the 19:37 UTC foreground/readiness check passed, one toggle returned `God Mode Off`/false, and independent engine observations confirmed `1 → 0`, restoring the original off state. The owner confirmed “Saw it”: **Off notification presentation PASS (owner-observed)**. Save hashes unchanged; owned servers exited 0 and read handles closed. Raw evidence: `mcp-godmode-background-on.json` and `mcp-godmode-foreground-off.json`. No damage, save/load, activation or keyboard operations were sent.

### Actor/equipment baseline and event preparation — 2026-10-13

The first harness attempt stopped before any game calls because its local tool-name lookup used `get_nearby_npcs`; the live server advertises `get_nearby_np_cs`. The local harness lookup was corrected from the existing discovered schema, with no public tool rename or native change; the stop alert was delivered. Historical raw evidence: `mcp-actor-event-baseline.json`.

The corrected read-only block passed connection/readiness and actor/equipment response paths. Player actor `00000014` matched Skylink-A/The Drunken Huntsman and returned `isDead=false`/`isInCombat=false`; combat response was `inCombat=false`. Nearby NPC detail for Anoriath `0001A680` agreed with list identity/death state. Equipment returned Roughspun Tunic body mask4, Footwraps feet mask128 and the right-hand sword. This is query execution/cross-query consistency and an idle/living baseline, not independent positive dead/active-combat/non-empty-group acceptance. Raw evidence: `mcp-actor-event-baseline-corrected.json`. Original save hashes unchanged; owned server exited0. No mutation, focus or input operation was sent.

Source inspection established that Inventory menu open/close is not a registered event; `open_close` is not a menu-event contract. At baseline handback, the reversible Footwraps trigger was proposed but not yet authorized; it was subsequently authorized and passed as recorded below. Independently known positive actor-state fixtures remain pending.


### Reversible equipment event smoke — 2026-10-13

Owner selected agent-run Footwraps unequip/re-equip. The first event-baseline poll exceeded the throwaway Python client's default64KiB newline limit; it stopped before either console command, delivered the authorized failure alert and disconnected. Footwraps were still equipped. Historical evidence: `mcp-equipment-events.json`. This is a client-harness failure, not a demonstrated plugin failure; that initial consumed baseline was not captured completely.

With only the local client response limit increased to4MiB, a fresh 19:56 UTC block verified the same instance/character/readiness and captured a complete113-event baseline. Exactly `player.unequipitem 0003CA00` then `player.equipitem 0003CA00` were sent, each once. Fresh equipment queries independently observed removal then exact original equipment restoration; Footwraps inventory count stayed1→1. The after-poll contained exactly two events, both `equip` for `0003CA00`/Footwraps, with ordered `equipped=false` then `true`: **equipment event delivery/restoration PASS**. This does not exercise all17 event types.

Original save pair hashes unchanged, owned server exit0, same Skyrim PID still running. No saving, window activation or keyboard input. Foreground HWND was non-game at both endpoints; no continuous focus qualification is claimed. Raw evidence: `mcp-equipment-events-corrected.json`.

### Protected actor fixture and checkpoint recovery — 2026-10-13

The owner authorized a protected disposable actor/combat/death test and exact checkpoint rollback. An initial paused flag stopped preparation with no mutations; after the owner's background/unpaused observation, a distinct read-only observation found no menus, `gameIsPaused=false`, and native console GameHour5.97→5.99. No foreground activation/input was used. `search_forms` did not find QASmoke by its editor ID; a format-aware read of installed `Skyrim.esm` decoded CELL00032AE7/EDIDQASmoke. A loaded ordinary Mudcrab base00021875 was discovered. This establishes identities, not cell isolation; actual isolation was checked after entry.

SkyrimNet.dll is loaded and overwrite Harness.yaml has `enabled:true`. Eight external SQLite databases were preserved by online backup from read-only sources, with quick_checkok and hashes; snapshots are per-database, not atomic across the collection. They were refreshed immediately before the authorized reload. This is preservation, not a claim that Harness external records remained unchanged through timeline rewind. Evidence: `external-precombat-backup.json`, `external-prereload-backup.json`.

**Save creation/preservation PASS:** explicit fresh checkpoint `Skylink-migration-precombat-20261013T202221Z` produced nonempty stable ESS/SKSE files and hash-equal backup copies. God Mode original engine byte was0. No source checkpoint was overwritten. Evidence: `mcp-precombat-checkpoint.json`.

**Combat-group fixture BLOCKED:** God guard independently changed0→1; QASmoke's actual cell00032AE7 and empty nearby-actor list were verified. Exactly one Mudcrab was spawned, base00021875/refFF000E86, alive/nonessential/nonprotected; independent engine GetDead returned0.00. One targeted StartCombat produced repeated `inCombat=true` responses, but no `targets`/`targetCount`/`allies` fields appeared within12seconds. The test stopped and alerted; no kill/death test or combat-state save was performed. This does not by itself distinguish nullable fixture behavior, wrong player accessor or a migration ABI issue. Evidence: `mcp-protected-actor-fixture.json`.

**Authorized exact reload and bounded persistence PASS:** owner selected Restore now. Exact named load returned the character to original cell000165B7/The Drunken Huntsman, with matching name/level/health/magicka/stamina, original equipment and queried inventory-page form/count pairs. An overly strict throwaway-harness position assertion stopped on Z delta-0.7353515625; X/Y matched within rounding. No second load or position correction was issued. The recorded discrepancy is not an exact-position persistence pass and its cause is unproven. From the independently established safe restored state, original God Mode OFF was explicitly completed and independently read1→0. Original Skylink-test-01 and new checkpoint family hashes unchanged, owned servers exit0, same Skyrim process left open. Evidence: `mcp-precombat-checkpoint-recovery.json`, `mcp-precombat-recovery-completed.json`. Dead-actor and nonempty-group acceptance remain unpassed.

**Static group-access diagnosis:** exact installed1.7.104 executable SHA256846efccf0c1374d71f892907f46549560f2fcb0a75cb87a3eed438baa0f1402f and dense Address Library mapped player vtable ID208040 to RVA019296C0. SlotD4 is RVA0076ACD0 (`mov rax,[rcx+0x9E0]; ret`); D5 writes that same field. E3 reads the separate combat bit at `this+0xBEB`. Thus the selected getter is a real player-group getter, not an inherited constant-null/wrong-slot function. This is static executable evidence; it does not prove the runtime group value/lifecycle or exclude installed hooks. The SDK's packed info block/version-aware accessors are separate from VR layout comments; no direct-offset shortcut or speculative native patch was made. The fixture started combat on the enemy, not the player, so it did not establish a populated player group. Runtime group allocation/fixture engagement remains the leading area to discriminate, with navmesh/engagement and installed hooks still unproven alternatives. Evidence: `native-player-combat-group-static.json`.

### Revised native actor fixtures — 2026-10-13

Owner asked to try again after the background native-engagement proposal. Fresh checkpoint `Skylink-migration-retry-20261013T213036Z` was created, ESS/SKSE completeness observed and hash-equal backups preserved; eight SkyrimNet databases were consistently snapshotted before testing and refreshed before reload. No focus activation or keyboard input was sent. Across the four bounded blocks, all200 foreground samples were non-game; this is sampled qualification for the exercised operations/build/profile, not proof about all operations or uninterrupted focus ownership.

**Known dead actor PASS:** empty QASmoke verified before spawning one ordinary Mudcrab base00021875/refFF000E07. API `isDead=false` and engine GetDead0.00 established alive. One dedicated kill of only that temporary, nonessential/nonprotected actor produced API `isDead=true`, engine GetDead1.00 and a `death` event with matching actorFormId and deadtrue. Actor health remained55 in the response; death was not inferred from health. Evidence: `mcp-revised-death-fixture.json`.

**Combat-bit transition/agreement PASS; positive group UNKNOWN:** a distinct temporary Mudcrab FF000DD3 was identified. One `player.startcombat FF000DD3` dispatch left the observed player bit false and native group null; dispatch alone was not accepted as player engagement. One enemy `FF000DD3.startcombat 00000014` then produced repeated native player combat-bittrue/API inCombattrue observations, followed by both false. Live read-only observations confirmed the expected player vtable/getter address and native group pointer0 at every sample. The API omitted group fields consistently. No player combat-start event was captured, so event-corroborated natural player engagement is not claimed. This confirms a native-null fixture outcome, not a reporting mismatch; it does not exercise nonempty group arrays. Blocker alert delivered; no speculative code patch, repeated StartCombat or forced group pointer. After capture only the verified second temporary actor was killed for the agreed encounter cleanup. Evidence: `mcp-revised-player-combat-fixture.json`.

**Recovery PASS:** the exact fresh checkpoint loaded original cell000165B7/The Drunken Huntsman, matching character/level/health/magicka/stamina, equipment and queried inventory form/count pairs. Position delta was0 in this run, without asserting general exact-position persistence. Original God Mode OFF independently restored1→0; native/API combat flags false. Original Skylink-test-01 and fresh checkpoint families unchanged, owned servers exit0 and same Skyrim PID left open. No additional game operations after handback. Evidence: `mcp-revised-actor-checkpoint.json`, `mcp-revised-actor-recovery.json`.

**Normal-attack staging (historical, completed):** fresh checkpoint `Skylink-migration-attack-20261013T214120Z` ESS/SKSE and external DB snapshots preserved. One temporary Mudcrab FF000E54 in verified-empty QASmoke was identified nonessential/nonprotected, given current health1000 (reported base healthMax55), and moved near the player; measured distance17.57. God guard independently ON, native combat bitfalse/groupnull before handoff. No StartCombat or camera-setting change. Evidence: `mcp-normal-attack-checkpoint.json`, `mcp-normal-attack-fixture-setup.json`. This staging state is superseded by the completed recovery below.

**Positive combat-group query PASS; controlled attack sequence NOT CAPTURED:** owner reported crouching after Alt-Tab and repeated accidental hits before capture/cue. No cue or further attack was requested. At21:50:15UTC the independently read native player group was non-null (`0x1f501781d80`) and combat bittrue; the unchanged MCP query returned inCombattrue, targetCount1 and target refFF000E54. The separate NPC query matched identity, living/combat state and health973.8699951171875/max55. This proves the positive target-array query path against the intended fixture, not a single standing attack's timing, stance, combat-start event or causal sequence. Only the verified temporary actor was killed; combat returned idle. Evidence: `mcp-normal-attack-aborted.json`.

**Exact recovery PASS:** all eight external SkyrimNet databases were consistently snapshotted before rewind. Exact checkpoint load restored Skylink-A/The Drunken Huntsman000165B7, queried values/equipment/counts and weapon charge100; position delta0 in this observation. Original God Mode independently restored1→0, combat false, source Skylink-test-01 and fresh ESS/SKSE hashes unchanged, owned server exit0, same game left open. A restarted-client launch first failed locally on a wrong server path, before any game command; alert delivered, failure preserved in `mcp-normal-attack-recovery.json`. The discovered installed path was hash-verified before completing recovery in `mcp-normal-attack-recovery-completed.json`. No focus activation/raw input or further gameplay after handback; vanity settings unchanged.

### Read-only quest acceptance — 2026-10-13

**Quest consumer scenario PASS:** the unchanged installed C# `get_quest_info` returned Before the Storm0004E50D, currentStage23, completedfalse and objective records. On the same fresh-ready process, read-only engine console `getstage 0004E50D` returned23.00 and `GetQuestCompleted 0004E50D` returned0.00, independently matching the selected quest's stage/completion. Same original cell retained, God Mode byte0 before/after, owned server exit0 and game left open; no quest mutations, save/load, activation or input. Sequential reads are not an atomic snapshot; objective contents and other quests were not independently certified. This closes the last required runtime query scenario, not the historical prior-DLL-backup gap or publication concerns. Evidence: `SkyrimMCPPlugin/build/runtime-smoke-20261013T190120Z/mcp-quest-query-acceptance.json`.

### Supplemental ADT 1.6.1170 lightweight smoke — 2026-10-13

Owner selected ADT profile `iADT_harness-smoke` (verified filesystem/MO2 spelling), exact save `skylink-161170-01`, loaded/unpaused in The Drunken Huntsman. Process52104 ran the independently versioned/hashed1.6.1170 executable, loaded matching skse64_1_6_1170.dll and the candidate native path. Native/server SHA256 matched the1.7.104-tested candidate above. Address Library format2/hash matched the recorded1.6.1170 library, SKSE log reported2.2.6, current startup log recorded data-loaded initialization,17-event registration and pipe listener, and current SKSE log named the supplied save. Exact ESS/SKSE backups hash-equal; header characterSkylink-1.6/level1/location matched live player state.

**Basic read smoke PASS:** actual MCP connection, unpaused/readiness, unchanged player/inventory/cell/menu/idle-combat/actor/nearby-NPC/quest responses. Player health500 matched engine `player.getav health`500.00; API alive matched engine `player.getdead`0.00. Elrindir0001A681 list/detail identity and living state agreed; active Before the Storm returned stage10. This is limited query execution/state consistency, not independently certified inventory/objective content or positive death/combat/group fixtures.

**Sequence STOPPED:** extra independent NPC-death observation `0001A681.getdead` returned `Script command "0001A681.getdead" not found.` Its executedtrue receipt was not accepted as an effect. No syntax retry, provider switch, mutation or compatibility fix; cause not diagnosed and no ABI failure inferred. Alert delivered, owned client/server exit0, same game left open, named save family hashes unchanged. Math.abs catalog discovered, but Papyrus callback/quest console comparison/HUD dispatch did not run after the stop. God Mode untouched; no events/save-load/combat fixtures, activation or input. Completing the remaining lightweight Papyrus/HUD checks requires a distinct owner-authorized resumption, not rerunning this failed command. Full1.6.1170 acceptance remains deferred. Raw backups/fingerprints/requests/responses: `SkyrimMCPPlugin/build/adt-smoke-20261013T221429Z/`.

**Separately authorized Papyrus continuation PASS:** after owner allowed non-foreground continuation, fresh same-process readiness/original cell verified; one static Math.abs(-12.5) callback returned12.5 through the existing MCP tool. Exact save family hashes unchanged, same cell retained, owned server exit0 and game open; no failed-command retry, HUD dispatch, God toggle, save/load, activation or input. This supersedes only the earlier unexecuted Papyrus status, not the NPC command rejection. HUD awaits owner viewing readiness. Evidence: `adt-smoke-20261013T221429Z/mcp-papyrus-resumed.json` under the same build evidence root.

**HUD presentation PASS (owner-observed):** after owner ready, five-second viewing delay and fresh foreground/readiness verification, exactly one `SkyLink ADT smoke test` notification was acknowledged alongside an authorized short Windows Beep880Hz/150ms. Beep API accepted; timing was concurrent, not an atomic in-game audio/HUD operation. Owner replied “success” to the visibility/audibility question. Foreground released, owned server exit0, exact save hashes unchanged and same game left open; no replay on the intervening second ready, God toggle, input or further game actions. Windows sound is not proof of Skyrim audio/music compatibility. This supersedes earlier pending HUD notes and completes the lightweight smoke with the NPC-command limitation retained. Raw: `adt-smoke-20261013T221429Z/mcp-hud-windows-cue.json`, `hud-owner-observation.json`.

**Explicitly requested exact retry — rejection reproduced:** owner asked to retry the rejected command. Fresh same-process unpaused/readiness, original cell and living Elrindir `0001A681`/base `00013B9E` were verified, then exactly one additional `0001A681.getdead` returned the same `Script command "0001A681.getdead" not found.` Stopped, alerted and disconnected without alternate syntax, gameplay mutation or a compatibility patch. This establishes repeatability under two ready observations and weakens a transient-readiness explanation; it does not diagnose parsing, reference resolution or compiler context, nor prove an actor-query ABI failure. Independent console corroboration of this NPC's death state remains unavailable. Evidence: `adt-smoke-20261013T221429Z/mcp-npc-console-exact-retry.json`.

**Exact cross-instance comparison — same rejection on 1.7.104:** owner closed ADT and opened STD/iSTD_SkyrimMCM-skylink. Fresh process21544/runtime1.7.104 and identical installed native/server hashes verified; current SKSE log named Skylink-test-01, and live character/cell were Skylink-A/The Drunken Huntsman. Elrindir0001A681/base00013B9E was alive via native detail query. Exactly one `0001A681.getdead` produced the identical script-command-not-found response. Stopped/alerted/disconnected; same game open, original ESS/SKSE hashes unchanged, no reload/God/combat/input/focus mutation. This disconfirms a failure unique to1.6.1170 for the observed command; earlier1.7.104 FF-reference StartCombat successes were not this exact command. The different mod profiles still prevent general causal attribution to runtime, parsing or compiler context; no source fix made. Evidence: `SkyrimMCPPlugin/build/std-npc-compare-20261013T223131Z/mcp-exact-npc-console-comparison.json`.

**Documented quoting verified on STD:** [UESP's console syntax reference](https://en.uesp.net/wiki/Skyrim:Console#General_Information) explicitly warns that unquoted leading-zero RefIDs may produce command-not-found and documents quotes. After owner authorization, fresh same-process ready state and living Elrindir verified, exactly one `"0001A681".getdead` returned `GetDead >> 0.00`, matching API alive. Same actor/runtime/candidate as the rejected unquoted command; quote syntax changed, no source patch. This demonstrates command acceptance with the documented syntax and supports the parser/reference-token explanation; it does not claim a corrected ADT run or comprehensive targeting semantics. Original save hashes unchanged, owned server exit0, game open; no further game actions. Evidence: `SkyrimMCPPlugin/build/std-quoted-npc-20261013T223505Z/mcp-quoted-getdead.json`. Use quoted RefIDs for leading-zero dot-notation targets; do not rely on `prid` persisting between separate helper calls.

**Corrected ADT command PASS:** after owner switched back, fresh process61168/runtime1.6.1170, selected iADT_harness-smoke, identical native/server hashes, current log `skylink-161170-01` and live Skylink-1.6/The Drunken Huntsman were verified. Living Elrindir0001A681/base00013B9E queried; exactly one `"0001A681".getdead` returned `GetDead >> 0.00`, matching API alive. The corrected command is now accepted on both tested runtimes, resolving the extra smoke failure as unquoted-reference test syntax; earlier unknown/pending syntax notes are historical. No plugin change, retry/fallback, God/combat/quest/save-load/input/focus mutations. Exact ADT ESS/SKSE hashes unchanged, owned server exit0, ADT left open. The lightweight1.6.1170 smoke passes for its exercised paths, without asserting full positive-state/event/persistence coverage. Evidence: `SkyrimMCPPlugin/build/adt-quoted-npc-20261013T223743Z/mcp-quoted-getdead.json`.

## Project Structure

```
├── SkyrimMCPPlugin/          # C++ SKSE plugin
│   ├── src/
│   │   ├── Main.cpp          # SKSE entry point
│   │   ├── PipeServer.*      # Named pipe server
│   │   ├── Protocol.*        # Command registry
│   │   ├── Helpers.h         # Shared utilities + ResolveActor
│   │   ├── PlayerQueries.*   # Player state + toggles
│   │   ├── NPCManager.*     # NPC/actor operations
│   │   ├── InventoryManager.*# Item operations
│   │   ├── QuestManager.*    # Quest operations
│   │   ├── WorldManager.*    # World interaction
│   │   ├── CombatAnalysis.*  # Combat analysis
│   │   ├── UIManager.*       # Menu state
│   │   ├── UtilityManager.*  # Misc utilities
│   │   ├── PapyrusBridge.*   # Papyrus VM bridge
│   │   ├── EventSystem.*     # Game event sinks
│   │   └── TaskQueue.*       # Game thread dispatch
│   ├── CMakeLists.txt
│   └── vcpkg.json
├── SkyrimMCP/                # C# MCP server (.NET 10)
│   ├── Program.cs
│   ├── IPipeClient.cs
│   ├── PipeClient.cs
│   ├── SkyrimOffsets.cs
│   └── Tools/                # MCP tool classes
│       ├── ToolBase.cs
│       ├── PlayerTools.cs
│       ├── InventoryTools.cs
│       ├── QuestTools.cs
│       ├── NPCTools.cs
│       ├── WorldTools.cs
│       ├── CombatTools.cs
│       ├── UtilityTools.cs
│       └── PapyrusTools.cs
├── build_release.ps1         # Nexus packaging script
├── project_work_items.json   # Feature/bug tracking
├── project_dashboard.html    # Visual project dashboard
├── ROADMAP.md               # Feature roadmap
├── CHARACTER_BLUEPRINT_SPEC.json
└── CLAUDE.md                # Dev guidance for Claude Code
```

## Credits

- Console execution adapted from the [historical MIT ConsoleUtilSSE source](https://github.com/VersuchDrei/ConsoleUtilSSE/tree/0eb69c6c0d7366065f2408180216ec6cd8a40d5e) by VersuchDrei; see `licenses/LICENSE-ConsoleUtilSSE.txt`. No newer GPL source is imported.
- [MinLL/CommonLibVR](https://github.com/MinLL/CommonLibVR/tree/550cc4fb9114649dcf526d1f3d73d710c5d7003b), derived from Ryan-rsm-McKenzie's CommonLib; see `licenses/LICENSE-CommonLibVR.txt`.
- Packaged .NET dependencies follow the published `SkyrimMCP.deps.json` graph. `licenses/dotnet/` in release packages retains each exact package's MIT license, `.nuspec` copyright/repository metadata and available notices. Missing bundled license text uses the pinned upstream [MCP SDK license](https://github.com/modelcontextprotocol/csharp-sdk/blob/2da929914c2d7becbab0a51d1bda171aec4ce9e8/LICENSE), [dotnet license](https://github.com/dotnet/dotnet/blob/89c8f6a112d37d2ea8b77821e56d170a1bccdc5a/LICENSE.TXT), or [AI abstractions source license](https://github.com/dotnet/extensions/blob/f8f779a6ea004bb1f26649719ca77d63a9d9417c/LICENSE) and [notice](https://github.com/dotnet/extensions/blob/f8f779a6ea004bb1f26649719ca77d63a9d9417c/THIRD-PARTY-NOTICES.TXT), retained under root `licenses/`.
- SKSE by Ian Patterson, Stephen Abel, and Paul Shortman

## License

MIT
