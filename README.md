# Configuring CDECAD FiveM Scripts

Everything sensitive (API keys, backend URL, community ID, Discord webhooks) is set with server **convars** in `server.cfg`. The `.lua` config files in each resource hold only operational values (commands, departments, cooldowns, etc.) and are safe to ship to clients.

---

## 1. The convars (server.cfg)

Add these to your `server.cfg` (or `exec` them from a private `secrets.cfg` you don't commit). Set them **before** the `ensure`/`start` lines for the CDECAD resources.

### Required

```cfg
set CDE_CAD_API_URL       "https://cdecad.com"
set CDE_CAD_API_KEY       "fvm_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
set CDE_CAD_COMMUNITY_ID  "your_discord_guild_id"
```

| Convar | Where to get it | Notes |
|---|---|---|
| `CDE_CAD_API_URL` | Your CAD backend base URL — `https://cdecad.com` for the hosted version, your domain if self-hosted | No trailing slash. Resources that historically used `/api` paths append it themselves. |
| `CDE_CAD_API_KEY` | CAD admin panel → FiveM Integration → Issue Key | Format `fvm_<64-char-hex>`. Treat as a password. |
| `CDE_CAD_COMMUNITY_ID` | Your Discord server's guild ID | Same value as `community.discordGuildId` in the CAD. |

### Optional (CDE_Duty / CDECAD/duty)

Per-department Discord webhook URLs. Only set the ones you use:

```cfg
set CDE_CAD_WEBHOOK_THP       ""
set CDE_CAD_WEBHOOK_KCSO      ""
set CDE_CAD_WEBHOOK_KPD       ""
set CDE_CAD_WEBHOOK_SCSO      ""
set CDE_CAD_WEBHOOK_KFD       ""
set CDE_CAD_WEBHOOK_RMFD      ""
set CDE_CAD_WEBHOOK_DUTY      ""    # general duty fallback
set CDE_CAD_WEBHOOK_PAYCHECK  ""    # paycheck log
```

Webhook URLs look like `https://discord.com/api/webhooks/<id>/<token>`. If a webhook leaks, delete it in Discord (don't just unset the convar — the token is still valid until the webhook is deleted Discord-side).

### Optional (other resources)

| Convar | Used by | Purpose |
|---|---|---|
| `CDE_CAD_WEBHOOK_DISPATCH` | `cde-london-bridge`, `cde-duty-cad-911` | Dispatch-side Discord notifications |
| `CDE_CAD_SA_TOKEN` | `cde-inferno-bridge` | Inferno Station Alert HTTP auth token |
| `CDE_CAD_PR_TOKEN` | `cde-inferno-bridge` | Inferno Pager Reborn HTTP auth token |
| `CDE_CAD_FRAMEWORK` | `cde-cad-sync` | Force a framework: `esx`, `qbcore`, `qbox`, `nat2k15`, `vrp`. Auto-detected if unset. |

---

## 2. Which resources to install

You don't need everything. Pick one of these install patterns:

### Pattern A — The CDECAD bundle (recommended)

Drop **`fivem-scripts/CDECAD/`** into your `resources/` directory and add:

```cfg
ensure CDECAD
```

Gets you: tablet, duty system, civilian manager, 911 commands — all in one resource. No category folder, no sub-resources to start.

### Pattern B — Standalone resources

Pick whichever individual resources you want from `fivem-scripts/`:

| Folder | What it does |
|---|---|
| `cad-tablet` | In-game CAD tablet NUI |
| `CDE_Duty` | On/off-duty, paychecks, departments, /ts, /panic |
| `cde-civ-sa` | Civilian manager: /setciv, /myciv, /bank, /showid, /regveh |
| `cad-911` | /911 and /a911 commands |
| `cde_lm` | LiveMap location push (superseded by `cad-tablet`'s built-in tracker — don't run both) |
| `cde-cad-sync` | Auto-detects ESX/QBCore/QBox/NAT2k15/vRP and syncs characters/vehicles to CAD |
| `cde-cad-{esx,qbcore,qbox-release,nat2k15,vrp}` | Per-framework sync (older — use `cde-cad-sync` instead if possible) |
| `cde-wraith` | Wraith ARS 2X plate reader → CAD lookup |
| `cde-london-bridge` | London Studios (SmartFires, SmartSigns, SmartMotorways, Speed Cameras) → CAD |
| `cde-inferno-bridge` | Inferno Collection (Station Alert, Pager Reborn) → CAD |
| `cde-dz-drone` | DangerZone drone integration |
| `cde-ers` | ERS callout integration |
| `cad-lbphone` | lb-phone messaging hooks |
| `cad-panic` | Panic button |

**Do not run a standalone alongside the CDECAD bundle for the same module** — duplicate event handlers create unpredictable behaviour.

---

## 3. Per-resource .lua config

For most operational tweaks, you don't need to touch any convar — edit the resource's `config.lua` (or `shared/config.lua`):

| Resource | Config file | Common things you'd edit |
|---|---|---|
| `CDECAD` | `CDECAD/config.lua` | All four modules' settings (Tablet, Duty, Civ, 911) in one file. Departments, commands, paychecks, postal resource, NPC reports, ID-card style, bank rules. |
| `cad-tablet` (standalone) | `config.lua` | Keybinds (`TabletKey`, `CallPopupKey`), tablet URL, location tracking |
| `CDE_Duty` (standalone) | `config.lua` | Departments, paycheck amounts, loadouts, 911 chat settings |
| `cde-civ-sa` (standalone) | `shared/config.lua` | Commands, ID card style, bank settings, vehicle registration fee |
| `cde-wraith` | `shared/config.lua` | Plate reader cache, display duration, alert levels |
| `cde-cad-sync` | `shared/config.lua` | Postal resource, sync intervals, Discord role exclusions |

**Do not put API keys, URLs, or webhook URLs in any `.lua` file.** Those files load via `shared_scripts` and ship to every connecting client. Use convars.

---

## 4. Quickstart checklist

1. **Get your API key**: CAD admin panel → FiveM Integration → Issue Key. Copy the `fvm_…` string.
2. **Find your community ID**: Discord → right-click your server → Copy Server ID (Developer Mode required).
3. **Edit `server.cfg`** (add the three required convars above before `ensure` lines).
4. **Choose Pattern A or B** and `ensure` / `start` the resources.
5. **In-game**: `/d <dept>` to go on duty, `/setciv` to pick a civilian, `[` to open the tablet, `/911 <message>` to call dispatch.
6. **Check the console** for the `[CDECAD] ...` warning lines. If you see "CDE_CAD_API_KEY is not set", the convar isn't reaching the resource (typo, wrong file, or set after the resource started).

---

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `[CDECAD] CDE_CAD_API_KEY is not set` in console | Convar missing or set after the resource started | Move the `set CDE_CAD_*` lines above `ensure CDECAD` |
| `/d <dept>` says on-duty but CAD doesn't update | Either `ersAutoOnDuty` is disabled on your community, or your Discord ID isn't linked to a CAD user | Enable in CAD community settings; verify Discord OAuth on the user account |
| Tablet opens to a blank/login page repeatedly | `Config.TabletURL` points somewhere unexpected | Edit `Config.TabletURL` in `CDECAD/config.lua` or `cad-tablet/config.lua` |
| 911 calls go nowhere | Missing API key or wrong URL | Re-check both convars; set `Config.CAD.Debug = true` (CDECAD duty section) to see HTTP responses |
| Duplicate Discord notifications when going on duty | Running both CDECAD bundle AND standalone `CDE_Duty` | Pick one |
| Civilian ID card shows "NO PHOTO" | Either the civilian has no photo in CAD, or the resource's server can't reach the CAD (check `[CDECAD-CIVMANAGER]` logs) | Upload photo via CAD portal; verify convars |

---

## 6. Rotating credentials

If a key or webhook ever leaks (a player shares a screenshot, a config is pushed to a public repo, etc.):

1. **API key**: CAD admin → FiveM Integration → Revoke the old key, issue a new one, update `CDE_CAD_API_KEY` in `server.cfg`, restart the resource.
2. **Discord webhook**: Discord server settings → Integrations → Webhooks → Delete the leaked webhook. Create a fresh one, update the corresponding `CDE_CAD_WEBHOOK_*` convar.

Removing a leaked value from `server.cfg` is **not** enough — the value is still on every machine that ever saw it. Always rotate.
