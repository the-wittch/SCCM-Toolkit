<#
.SYNOPSIS
    Look up ConfigMgr maintenance windows by collection, by device, or site-wide.

.DESCRIPTION
    Uses the Configuration Manager PowerShell module (console install required).
    Decodes schedule tokens with Convert-CMSchedule so you get something readable.

    Device lookup uses SMS_FullCollectionMembership (direct + query membership),
    then pulls maintenance windows from each collection the device belongs to.

.PARAMETER CollectionName
    Collection name (wildcards OK).

.PARAMETER CollectionId
    Collection ID (e.g. XYZ000AB).

.PARAMETER ComputerName
    Device name. Returns maintenance windows from every collection that includes it.

.PARAMETER All
    Every device collection that has at least one maintenance window.

.PARAMETER MaintenanceWindowName
    Optional filter on window name (wildcards OK).

.PARAMETER SiteCode
    Three-letter site code. Defaults to env SCCM_SITE_CODE.

.PARAMETER ProviderMachineName
    SMS Provider / site server FQDN. Defaults to env SCCM_PROVIDER_MACHINE.

.EXAMPLE
    ./Get-CcmMaintenanceWindow.ps1 -CollectionName 'Patching-*' -SiteCode XYZ -ProviderMachineName sccm.contoso.com

.EXAMPLE
    ./Get-CcmMaintenanceWindow.ps1 -ComputerName LAT-JSMITH01 -SiteCode XYZ -ProviderMachineName sccm.contoso.com

.EXAMPLE
    $env:SCCM_SITE_CODE = 'XYZ'; $env:SCCM_PROVIDER_MACHINE = 'sccm.contoso.com'
    ./Get-CcmMaintenanceWindow.ps1 -All | Format-Table CollectionName, Name, TypeName, ScheduleText
#>
#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'ByCollectionName')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByCollectionName', Position = 0)]
    [string]$CollectionName,

    [Parameter(Mandatory, ParameterSetName = 'ByCollectionId')]
    [Alias('Id')]
    [string]$CollectionId,

    [Parameter(Mandatory, ParameterSetName = 'ByComputer')]
    [Alias('Name', 'DeviceName')]
    [string]$ComputerName,

    [Parameter(Mandatory, ParameterSetName = 'All')]
    [switch]$All,

    [Parameter()]
    [string]$MaintenanceWindowName,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]{3}$')]
    [string]$SiteCode = $env:SCCM_SITE_CODE,

    [Parameter()]
    [string]$ProviderMachineName = $env:SCCM_PROVIDER_MACHINE
)

$ErrorActionPreference = 'Stop'

function Get-ServiceWindowTypeName {
    param([Parameter()][object]$TypeCode)

    switch ([string]$TypeCode) {
        '1' { 'AllDeployments' }
        '4' { 'SoftwareUpdates' }
        '5' { 'TaskSequences' }
        default { if ($null -eq $TypeCode -or $TypeCode -eq '') { 'Unknown' } else { "Type_$TypeCode" } }
    }
}

function ConvertTo-ScheduleText {
    param([Parameter()][string]$ScheduleString)

    if ([string]::IsNullOrWhiteSpace($ScheduleString)) {
        return $null
    }

    try {
        $decoded = Convert-CMSchedule -ScheduleString $ScheduleString -ErrorAction Stop
    }
    catch {
        return $ScheduleString
    }

    if (-not $decoded) {
        return $ScheduleString
    }

    # Convert-CMSchedule may return one object or many; pull the useful fields.
    $parts = foreach ($item in @($decoded)) {
        if ($item -is [string]) {
            $item
            continue
        }

        $bits = [System.Collections.Generic.List[string]]::new()
        foreach ($prop in @(
                'StartTime', 'DayDuration', 'HourDuration', 'MinuteDuration',
                'DaySpan', 'HourSpan', 'MinuteSpan', 'ForNumberOfWeeks',
                'WeekOrder', 'Day', 'IsGmt'
            )) {
            if ($item.PSObject.Properties[$prop] -and $null -ne $item.$prop -and [string]$item.$prop -ne '') {
                $bits.Add("${prop}=$($item.$prop)")
            }
        }

        if ($bits.Count -gt 0) {
            ($bits -join ', ')
        }
        else {
            ([string]$item).Trim()
        }
    }

    (($parts | Where-Object { $_ }) -join ' | ')
}

function Connect-CcmSiteDrive {
    param(
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ProviderMachineName
    )

    if (-not (Get-Module -Name ConfigurationManager -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($env:SMS_ADMIN_UI_PATH)) {
            throw 'ConfigurationManager module not loaded and SMS_ADMIN_UI_PATH is not set. Install/launch the ConfigMgr console once on this box.'
        }

        $modulePath = Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1'
        Import-Module $modulePath -ErrorAction Stop
    }

    $drive = Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue
    if (-not $drive) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -Description 'SCCM-Toolkit' -ErrorAction Stop | Out-Null
    }

    Set-Location "$($SiteCode):\" -ErrorAction Stop
}

function Get-CollectionTarget {
    param(
        [Parameter()][string]$CollectionName,
        [Parameter()][string]$CollectionId
    )

    if ($CollectionId) {
        $coll = Get-CMCollection -CollectionId $CollectionId -ErrorAction SilentlyContinue
        if (-not $coll) {
            throw "Collection not found: $CollectionId"
        }
        return @($coll)
    }

    $colls = @(Get-CMCollection -Name $CollectionName -ErrorAction SilentlyContinue)
    if ($colls.Count -eq 0) {
        throw "No collections matched: $CollectionName"
    }
    return $colls
}

function Get-CollectionIdForDevice {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ProviderMachineName
    )

    $ns = "root\sms\site_$SiteCode"
    $escaped = $ComputerName.Replace("'", "''")

    # Full membership = direct + query/include. That's what applies for MW evaluation.
    try {
        $members = @(
            Get-CimInstance -ComputerName $ProviderMachineName -Namespace $ns -ClassName SMS_FullCollectionMembership -Filter "Name = '$escaped'" -ErrorAction Stop
        )
    }
    catch {
        throw "Couldn't query SMS_FullCollectionMembership on $ProviderMachineName ($ns): $($_.Exception.Message)"
    }

    if ($members.Count -eq 0) {
        # Case / exact name miss — try ResourceID via Get-CMDevice
        $device = Get-CMDevice -Name $ComputerName -Fast -ErrorAction SilentlyContinue
        if (-not $device) {
            throw "Device not found in site: $ComputerName"
        }

        $resId = [uint32]$device.ResourceID
        $members = @(
            Get-CimInstance -ComputerName $ProviderMachineName -Namespace $ns -ClassName SMS_FullCollectionMembership -Filter "ResourceID = $resId" -ErrorAction Stop
        )
    }

    if ($members.Count -eq 0) {
        throw "Device '$ComputerName' found but has no collection membership rows."
    }

    return @($members.CollectionID | Select-Object -Unique)
}

function Get-MaintenanceWindowRow {
    param(
        [Parameter(Mandatory)]$Collection,
        [Parameter()]$Window,
        [Parameter()][string]$ComputerName
    )

    $scheduleText = ConvertTo-ScheduleText -ScheduleString ([string]$Window.ServiceWindowSchedules)

    [pscustomobject]@{
        ComputerName     = $ComputerName
        CollectionName   = [string]$Collection.Name
        CollectionId     = [string]$Collection.CollectionID
        Name             = [string]$Window.Name
        Description      = [string]$Window.Description
        Type             = $Window.ServiceWindowType
        TypeName         = Get-ServiceWindowTypeName -TypeCode $Window.ServiceWindowType
        Enabled          = [bool]$Window.IsEnabled
        IsUtc            = [bool]$Window.IsUtc
        Duration         = $Window.Duration
        ScheduleText     = $scheduleText
        ScheduleToken    = [string]$Window.ServiceWindowSchedules
        ServiceWindowId  = [string]$Window.ServiceWindowID
    }
}

function Get-WindowsForCollection {
    param(
        [Parameter(Mandatory)]$Collection,
        [Parameter()][string]$MaintenanceWindowName,
        [Parameter()][string]$ComputerName
    )

    $windows = @(Get-CMMaintenanceWindow -CollectionId $Collection.CollectionID -ErrorAction SilentlyContinue)
    if ($MaintenanceWindowName) {
        $windows = @($windows | Where-Object { $_.Name -like $MaintenanceWindowName })
    }

    foreach ($window in $windows) {
        Get-MaintenanceWindowRow -Collection $Collection -Window $window -ComputerName $ComputerName
    }
}

# --- main ---
if ([string]::IsNullOrWhiteSpace($SiteCode) -or [string]::IsNullOrWhiteSpace($ProviderMachineName)) {
    throw @"
SiteCode and ProviderMachineName are required.
Pass -SiteCode / -ProviderMachineName, or set:
  `$env:SCCM_SITE_CODE
  `$env:SCCM_PROVIDER_MACHINE
"@
}

$SiteCode = $SiteCode.ToUpperInvariant()
$originalLocation = Get-Location
$createdDrive = $false

try {
    $existingDrive = Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue
    Connect-CcmSiteDrive -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName
    if (-not $existingDrive) {
        $createdDrive = $true
    }

    $rows = @()

    switch ($PSCmdlet.ParameterSetName) {
        'ByCollectionName' {
            foreach ($coll in (Get-CollectionTarget -CollectionName $CollectionName)) {
                $rows += @(Get-WindowsForCollection -Collection $coll -MaintenanceWindowName $MaintenanceWindowName)
            }
        }
        'ByCollectionId' {
            foreach ($coll in (Get-CollectionTarget -CollectionId $CollectionId)) {
                $rows += @(Get-WindowsForCollection -Collection $coll -MaintenanceWindowName $MaintenanceWindowName)
            }
        }
        'ByComputer' {
            $collectionIds = Get-CollectionIdForDevice -ComputerName $ComputerName -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName
            foreach ($id in $collectionIds) {
                $coll = Get-CMCollection -CollectionId $id -ErrorAction SilentlyContinue
                if (-not $coll) { continue }
                $rows += @(Get-WindowsForCollection -Collection $coll -MaintenanceWindowName $MaintenanceWindowName -ComputerName $ComputerName)
            }
        }
        'All' {
            Write-Verbose "Enumerating device collections with maintenance windows (All=$All)."
            $deviceCollections = @(Get-CMCollection -CollectionType Device -ErrorAction Stop)
            foreach ($coll in $deviceCollections) {
                $hit = @(Get-WindowsForCollection -Collection $coll -MaintenanceWindowName $MaintenanceWindowName)
                if ($hit.Count -gt 0) {
                    $rows += $hit
                }
            }
        }
    }

    if ($rows.Count -eq 0) {
        Write-Warning 'No maintenance windows matched.'
        return
    }

    $rows |
        Sort-Object CollectionName, Name |
        ForEach-Object { $_ }
}
finally {
    Set-Location $originalLocation -ErrorAction SilentlyContinue

    if ($createdDrive) {
        Remove-PSDrive -Name $SiteCode -Force -ErrorAction SilentlyContinue
    }
}
