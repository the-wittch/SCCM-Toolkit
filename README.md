# SCCM Toolkit

[![PowerShell](https://github.com/the-wittch/SCCM-Toolkit/actions/workflows/powershell.yml/badge.svg)](https://github.com/the-wittch/SCCM-Toolkit/actions/workflows/powershell.yml)

Home base for the ConfigMgr scripts I ship. Apps, drivers, baselines, task sequence helpers.

Rewrite / migration from the old [SCCM-Helpers](https://github.com/the-wittch/SCCM-Helpers) stash. I've learned some things since then.

## Where things live

```
applications/     # One folder per app (detection / install / uninstall / source)
drivers/          # Same pattern for driver packages
baselines/        # Configuration items & baselines
collections/      # Queries and maintenance
task-sequences/   # TS scripts and group notes
shared/           # Reusable functions, modules, logging
tools/            # Admin scripts you run (inventory, client SDK, lint) — see tools/README.md
reports/          # SQL / reports
docs/             # Conventions and runbooks
```

## Start here

| Want to… | Go here |
|----------|---------|
| Add a new app or driver package | Copy `applications/_template` or `drivers/_template` — details in [docs/conventions.md](docs/conventions.md) |
| Find an admin / helper script | [tools/README.md](tools/README.md) |
| UI++ task sequence GUIs | [task-sequences/ui++/README.md](task-sequences/ui++/README.md) |
| Remember naming & detection rules | [docs/conventions.md](docs/conventions.md) |
| Lint before you push | `./tools/validation/Invoke-ScriptAnalysis.ps1` |

## Lint (short version)

```powershell
./tools/validation/Invoke-ScriptAnalysis.ps1              # full analyzer when available
./tools/validation/Invoke-ScriptAnalysis.ps1 -Mode Syntax  # no third-party modules
```

Locked-down box? See [tools/validation/lib/README.md](tools/validation/lib/README.md).
