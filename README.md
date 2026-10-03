# SCCM Toolkit

Home base for the ConfigMgr scripts I ship. Apps, drivers, baselines, task sequence helpers.

## Where things live

```
applications/          # One folder per app. Don't dump everything in root.
  _template/           # Copy this. Rename it. Fill it in. Move on.
    detection/         # "Is it installed?" scripts
    install/           # Install wrappers
    uninstall/         # Uninstall wrappers
    source/            # Notes / tiny support files. Binaries stay on the share.

drivers/               # Same idea as applications, but for drivers
  _template/
  examples/            # "Here's how I did that thing" type stuff

baselines/
  configuration-items/
  configuration-baselines/

collections/
  queries/             # WQL and membership queries
  maintenance/         # Collection cleanup / "why is this still here" scripts

task-sequences/
  scripts/             # Steps that run in a TS
  groups/              # Notes on TS groups so Future You remembers why

shared/
  functions/           # Little helpers you dot-source
  modules/             # When a helper grows up and needs a real module
  logging/             # CCM log helpers — write once, reuse forever

tools/                 # Stuff you run. Not the client.
reports/               # SQL / reports / whatever keeps people happy
docs/                  # How we do things around here
```

## Naming (so we can find things later)

| What | Pattern | Example |
|------|---------|---------|
| Package folder | `Vendor-Product` or `Vendor-Product-Version` | `Dell-CommandUpdate` |
| Detection | `Detect-<Thing>.ps1` | `Detect-DriverStore.ps1` |
| Install | `Install-<Thing>.ps1` | `Install-RealtekNIC.ps1` |
| Uninstall | `Uninstall-<Thing>.ps1` | `Uninstall-RealtekNIC.ps1` |
| Shared function | `Verb-Noun.ps1` | `Write-CcmLog.ps1` |

If the folder name doesn't tell you what it is at a glance, rename it. Your 6am self will thank you.

## New package, quick version

1. Copy `applications/_template` or `drivers/_template` and give it a real name.
2. Drop in detection / install / uninstall as needed.
3. Leave the fat binaries on the DP / content share. Git is for scripts, not 800MB driver packs. See `.gitignore`.
4. If you're about to paste the same logging block for the third time, put it in `shared/` instead.

## Detection methods (App Model)

ConfigMgr is picky. Play by the rules:

- Found it? Exit `0` and print something on stdout (usually `Installed`).
- Didn't find it? Exit non-zero. `1` is fine.
- Keep it quick. Detection can fire a lot, and it runs as SYSTEM.
- Leave debug mode **off** before you paste anything into the console. ISE can turn it on for you when you're poking at it locally.
- Logging to `C:\Windows\CCM\Logs\` is great for troubleshooting. It is not how ConfigMgr decides success.

## Templates in the box

- `drivers/_template/detection/Detect-DriverStore.ps1` — match a HWID and a minimum version.
  - Default mode is `Active` (what's actually bound on the device).
  - `Store` mode if you only care that the package landed in the DriverStore.
  - `$DebugMode` starts at `$false`. Empty `$HardwareIDs` fails on purpose so you don't deploy a blank template by accident.

## Linting (keep the scripts honest)

We use [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). Errors fail CI; warnings yell at you but don't block (unless you ask).

```powershell
# Same check GitHub Actions runs
./tools/validation/Invoke-ScriptAnalysis.ps1

# Get strict about warnings too
./tools/validation/Invoke-ScriptAnalysis.ps1 -FailOnWarning
```

Settings live in `PSScriptAnalyzerSettings.psd1`. Workflow is `.github/workflows/powershell.yml`.


## Further readings

- more to come, this is just initial scaffolding for now.
- this is a rewrite and migration from my [archived repo](https://github.com/the-wittch/SCCM-Helpers) that is nearly a decade old now. I have learned some things.