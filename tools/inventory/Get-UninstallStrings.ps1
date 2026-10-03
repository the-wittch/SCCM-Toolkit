<#
.SYNOPSIS
    Dump uninstall registry entries (the "Add/Remove Programs" list) as objects or CSV.

.DESCRIPTION
    Walks the 64-bit and 32-bit HKLM Uninstall keys and pulls the fields you
    actually care about when writing detection / uninstall logic.

    For MSI entries it also builds a quiet uninstall command you can paste into
    a ConfigMgr deployment type without rediscovering the GUID by hand.

.PARAMETER Name
    Optional DisplayName filter. Supports wildcards. Example: *Chrome*

.PARAMETER Path
    Optional CSV output path. If omitted, objects hit the pipeline so you can
    Where-Object / Export-Csv yourself.

.PARAMETER IncludeEmptyNames
    Keep entries with no DisplayName (usually noise). Off by default.

.EXAMPLE
    ./Get-UninstallStrings.ps1 -Name '*7-Zip*' | Format-Table DisplayName, DisplayVersion, QuietUninstallString

.EXAMPLE
    ./Get-UninstallStrings.ps1 -Path "$env:USERPROFILE\Downloads\UninstallStrings.csv"
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Name,

    [Parameter()]
    [string]$Path,

    [Parameter()]
    [switch]$IncludeEmptyNames
)

$ErrorActionPreference = 'Stop'

function Get-UninstallEntry {
    param(
        [Parameter(Mandatory)]
        [Microsoft.Win32.RegistryKey]$Key,

        [Parameter(Mandatory)]
        [ValidateSet('x64', 'x86')]
        [string]$Architecture,

        [Parameter()]
        [switch]$IncludeEmptyNames
    )

    $props = Get-ItemProperty -LiteralPath $Key.PSPath -ErrorAction SilentlyContinue
    if (-not $props) {
        return
    }

    $displayName = [string]$props.DisplayName
    if (-not $IncludeEmptyNames -and [string]::IsNullOrWhiteSpace($displayName)) {
        return
    }

    $uninstallString = [string]$props.UninstallString
    $quietFromReg    = [string]$props.QuietUninstallString
    $quietBuilt      = $null
    $productCode     = $null

    if ($uninstallString -match 'MsiExec\.exe.*\{([0-9A-Fa-f-]+)\}') {
        $productCode = $Matches[1]
        $quietBuilt = "MsiExec.exe /X{$productCode} /qn /norestart"
    }
    elseif ($uninstallString -match '\{([0-9A-Fa-f-]{36})\}') {
        # Some vendors bury a GUID in a non-Msiexec string
        $productCode = $Matches[1]
        $quietBuilt = "MsiExec.exe /X{$productCode} /qn /norestart"
    }

    $productCodeOut = if ($productCode) {
        "{$productCode}"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$props.ProductGUID)) {
        [string]$props.ProductGUID
    }
    else {
        $null
    }

    [pscustomobject]@{
        Architecture         = $Architecture
        RegistryName         = $Key.PSChildName
        DisplayName          = $displayName
        DisplayVersion       = [string]$props.DisplayVersion
        Publisher            = [string]$props.Publisher
        InstallLocation      = [string]$props.InstallLocation
        InstallDate          = [string]$props.InstallDate
        ProductCode          = $productCodeOut
        UninstallString      = $uninstallString
        QuietUninstallString = if (-not [string]::IsNullOrWhiteSpace($quietFromReg)) { $quietFromReg } else { $quietBuilt }
    }
}

$roots = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Arch = 'x64' }
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Arch = 'x86' }
)

$entries = foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root.Path)) {
        Write-Verbose "Skipping missing hive: $($root.Path)"
        continue
    }

    Get-ChildItem -LiteralPath $root.Path -ErrorAction SilentlyContinue | ForEach-Object {
        Get-UninstallEntry -Key $_ -Architecture $root.Arch -IncludeEmptyNames:$IncludeEmptyNames
    }
}

if ($Name -and $Name.Count -gt 0) {
    $entries = foreach ($entry in $entries) {
        foreach ($pattern in $Name) {
            if ($entry.DisplayName -like $pattern) {
                $entry
                break
            }
        }
    }
}

$entries = @($entries | Sort-Object DisplayName, Architecture)

if ($Path) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $entries | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    Write-Verbose "Wrote $($entries.Count) row(s) to $Path"
}

# Always emit objects so this stays pipeline-friendly even when writing CSV.
$entries
