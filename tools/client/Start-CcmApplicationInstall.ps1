<#
.SYNOPSIS
    Kick off one or more ConfigMgr (CCM) Application installs from the local client SDK.

.DESCRIPTION
    Talks to ROOT\ccm\ClientSDK\CCM_Application on the machine you're sitting on.
    Useful when an app is deployed as Available and you'd rather not click Software Center,
    or when you're scripting a lab box through a known set of apps.

.PARAMETER Name
    One or more FullName filters (wildcards OK). Required so we don't try to install
    every available app on the box by accident.

.PARAMETER Force
    Start install even if InstallState is already Installed.

.PARAMETER Priority
    CCM priority string. Normal is fine for humans. Foreground if you're impatient.

.PARAMETER EnforcePreference
    0 = Immediate (default), 1 = NonBusinessHours, 2 = AdminSchedule.

.EXAMPLE
    ./Start-CcmApplicationInstall.ps1 -Name '*Company Portal*','*7-Zip*' -WhatIf

.EXAMPLE
    ./Start-CcmApplicationInstall.ps1 -Name '*Chrome*' -Force
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [Alias('FullName')]
    [string[]]$Name,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateSet('Normal', 'High', 'Low', 'Foreground')]
    [string]$Priority = 'Normal',

    [Parameter()]
    [ValidateSet(0, 1, 2)]
    [int]$EnforcePreference = 0
)

$ErrorActionPreference = 'Stop'

$namespace = 'ROOT\ccm\ClientSDK'

try {
    $apps = Get-CimInstance -Namespace $namespace -ClassName 'CCM_Application' -ErrorAction Stop
}
catch {
    throw @"
Couldn't talk to $namespace\CCM_Application.
Is the ConfigMgr client installed on this box, and are you elevating?
$($_.Exception.Message)
"@
}

$matched = foreach ($app in $apps) {
    foreach ($pattern in $Name) {
        if ($app.FullName -like $pattern) {
            $app
            break
        }
    }
}

$matched = @($matched | Sort-Object FullName -Unique)

if ($matched.Count -eq 0) {
    Write-Warning "No CCM applications matched: $($Name -join ', ')"
    return
}

foreach ($app in $matched) {
    $fullName = [string]$app.FullName
    $state    = [string]$app.InstallState

    if (-not $Force -and $state -eq 'Installed') {
        Write-Host "$fullName is already installed."
        continue
    }

    if ([int]$app.ErrorCode -ne 0) {
        Write-Warning "$fullName has ErrorCode $($app.ErrorCode) — skipping. Fix policy/eval first."
        continue
    }

    $target = if ($app.IsMachineTarget) { 'machine' } else { 'user' }
    $action = "Install CCM app '$fullName' (rev $($app.Revision), $target target, state=$state)"

    if (-not $PSCmdlet.ShouldProcess($fullName, $action)) {
        continue
    }

    Write-Host "Starting install: $fullName ..."

    try {
        $result = Invoke-CimMethod -Namespace $namespace -ClassName 'CCM_Application' -MethodName 'Install' -Arguments @{
            Id                = [string]$app.Id
            Revision          = [string]$app.Revision
            IsMachineTarget   = [bool]$app.IsMachineTarget
            EnforcePreference = [uint32]$EnforcePreference
            Priority          = $Priority
            IsRebootIfNeeded  = $false
        } -ErrorAction Stop

        if ($result -and $result.PSObject.Properties['ReturnValue'] -and [int]$result.ReturnValue -ne 0) {
            Write-Warning "$fullName Install() returned $($result.ReturnValue)"
        }
        else {
            Write-Host "Submitted: $fullName"
        }
    }
    catch {
        Write-Warning "Failed to start '$fullName': $($_.Exception.Message)"
    }
}
