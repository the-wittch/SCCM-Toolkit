# Tools

Scripts **you** run on a workstation or jump box. Not client detection/install payloads — those live under `applications/` and `drivers/`.

Add new tools here and update this list.

## Inventory

| Script | What it does |
|--------|----------------|
| [inventory/Get-UninstallStrings.ps1](inventory/Get-UninstallStrings.ps1) | Scrape HKLM uninstall keys; optional CSV; quiet MSI uninstall lines |

```powershell
./tools/inventory/Get-UninstallStrings.ps1 -Name '*Chrome*' |
    Format-Table DisplayName, DisplayVersion, QuietUninstallString
```

## Client SDK

| Script | What it does |
|--------|----------------|
| [client/Start-CcmApplicationInstall.ps1](client/Start-CcmApplicationInstall.ps1) | Trigger Available apps via local `CCM_Application` (needs ConfigMgr client + admin) |

```powershell
./tools/client/Start-CcmApplicationInstall.ps1 -Name '*Company Portal*' -WhatIf
```

## Validation

| Script | What it does |
|--------|----------------|
| [validation/Invoke-ScriptAnalysis.ps1](validation/Invoke-ScriptAnalysis.ps1) | PSScriptAnalyzer (or syntax-only fallback) |
| [validation/Save-PSScriptAnalyzer.ps1](validation/Save-PSScriptAnalyzer.ps1) | Download analyzer into `lib/` for offline / locked-down boxes |

Details for offline installs: [validation/lib/README.md](validation/lib/README.md).

## Export / import

Placeholder for ConfigMgr export/import helpers.
