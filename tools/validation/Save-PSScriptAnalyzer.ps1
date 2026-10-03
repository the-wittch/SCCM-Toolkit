<#
.SYNOPSIS
    Download PSScriptAnalyzer into tools/validation/lib for offline / locked-down use.

.DESCRIPTION
    Run this somewhere that is allowed to talk to PSGallery. Then copy the
    lib\PSScriptAnalyzer folder to the locked-down box (or commit it, if policy allows).

.EXAMPLE
    ./tools/validation/Save-PSScriptAnalyzer.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Destination = (Join-Path $PSScriptRoot 'lib')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Write-Host "Saving PSScriptAnalyzer to $Destination ..."

$prevProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Save-Module -Name PSScriptAnalyzer -Path $Destination -Force -ErrorAction Stop
}
finally {
    $ProgressPreference = $prevProgress
}

$saved = Get-ChildItem -LiteralPath $Destination -Directory |
    Where-Object { $_.Name -eq 'PSScriptAnalyzer' }

if (-not $saved) {
    throw "Save-Module finished but PSScriptAnalyzer folder wasn't found under $Destination"
}

Write-Host "Done. Analyzer is at: $($saved.FullName)"
Write-Host 'Invoke-ScriptAnalysis.ps1 will pick this up automatically.'
