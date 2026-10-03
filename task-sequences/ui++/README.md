# UI++

Simple GUIs for task sequences — computer name, site/OU, app picks — without building HTAs.

Configs are XML. The EXE is [UI++](https://uiplusplus.tplant.com.au/) (Jason Sandys). Binaries stay on the content share; see [source/README.md](source/README.md).

## Samples

| Config | Job |
|--------|-----|
| [configs/ui++.ComputerName.xml](configs/ui++.ComputerName.xml) | Text box → `OSDComputerName` |
| [configs/ui++.SiteOu.xml](configs/ui++.SiteOu.xml) | Site + role dropdowns → `OSDDomainOUName`, `NamePrefix` |
| [configs/ui++.AppTree.xml](configs/ui++.AppTree.xml) | App tree → `XApplications##` / `XPackages###` |

Copy a sample, search-replace `Contoso` / LDAP paths / app names, send it.

## Wire-up (task sequence)

1. Package containing `UI++64.exe`, the two FTW DLLs, and your `ui++.xml` (no program required).
2. **Run Command Line** step (with the package):

```text
UI++64.exe /config:ui++.ComputerName.xml
```

3. WinPE arch must match the EXE (x64 PE → `UI++64.exe`).
4. If you run a TS from full Windows and need the interactive desktop, use `ServiceUI.exe` from MDT in front of UI++. Same goes for any other UI in a TS.

### Boot image prestart (optional)

Put UI++ and a config in the prestart files folder, then something like:

```text
UI++64.exe /config:ui++.xml
```

Handy when you want a GUI before the TS list (e.g. set `SMSTSPreferredAdvertID`). 

## Test the XML without imaging a box

```powershell
./task-sequences/ui++/Test-UippConfig.ps1
./task-sequences/ui++/Test-UippConfig.ps1 -Path ./task-sequences/ui++/configs/ui++.ComputerName.xml
```

That only checks the XML is sane. To click through the dialogs, run `UI++64.exe /config:...` on a workstation with the binaries present.

## Variable gotchas

- Prefer `OSDComputerName`, not `ComputerName` (env var collision).
- AppTree `Name=` must match the ConfigMgr application name exactly.
- After AppTree, point Install Application at base variable `XApplications` (or whatever you set in `ApplicationVariableBase`).
