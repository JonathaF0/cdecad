# Configuring [CDECAD](https://cdecad.com) FiveM Scripts

Everything sensitive (API keys, backend URL, community ID, Discord webhooks) is set with server **convars** in `server.cfg`. The `.lua` config files in each resource hold only operational values (commands, departments, cooldowns, etc.) and are safe to ship to clients.

---
## Modules included

| Module | What it does |
|---|---|
| Tablet | In-game CAD tablet NUI (default keybind `[`) + call-details popup (`G`) |
| Duty | `/d <dept>` on-duty, paychecks, per-department callsigns, `/ts` |
| Civilian | `/setciv`, `/myciv`, `/showid`, `/regveh` |
| 911 | `/911 <message>` and `/a911 <message>` (anonymous) with location + postal |
| Panic | `/panic` officer-down alert (keybind `Y`) - **on-duty LEOs only**, blip/route + optional auto-911 |
| Wraith | Wraith ARS 2X plate-reader → CAD lookup with flag/BOLO alerts |
| ERS | Bridge for the Emergency Response Simulator callout system |
## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [nearest-postal](https://forum.cfx.re/t/release-nearest-postal-script/293511) (optional)
- [wk_wars2x](https://github.com/WolfKnight98/wk_wars2x) (optional - Wraith module only)


## Departments

Departments (name, type, callsign, blip icon/colour, on-duty paycheck) are **managed in the CAD admin panel** and pulled into the resource on startup - you don't hand-maintain them in `config.lua`. The `Config.Departments` block in `config.lua` is a **fallback** only, used if the CAD is unreachable at boot.

- Edit departments in the CAD admin panel, then run `/refreshdepts` in-game (admin) to re-pull them live without a resource restart.
- Otherwise the new list is picked up on the next `ensure`/restart.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [nearest-postal](https://forum.cfx.re/t/release-nearest-postal-script/293511) (optional, recommended for postal codes)
- [wk_wars2x](https://github.com/WolfKnight98/wk_wars2x) (optional - only required if you use the Wraith module)

## Installation

1. Drop the `CDECAD` folder into your `resources/` directory
2. Configure API credentials via server.cfg convars (see Configuration below)
3. Add to your `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure CDECAD
   ```
4. (Framework servers only) also `ensure cde-cad-sync` **after** your framework resource
5. Restart your server

## Configuration

### API Settings

For security reasons, CDE CAD credentials are stored in `server.cfg` as convars rather than in resource files. Add the following block to your `server.cfg`:

```
##CDECAD
set CDE_CAD_API_URL "https://your-cdecad-instance.com/api"
set CDE_CAD_API_KEY "your-fivem-api-key"
set CDE_CAD_COMMUNITY_ID "your-discord-guild-id"
set CDE_CAD_SERVER_NAME "Your Server Name"
```

### Optional convars

| Convar | Used by | Purpose |
|---|---|---|
| `CDE_CAD_WEBHOOK_DUTY` | Duty module | General duty Discord log webhook |
| `CDE_CAD_WEBHOOK_PAYCHECK` | Duty module | Paycheck Discord log webhook |
| `CDE_CAD_WEBHOOK_DEPTS` | Duty module | Comma-separated department codes that have their own webhook, e.g. `"PD,SO,SP,FD"` |
| `CDE_CAD_WEBHOOK_<CODE>` | Duty module | Per-department webhook - one per code listed in `CDE_CAD_WEBHOOK_DEPTS` (e.g. `CDE_CAD_WEBHOOK_PD`) |
| `CDE_CAD_WEBHOOK_DISPATCH` | 911 module | Dispatch Discord webhook |

Per-department webhooks can also be configured in the CAD itself.

### Operational settings

Open `config.lua` to tweak operational values (paycheck amounts, commands, postal resource, NPC reports, ID-card style, plate-reader cache, etc.). Departments are pulled from the CAD (see [Departments](#departments) above); the block in `config.lua` is only a fallback. Do **not** put API keys or URLs in this file - it ships to every connecting client.

## Default commands

| Command | Description |
|---|---|
| `/d <dept>` | Go on duty for a department (`/d off` to go off duty) |
| `/duty` | Go off duty |
| `/setciv` | Open civilian selector menu |
| `/myciv` | Show your current civilian info |
| `/showid` | Show your ID to nearby players |
| `/regveh` | Register your current vehicle |
| `/911 <message>` | Make a 911 call |
| `/a911 <message>` | Make an anonymous 911 call |
| `/ts` | Traffic stop on last locked Wraith plate |
| `/panic` | Officer-down panic alert (keybind `Y`) - on-duty LEOs only |
| `/platelookup <plate>` | Manual Wraith-style plate lookup |
| `/refreshdepts` | (Admin) Re-pull departments from the CAD without a restart |
| `/cdewraithrefresh` | (Admin) Refresh the flagged-plates cache |
| `/cdewraithstatus` | (Admin) Show plate-cache status |

Admin commands are gated behind aces - grant them in `server.cfg`, e.g. `add_ace group.admin command.refreshdepts allow`.

## Notes

- **Do not run** the standalone modules (`cad-tablet`, `CDE_Duty`, `cde-civ-sa`, `cad-911`, `cde-wraith`, `cde-ers`) alongside the bundle for the same module - duplicate event handlers create unpredictable behaviour.
- See [`../CONFIGURING.md`](../CONFIGURING.md) for the full convar reference and rotation guidance.



---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `[CDECAD] CDE_CAD_API_KEY is not set` | Convar missing or set after the resource started | Move the `set CDE_CAD_*` lines above `ensure CDECAD` in `server.cfg` |
| Tablet opens to a blank/login page repeatedly | `Config.TabletURL` points somewhere unexpected | Edit `Config.TabletURL` in `config.lua` |
| 911 calls go nowhere | Missing API key or wrong URL | Re-check both convars; enable `Config.CAD.Debug = true` in the duty section |
| Departments are missing / use the fallback list | CAD unreachable at boot, or url/key not set | Fix the convars, then run `/refreshdepts` (admin) to re-pull live |
| Framework characters/vehicles don't show in the CAD | `cde-cad-sync` not running | `ensure cde-cad-sync` after your framework resource (framework servers only) |

1. **Get your API key**: CAD admin panel → FiveM Integration → Issue Key. Copy the `fvm_…` string.
2. **Find your community ID**: Discord → right-click your server → Copy Server ID (Developer Mode required).
3. **Edit `server.cfg`** (add the three required convars above before `ensure` lines).
4. **Choose Pattern A or B** and `ensure` / `start` the resources.
5. **In-game**: `/d <dept>` to go on duty, `/setciv` to pick a civilian, `[` to open the tablet, `/911 <message>` to call dispatch.
6. **Check the console** for the `[CDECAD] ...` warning lines. If you see "CDE_CAD_API_KEY is not set", the convar isn't reaching the resource (typo, wrong file, or set after the resource started).
