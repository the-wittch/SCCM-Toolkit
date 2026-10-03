# Local PSScriptAnalyzer drop spot

Some fine establishments won't let you `Install-Module` from the gallery on a box.
Drop a copy of the module here instead:

```
tools/validation/lib/PSScriptAnalyzer/
```

## How to get the module onto a locked-down machine

On a machine that *can* reach PSGallery (home lab, unlocked laptop, CI agent):

```powershell
./tools/validation/Save-PSScriptAnalyzer.ps1
```

That saves the module under this `lib/` folder. Then either:

1. Copy `tools/validation/lib/PSScriptAnalyzer` over with USB / approved software channel, or
2. Commit it if your security folks are fine with vendoring Microsoft’s analyzer in-repo.

The folder is gitignored by default so we don’t bloat the repo.

`Invoke-ScriptAnalysis.ps1` looks here first, then for an already-installed module, then (optionally) tries the gallery, then can fall back to a no-module syntax parse.
