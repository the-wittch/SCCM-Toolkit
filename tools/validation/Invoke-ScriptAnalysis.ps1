<#
.SYNOPSIS
    Run PSScriptAnalyzer across the repo.

.DESCRIPTION
    Same check the CI runs. Use this before you push so GitHub isn't the first
    friend to tell you that you left a blank catch block in there.

.EXAMPLE
    ./tools/validation/Invoke-ScriptAnalysis.ps1

.EXAMPLE
    ./tools/validation/Invoke-ScriptAnalysis.ps1 -Path ./drivers -FailOnWarning
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,

    [Parameter()]
    [string]$SettingsPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'PSScriptAnalyzerSettings.psd1'),

    [Parameter()]
    [switch]$FailOnWarning,

    [Parameter()]
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

function Install-AnalyzerModuleIfMissing {
    param(
        [Parameter()]
        [switch]$SkipInstall
    )

    $module = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($module) {
        Import-Module PSScriptAnalyzer -Force
        return
    }

    if ($SkipInstall) {
        throw 'PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser'
    }

    Write-Host 'PSScriptAnalyzer not found. Installing for CurrentUser...'
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    finally {
        $ProgressPreference = $prevProgress
    }

    Import-Module PSScriptAnalyzer -Force
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}

if (-not (Test-Path -LiteralPath $SettingsPath)) {
    throw "Settings file not found: $SettingsPath"
}

Install-AnalyzerModuleIfMissing -SkipInstall:$SkipInstall

Write-Host "Scanning:  $Path"
Write-Host "Settings:  $SettingsPath"
Write-Host ''

$results = @(
    Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse -ReportSummary
)

if ($results.Count -eq 0) {
    Write-Host 'Clean. No analyzer findings.'
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
    Write-Host "PSScriptAnalyzer reported $errorCount error(s)." -ForegroundColor Red
    exit 1
}

if ($FailOnWarning -and $warningCount -gt 0) {
    Write-Host "PSScriptAnalyzer reported $warningCount warning(s) and -FailOnWarning was set." -ForegroundColor Red
    exit 1
}

exit 0
