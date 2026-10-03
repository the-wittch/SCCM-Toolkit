# Conventions

Root README stays short. This file is the how-we-work notes.

## One package, one folder

Don't mix three products in one directory.

```
drivers/Realtek-USB-NIC-8153/
  detection/Detect-DriverStore.ps1
  install/Install-Driver.ps1
  uninstall/Uninstall-Driver.ps1
  source/README.md          # "binaries live on the share at ..."
```

Vendor driver packs do **not** go in git. Note the content library path in `source/README.md`. Disk is cheap. Git history full of `.cab` files is not.

## Naming

| What | Pattern | Example |
|------|---------|---------|
| Package folder | `Vendor-Product` or `Vendor-Product-Version` | `Dell-CommandUpdate` |
| Detection | `Detect-<Thing>.ps1` | `Detect-DriverStore.ps1` |
| Install | `Install-<Thing>.ps1` | `Install-RealtekNIC.ps1` |
| Uninstall | `Uninstall-<Thing>.ps1` | `Uninstall-RealtekNIC.ps1` |
| Shared function | `Verb-Noun.ps1` | `Write-CcmLog.ps1` |
| Admin tool | `Verb-Noun.ps1` under `tools/` | `Get-UninstallStrings.ps1` |

If the folder name doesn't tell you what it is at a glance, rename it.

## New package, quick version

1. Copy `applications/_template` or `drivers/_template` and give it a real name.
2. Fill `detection/`, `install/`, `uninstall/` as needed.
3. Leave fat binaries on the DP / content share.
4. Third time you're pasting the same logging block → put it in `shared/`.

## Script headers

At the top of anything that runs on a client, leave:

1. What it does (detect / install / uninstall — pick one job)
2. Who it runs as (SYSTEM vs user)
3. Exit codes
4. The knobs they need to turn (HWIDs, versions, paths) near the top

Admin tools under `tools/` should have a proper comment-based help block (`.SYNOPSIS` / `.EXAMPLE`) so `Get-Help` works.

## Detection methods (App Model)

ConfigMgr is picky:

- Found it? Exit `0` and print something on stdout (usually `Installed`).
- Didn't find it? Exit non-zero. `1` is fine.
- Keep it quick. Detection can fire a lot, and it runs as SYSTEM.
- Leave debug mode **off** before you paste into the console.
- CCM logs are for you. They are not how ConfigMgr decides success.

## Templates currently in the box

- `drivers/_template/detection/Detect-DriverStore.ps1` — HWID + min version.
  - Default `Active` (bound driver). Optional `Store` mode.
  - `$DebugMode` defaults `$false`. Empty `$HardwareIDs` fails on purpose.
- `task-sequences/ui++/configs/` — UI++ sample XMLs (computer name, site/OU, app tree). See that folder’s README.

## Shared code

Copy/paste is fine twice. Third time, extract to `shared/functions/`. Bigger helpers can become a module under `shared/modules/`.

## Docs vs README vs this file

| Place | Job |
|-------|-----|
| Root `README.md` | Front door. Map + links. |
| `tools/README.md` | Catalog of admin scripts. |
| `docs/conventions.md` | How we build packages (this file). |
| Script comment help | Per-tool usage. |
