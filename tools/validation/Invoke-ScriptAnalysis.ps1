<#
.SYNOPSIS
    Lint PowerShell in this repo (PSScriptAnalyzer when available).

.DESCRIPTION
    Resolution order for the analyzer module:
      1. Bundled copy under tools/validation/lib/PSScriptAnalyzer
      2. Already installed for this user/machine
      3. Install-Module from PSGallery (skipped if -SkipInstall)
      4. Fallback: built-in AST syntax parse (no third-party modules)

    Locked-down shop? Use Save-PSScriptAnalyzer.ps1 on an open box, copy lib over,
    or run with -Mode Syntax and let CI do the full analyze on GitHub.

.EXAMPLE
    ./tools/validation/Invoke-ScriptAnalysis.ps1

.EXAMPLE
    ./tools/validation/Invoke-ScriptAnalysis.ps1 -Mode Syntax

.EXAMPLE
    ./tools/validation/Invoke-ScriptAnalysis.ps1 -SkipInstall -FailOnWarning
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,

    [Parameter()]
    [string]$SettingsPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'PSScriptAnalyzerSettings.psd1'),

    [Parameter()]
    [ValidateSet('Auto', 'Analyzer', 'Syntax')]
    [string]$Mode = 'Auto',

    [Parameter()]
    [switch]$FailOnWarning,

    [Parameter()]
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

function Get-BundledAnalyzerPath {
    $libRoot = Join-Path $PSScriptRoot 'lib/PSScriptAnalyzer'
    if (-not (Test-Path -LiteralPath $libRoot)) {
        return $null
    }

    # Save-Module lays out lib/PSScriptAnalyzer/<version>/
    $versionDir = Get-ChildItem -LiteralPath $libRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1

    if ($versionDir -and (Test-Path -LiteralPath (Join-Path $versionDir.FullName 'PSScriptAnalyzer.psd1'))) {
        return $versionDir.FullName
    }

    if (Test-Path -LiteralPath (Join-Path $libRoot 'PSScriptAnalyzer.psd1')) {
        return $libRoot
    }

    return $null
}

function Import-AnalyzerModule {
    param(
        [Parameter()]
        [switch]$SkipInstall,

        [Parameter()]
        [switch]$AllowInstall
    )

    $bundled = Get-BundledAnalyzerPath
    if ($bundled) {
        Write-Host "Using bundled PSScriptAnalyzer: $bundled"
        Import-Module $bundled -Force
        return $true
    }

    $installed = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($installed) {
        Write-Host "Using installed PSScriptAnalyzer $($installed.Version)"
        Import-Module PSScriptAnalyzer -Force
        return $true
    }

    if (-not $AllowInstall -or $SkipInstall) {
        return $false
    }

    Write-Host 'PSScriptAnalyzer not found locally. Trying Install-Module (CurrentUser)...'
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module PSScriptAnalyzer -Force
        return $true
    }
    catch {
        Write-Host "Install-Module failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
    finally {
        $ProgressPreference = $prevProgress
    }
}

function Invoke-SyntaxOnlyAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $scripts = @(
        Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in '.ps1', '.psm1', '.psd1' -and
                $_.FullName -notmatch '[\\/]\.git[\\/]'
            }
    )

    $findings = @()

    foreach ($script in $scripts) {
        $tokens = $null
        $parseErrors = $null
        $content = Get-Content -LiteralPath $script.FullName -Raw -ErrorAction Stop

        [void][System.Management.Automation.Language.Parser]::ParseInput(
            $content,
            [ref]$tokens,
            [ref]$parseErrors
        )

        foreach ($parseError in @($parseErrors)) {
            $findings += [pscustomobject]@{
                Severity   = 'Error'
                RuleName   = 'SyntaxParseError'
                ScriptName = $script.Name
                Line       = $parseError.Extent.StartLineNumber
                Message    = $parseError.Message
            }
        }
    }

    return $findings
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}

$useAnalyzer = $false

switch ($Mode) {
    'Syntax' {
        $useAnalyzer = $false
    }
    'Analyzer' {
        $imported = Import-AnalyzerModule -SkipInstall:$SkipInstall -AllowInstall:(-not $SkipInstall)
        if (-not $imported) {
            throw @"
PSScriptAnalyzer is required for -Mode Analyzer but wasn't available.

Options when the gallery is blocked:
  1. On an open machine: ./tools/validation/Save-PSScriptAnalyzer.ps1
     then copy tools/validation/lib/PSScriptAnalyzer to this box
  2. Install the module through whatever software channel your org allows
  3. Run: ./tools/validation/Invoke-ScriptAnalysis.ps1 -Mode Syntax
"@
        }
        $useAnalyzer = $true
    }
    default {
        # Auto
        $imported = Import-AnalyzerModule -SkipInstall:$SkipInstall -AllowInstall:(-not $SkipInstall)
        $useAnalyzer = [bool]$imported
        if (-not $useAnalyzer) {
            Write-Host 'No PSScriptAnalyzer available. Falling back to built-in syntax parse.' -ForegroundColor Yellow
            Write-Host '(Rules/style checks need the analyzer module — see tools/validation/lib/README.md)' -ForegroundColor Yellow
        }
    }
}

Write-Host "Scanning:  $Path"
Write-Host "Mode:      $(if ($useAnalyzer) { 'Analyzer' } else { 'Syntax' })"
if ($useAnalyzer) {
    Write-Host "Settings:  $SettingsPath"
}
Write-Host ''

if ($useAnalyzer) {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        throw "Settings file not found: $SettingsPath"
    }

    $results = @(
        Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse -ReportSummary
    )
}
else {
    $results = @(Invoke-SyntaxOnlyAnalysis -RootPath $Path)
}

if ($results.Count -eq 0) {
    Write-Host 'Clean. No findings.'
    exit 0
}

$results |
    Sort-Object Severity, ScriptName, Line |
    Format-Table -AutoSize Severity, RuleName, ScriptName, Line, Message

$errorCount   = @($results | Where-Object { $_.Severity -eq 'Error' }).Count
$warningCount = @($results | Where-Object { $_.Severity -eq 'Warning' }).Count
$infoCount    = @($results | Where-Object { $_.Severity -eq 'Information' }).Count

Write-Host ''
Write-Host "Summary: $errorCount error(s), $warningCount warning(s), $infoCount info"

if ($errorCount -gt 0) {
    Write-Host "Reported $errorCount error(s)." -ForegroundColor Red
    exit 1
}

if ($FailOnWarning -and $warningCount -gt 0) {
    Write-Host "Reported $warningCount warning(s) and -FailOnWarning was set." -ForegroundColor Red
    exit 1
}

exit 0
