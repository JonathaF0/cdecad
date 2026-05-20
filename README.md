# Configuring CDECAD FiveM Scripts

Everything sensitive (API keys, backend URL, community ID, Discord webhooks) is set with server **convars** in `server.cfg`. The `.lua` config files in each resource hold only operational values (commands, departments, cooldowns, etc.) and are safe to ship to clients.

---

## 1. The convars (server.cfg)

Add these to your `server.cfg` 

### Required

```cfg
set CDE_CAD_API_URL       "https://cdecad.com"
set CDE_CAD_API_KEY       "fvm_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
set CDE_CAD_COMMUNITY_ID  "your_discord_guild_id"
```

| Convar | Where to get it | Notes |
|---|---|---|
| `CDE_CAD_API_URL` | Your CAD backend base URL — `https://cdecad.com` for the hosted version, your domain if hosted | No trailing slash. Resources that historically used `/api` paths append it themselves. |
| `CDE_CAD_API_KEY` | CAD admin panel → FiveM Integration → Issue Key | Format `fvm_<64-char-hex>`. Treat as a password. |
| `CDE_CAD_COMMUNITY_ID` | Your Discord server's guild ID | Same value as `community.discordGuildId` in the CAD. |

### Optional (CDE_Duty / CDECAD/duty)

Per-department Discord webhook URLs. Only set the ones you use:

```cfg
set CDE_CAD_WEBHOOK_SAHP      ""
set CDE_CAD_WEBHOOK_LCSO      ""
set CDE_CAD_WEBHOOK_LSPD      ""
set CDE_CAD_WEBHOOK_DUTY      ""    # general duty fallback
set CDE_CAD_WEBHOOK_PAYCHECK  ""    # paycheck log
```

Webhook URLs look like `https://discord.com/api/webhooks/<id>/<token>`. If a webhook leaks, delete it in Discord (don't just unset the convar the token is still valid until the webhook is deleted Discord-side).

### Optional (other resources) **COMING SOON*

| Convar | Used by | Purpose |
|---|---|---|
| `CDE_CAD_WEBHOOK_DISPATCH` | `cde-london-bridge`, `cde-duty-cad-911` | Dispatch-side Discord notifications |
| `CDE_CAD_SA_TOKEN` | `cde-inferno-bridge` | Inferno Station Alert HTTP auth token |
| `CDE_CAD_PR_TOKEN` | `cde-inferno-bridge` | Inferno Pager Reborn HTTP auth token |
| `CDE_CAD_FRAMEWORK` | `cde-cad-sync` | Force a framework: `esx`, `qbcore`, `qbox`, `nat2k15`, `vrp`. Auto-detected if unset. |

---


## 2. Quickstart checklist

1. **Get your API key**: CAD admin panel → FiveM Integration → Issue Key. Copy the `fvm_…` string.
2. **Find your community ID**: Discord → right-click your server → Copy Server ID (Developer Mode required).
3. **Edit `server.cfg`** (add the three required convars above before `ensure` lines).
4. **Choose Pattern A or B** and `ensure` / `start` the resources.
5. **In-game**: `/d <dept>` to go on duty, `/setciv` to pick a civilian, `[` to open the tablet, `/911 <message>` to call dispatch.
6. **Check the console** for the `[CDECAD] ...` warning lines. If you see "CDE_CAD_API_KEY is not set", the convar isn't reaching the resource (typo, wrong file, or set after the resource started).

---

## 3. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `[CDECAD] CDE_CAD_API_KEY is not set` in console | Convar missing or set after the resource started | Move the `set CDE_CAD_*` lines above `ensure CDECAD` |
| `/d <dept>` says on-duty but CAD doesn't update | Either `ersAutoOnDuty` is disabled on your community, or your Discord ID isn't linked to a CAD user | Enable in CAD community settings; verify Discord OAuth on the user account |
| Tablet opens to a blank/login page repeatedly | `Config.TabletURL` points somewhere unexpected | Edit `Config.TabletURL` in `CDECAD/config.lua` or `cad-tablet/config.lua` |
| 911 calls go nowhere | Missing API key or wrong URL | Re-check both convars; set `Config.CAD.Debug = true` (CDECAD duty section) to see HTTP responses |
| Duplicate Discord notifications when going on duty | Running both CDECAD bundle AND standalone `CDE_Duty` | Pick one |
| Civilian ID card shows "NO PHOTO" | Either the civilian has no photo in CAD, or the resource's server can't reach the CAD (check `[CDECAD-CIVMANAGER]` logs) | Upload photo via CAD portal; verify convars |

---

