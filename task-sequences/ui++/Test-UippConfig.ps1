<#
.SYNOPSIS
    Sanity-check UI++ XML configs without launching the EXE.

.DESCRIPTION
    Loads one or more UI++ config files and checks for common mistakes:
    bad XML, missing UIpp/Actions, Variable="ComputerName", empty App Name=, etc.

    Does not replace clicking through UI++64.exe on a test box.

.PARAMETER Path
    File or folder. Default: configs\ next to this script.

.EXAMPLE
    ./task-sequences/ui++/Test-UippConfig.ps1

.EXAMPLE
    ./task-sequences/ui++/Test-UippConfig.ps1 -Path ./task-sequences/ui++/configs/ui++.ComputerName.xml
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path $PSScriptRoot 'configs')
)

$ErrorActionPreference = 'Stop'

function Get-UippConfigFile {
    param([Parameter(Mandatory)][string]$Target)

    if (-not (Test-Path -LiteralPath $Target)) {
        throw "Path not found: $Target"
    }

    $item = Get-Item -LiteralPath $Target
    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.xml' -File | Sort-Object Name)
    }

    return @($item)
}

function Test-UippConfigFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $result = [pscustomobject]@{
        File     = $File.Name
        Ok       = $true
        Errors   = @()
        Warnings = @()
        Variables = @()
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $File.FullName -Raw
    }
    catch {
        $result.Ok = $false
        $result.Errors += "Not valid XML: $($_.Exception.Message)"
        return $result
    }

    if ($xml.DocumentElement.LocalName -ne 'UIpp') {
        $result.Ok = $false
        $result.Errors += "Root element is <$($xml.DocumentElement.LocalName)>, expected <UIpp>."
        return $result
    }

    $actions = $xml.DocumentElement.Actions
    if (-not $actions) {
        $result.Ok = $false
        $result.Errors += 'Missing <Actions> section.'
    }

    $all = $xml.SelectNodes('//*')

    foreach ($node in $all) {
        if ($node.Attributes) {
            foreach ($attrName in @('Variable', 'AlternateVariable', 'ApplicationVariableBase', 'PackageVariableBase')) {
                $varAttr = $node.GetAttribute($attrName)
                if (-not $varAttr) { continue }

                $result.Variables += $varAttr
                if ($varAttr -eq 'ComputerName') {
                    $result.Warnings += "$attrName=`"ComputerName`" collides with the Windows env var. Use OSDComputerName."
                }
            }
        }

        if ($node.LocalName -eq 'Action' -and $node.GetAttribute('Type') -eq 'TSVar') {
            $tsName = $node.GetAttribute('Name')
            if ($tsName) {
                $result.Variables += $tsName
                if ($tsName -eq 'ComputerName') {
                    $result.Warnings += 'TSVar Name="ComputerName" collides with the Windows env var. Use OSDComputerName.'
                }
            }
            if ([string]::IsNullOrWhiteSpace($node.InnerText)) {
                $result.Errors += "TSVar '$tsName' has an empty value."
                $result.Ok = $false
            }
        }

        if ($node.LocalName -eq 'Application') {
            $appName = $node.GetAttribute('Name')
            $appId   = $node.GetAttribute('Id')
            if ([string]::IsNullOrWhiteSpace($appId)) {
                $result.Errors += 'Application missing Id=.'
                $result.Ok = $false
            }
            if ([string]::IsNullOrWhiteSpace($appName)) {
                $result.Errors += "Application '$appId' missing Name= (must match ConfigMgr exactly)."
                $result.Ok = $false
            }
            elseif ($appName -like 'Contoso*') {
                $result.Warnings += "Application '$appId' still has placeholder Name='$appName'."
            }
        }

        if ($node.LocalName -eq 'Package') {
            if ([string]::IsNullOrWhiteSpace($node.GetAttribute('PkgId'))) {
                $result.Errors += "Package '$($node.GetAttribute('Id'))' missing PkgId=."
                $result.Ok = $false
            }
            if ([string]::IsNullOrWhiteSpace($node.GetAttribute('Label'))) {
                $result.Errors += "Package '$($node.GetAttribute('Id'))' missing Label= (program name)."
                $result.Ok = $false
            }
            $pkgId = $node.GetAttribute('PkgId')
            if ($pkgId -eq 'CON00001') {
                $result.Warnings += "Package '$($node.GetAttribute('Id'))' still has placeholder PkgId='$pkgId'."
            }
        }

        if ($node.LocalName -eq 'InputText') {
            $regex = $node.GetAttribute('RegEx')
            if ($regex) {
                try {
                    [void][regex]::new($regex)
                }
                catch {
                    $result.Errors += "InputText Variable='$($node.GetAttribute('Variable'))' has invalid RegEx: $regex"
                    $result.Ok = $false
                }
            }
        }
    }

    if ($result.Variables.Count -eq 0 -and $result.Ok) {
        $result.Warnings += 'No Variable= / TSVar Name= attributes found. Is this an empty shell?'
    }

    $result.Variables = @($result.Variables | Select-Object -Unique | Sort-Object)
    return $result
}

$files = Get-UippConfigFile -Target $Path
if ($files.Count -eq 0) {
    throw "No .xml files found under $Path"
}

$results = foreach ($file in $files) {
    Test-UippConfigFile -File $file
}

foreach ($r in $results) {
    $status = if ($r.Ok) { 'OK' } else { 'FAIL' }
    Write-Host "[$status] $($r.File)"

    foreach ($err in $r.Errors) {
        Write-Host "  ERROR: $err" -ForegroundColor Red
    }
    foreach ($warn in $r.Warnings) {
        Write-Host "  WARN:  $warn" -ForegroundColor Yellow
    }
    if ($r.Variables.Count -gt 0) {
        Write-Host "  Vars:  $($r.Variables -join ', ')" -ForegroundColor DarkGray
    }
}

$failed = @($results | Where-Object { -not $_.Ok }).Count
$warned = @($results | Where-Object { $_.Warnings.Count -gt 0 }).Count

Write-Host ''
Write-Host "Checked $($results.Count) file(s): $failed failure(s), $warned with warnings."

if ($failed -gt 0) {
    exit 1
}

exit 0
