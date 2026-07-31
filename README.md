# CDECAD

The all-in-one CDE CAD resource for FiveM. It bundles the tablet, duty system, civilian manager, 911 commands, fingerprint scanner, ALPR camera network, Wraith plate-reader integration, and the ERS bridge into one resource, so you `ensure CDECAD` once and you're done.

## Framework support

CDECAD runs standalone on any server. It talks only to your CDE CAD backend over HTTP, so it behaves the same whether your server is standalone, ESX, QBCore, QBox, NAT2k15, or vRP. Duty, callsigns, and civilians are driven by the CAD itself: players pick a civilian they own with `/setciv` and go on duty with `/d`.

If you run a framework and want its **characters and vehicles** to show up in the CAD automatically, add one more resource:

- **[`cde-cad-sync`](../cde-cad-sync)** auto-detects ESX / QBCore / QBox / NAT2k15 / vRP at runtime and syncs characters (on create, load, update, delete) and vehicle registrations into the CAD. It replaces the older per-framework `cde-cad-{esx,qbcore,qbox,nat2k15,vrp}` resources.

So the full picture is simple: every server runs `CDECAD`, and framework servers also run `cde-cad-sync`. The two don't talk to each other, they just point at the same CAD backend. See [`../CONFIGURING.md`](../CONFIGURING.md) for the sync resource's convars.

## Modules included

| Module | What it does |
|---|---|
| Tablet | In-game CAD tablet NUI (default keybind `[`) plus a call-details popup (`G`) |
| Duty | `/d <dept>` on/off duty, paychecks, per-department callsigns, `/ts` |
| Civilian | `/setciv`, `/myciv`, `/showid`, `/regveh` |
| 911 | `/911 <message>` and `/a911 <message>` (anonymous), with location and postal |
| Fingerprint | Scan a nearby person's prints and pull their CAD record. On-duty LEOs only |
| ALPR | Placeable plate-reader cameras that read passing vehicles, flag wanted/BOLO plates to dispatch, and optionally clock speed and snap photos |
| Panic | `/panic` officer-down alert (keybind `Y`), on-duty LEOs only, with blip/route and optional auto-911 |
| Wraith | Wraith ARS 2X plate reader wired to CAD lookups with flag/BOLO alerts |
| ERS | Bridge for the Emergency Response Simulator callout system |

## Departments

Departments (name, type, callsign, blip icon and colour, on-duty paycheck) are managed in the CAD admin panel and pulled into the resource on startup. You don't hand-maintain them in `config.lua`. The `Config.Departments` block there is only a fallback, used if the CAD can't be reached at boot.

Edit departments in the admin panel, then run `/refreshdepts` in-game (admin) to re-pull them live without restarting the resource. If you'd rather not, the new list is picked up on the next restart anyway.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_target](https://github.com/overextended/ox_target) (optional, gives the fingerprint scanner its look-at menu; it falls back to `/scanprint` without it)
- [nearest-postal](https://forum.cfx.re/t/release-nearest-postal-script/293511) (optional, recommended so 911 calls and ALPR hits carry a postal code)
- [wk_wars2x](https://github.com/WolfKnight98/wk_wars2x) (optional, only needed for the Wraith module)

## Installation

1. Drop the `CDECAD` folder into your `resources/` directory.
2. Set your API credentials as server.cfg convars (see Configuration below).
3. Add the ensures to `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure CDECAD
   ```
4. On a framework server, also `ensure cde-cad-sync` **after** your framework resource.
5. Restart the server.

## Configuration

### API settings

Credentials live in `server.cfg` as convars, never in the resource files (`config.lua` ships to every connecting client, so anything in it is public). Add this block to your `server.cfg`, above the `ensure CDECAD` line:

```cfg
##CDECAD
set CDE_CAD_API_URL "https://your-cdecad-instance.com/api"
set CDE_CAD_API_KEY "your-fivem-api-key"
set CDE_CAD_COMMUNITY_ID "your-discord-guild-id"
set CDE_CAD_SERVER_NAME "Your Server Name"
```

The fingerprint scanner and the ALPR cameras use these same convars. There's nothing extra to set for either one.

### Optional convars

| Convar | Used by | Purpose |
|---|---|---|
| `CDE_CAD_WEBHOOK_DUTY` | Duty | General duty Discord log webhook |
| `CDE_CAD_WEBHOOK_PAYCHECK` | Duty | Paycheck Discord log webhook |
| `CDE_CAD_WEBHOOK_DEPTS` | Duty | Comma-separated department codes that have their own webhook, e.g. `"PD,SO,SP,FD"` |
| `CDE_CAD_WEBHOOK_<CODE>` | Duty | Per-department webhook, one per code listed in `CDE_CAD_WEBHOOK_DEPTS` (e.g. `CDE_CAD_WEBHOOK_PD`) |
| `CDE_CAD_WEBHOOK_DISPATCH` | 911, ALPR | Dispatch Discord webhook (ALPR hits post here too) |

Per-department webhooks can also be set in the CAD itself.

### Operational settings

Everything that isn't a secret lives in `config.lua`: paycheck amounts, command names, the postal resource, NPC reports, ID-card style, the fingerprint scanner (`Config.Fingerprint`), the ALPR network (`Config.ALPR`), the plate-reader cache, and so on. Departments come from the CAD (see [Departments](#departments)); the block in `config.lua` is only a fallback. Never put API keys or URLs in this file.

## Default commands

| Command | Description |
|---|---|
| `/d <dept>` | Go on duty for a department (`/d off` to go off) |
| `/duty` | Go off duty |
| `/setciv` | Open the civilian selector menu |
| `/myciv` | Show your current civilian info |
| `/showid` | Show your ID to nearby players |
| `/regveh` | Register the vehicle you're in |
| `/911 <message>` | Make a 911 call |
| `/a911 <message>` | Make an anonymous 911 call |
| `/scanprint` | Scan the nearest person's fingerprint against the CAD (on-duty LEO, within ~2.5m). With ox_target you can also just look at them and pick **Scan Fingerprint** |
| `/alprcam` (alias `/alpr`) | Place and manage ALPR cameras. See below |
| `/ts` | Traffic stop on the last locked Wraith plate |
| `/panic` | Officer-down panic alert (keybind `Y`), on-duty LEOs only |
| `/platelookup <plate>` | Manual Wraith-style plate lookup |
| `/refreshdepts` | (Admin) Re-pull departments from the CAD without a restart |
| `/cdewraithrefresh` | (Admin) Refresh the flagged-plates cache |
| `/cdewraithstatus` | (Admin) Show plate-cache status |

Admin commands are gated behind aces. Grant them in `server.cfg`, e.g. `add_ace group.admin command.refreshdepts allow`.

### ALPR cameras

Cameras are placed in the world by on-duty LEOs and read the plates of vehicles that drive past them. A flagged plate (wanted, BOLO, stolen, expired reg, no insurance, and so on) fires a hit to dispatch, and optionally logs a speed reading or a photo. Manage them all through `/alprcam` (or `/alpr`):

| Subcommand | What it does |
|---|---|
| `place [model#]` | Start placement (opens the placement UI if enabled). Optionally pick a prop model number |
| `panel` | Open the camera management panel |
| `props` | List the available camera prop models |
| `name <id> <text>` | Rename a camera |
| `toggle <id>` | Enable or disable a camera |
| `flip <id>` | Flip which way the camera faces |
| `speed <id> <mph\|off>` | Set or clear a speed threshold for speed enforcement |
| `move <id>` | Reposition an existing camera |
| `watch add\|rm\|list` | Manage the plate watchlist that triggers extra alerts |
| `remove` | Remove the camera you're looking at |
| `list` | List placed cameras |
| `clear` | Remove all cameras |

Cameras also sync up to the web ALPR panel in the CAD, so dispatch can see them on the map. Tuning (read range, field of view, camera limit, speed options, screenshots, alert level) is all under `Config.ALPR` in `config.lua`.

## Notes

- Don't run the standalone modules (`cad-tablet`, `CDE_Duty`, `cde-civ-sa`, `cad-911`, `cde-wraith`, `cde-ers`) next to the bundle for the same feature. Duplicate event handlers lead to unpredictable behaviour.
- See [`../CONFIGURING.md`](../CONFIGURING.md) for the full convar reference and key-rotation guidance.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `[CDECAD] CDE_CAD_API_KEY is not set` | Convar missing, or set after the resource started | Move the `set CDE_CAD_*` lines above `ensure CDECAD` in `server.cfg` |
| Tablet keeps opening to a blank/login page | `Config.TabletURL` points somewhere unexpected | Fix `Config.TabletURL` in `config.lua` |
| 911 calls go nowhere | Missing API key or wrong URL | Re-check both convars; enable `Config.CAD.Debug = true` in the duty section |
| "You must be on duty as LEO to scan prints" | You're not on duty as a law-enforcement unit | Go on duty with `/d <dept>` first; corrections/coroner setups can flip `Config.Fingerprint.RequireLEO` off |
| ALPR camera reads nothing | Camera disabled, or it's directional and facing the wrong way | `/alpr toggle <id>` to enable, `/alpr flip <id>` to turn it around, or widen `Config.ALPR.FOV` |
| Departments missing / stuck on the fallback list | CAD unreachable at boot, or url/key not set | Fix the convars, then `/refreshdepts` (admin) to re-pull live |
| Framework characters/vehicles don't show in the CAD | `cde-cad-sync` isn't running | `ensure cde-cad-sync` after your framework resource (framework servers only) |
