###############################################################################
# Driver Detection Template
#
#
# Modes:
#   Active  - device is using the matching signed driver (preferred)
#   Store   - package is in the DriverStore (may not be bound yet)
#
# Setup:
# 1. Uncomment / add your HWID(s) below.
# 2. Set $minVersion to the minimum acceptable version.
# 3. Leave DetectionMode on Active unless you need Store.
# 4. Paste into ConfigMgr app detection (PowerShell). Runs as SYSTEM.
#
# Exit codes:
#   0 + prints "Installed"  = detected
#   1                       = not found, too old, or $HardwareIDs is empty
#
###############################################################################

#Requires -Version 5.1

# ----------------------
# DEBUG MODE
# ----------------------
# Leave false for ConfigMgr. Auto-enabled in PowerShell ISE.
$DebugMode = $false

if ($null -ne $psISE) {
    $DebugMode = $true
}

function SafeExit {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(0, 1)]
        [int]$Code
    )

    if ($DebugMode) {
        Write-Output "DEBUG MODE: Would exit with code $Code"
        return
    }

    exit $Code
}

# ----------------------
# Config
# ----------------------

# Minimum acceptable driver version
$minVersion = [version]'1.0.0.0'

# Active = what's bound on the device (preferred)
# Store  = package showed up in the DriverStore (may not be the active one)
$DetectionMode = 'Active'

# HWID fragments. Substring match, case doesn't matter.
# Examples below are commented out. Uncomment the one you need, or add your own.
$HardwareIDs = @(
    # Realtek USB NIC (8153)
    # 'VID_0BDA&PID_8153'

    # Realtek Audio
    # 'HDAUDIO\FUNC_01&VEN_10EC'

    # Intel Wi-Fi / Bluetooth
    # 'VID_8087&PID_0AAA'          # Intel BT
    # 'PCI\VEN_8086&DEV_2725'      # Intel AX201 Wi-Fi
    # 'PCI\VEN_8086&DEV_7A70'      # Intel Wi-Fi 6 AX411

    # Intel Chipset / MEI
    # 'PCI\VEN_8086&DEV_A0E0'
    # 'PCI\VEN_8086&DEV_43E0'

    # NVIDIA
    # 'PCI\VEN_10DE&DEV_1C82'      # GTX 1050 Ti
    # 'PCI\VEN_10DE&DEV_2684'      # RTX 3080

    # AMD
    # 'PCI\VEN_1002&DEV_73BF'      # Radeon RX 6800 XT
    # 'PCI\VEN_1002&DEV_164D'      # Radeon RX 7800 XT

    # Dell touchpad / camera
    # 'ACPI\DLL06E4'
    # 'USB\VID_05A9&PID_08C0'

    # <-- your HWID goes here
)

$logPath = 'C:\Windows\CCM\Logs\UniversalDriverDetection.log'

# ----------------------
# Helpers
# ----------------------
function Write-DetectLog {
    param([Parameter(Mandatory)][string]$Message)

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "$timestamp $Message"

    try {
        $logDir = Split-Path -Parent $logPath
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -LiteralPath $logPath -Value $line -ErrorAction Stop
    }
    catch {
        # Logging failed; detection still needs to return a result.
        Write-Verbose $line
    }
}

function Test-HardwareIdMatch {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Candidate,
        [Parameter(Mandatory)][string[]]$Ids
    )

    foreach ($id in $Ids) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($Candidate -like "*$id*") {
            return $id
        }
    }

    return $null
}

function ConvertTo-DriverVersion {
    param([Parameter(Mandatory)][string]$VersionString)

    $normalized = $VersionString.Trim()
    if ($normalized -notmatch '^\d+(\.\d+){1,3}$') {
        return $null
    }

    try {
        return [version]$normalized
    }
    catch {
        return $null
    }
}

function Get-DriverVerFromInf {
    param([Parameter(Mandatory)][string]$InfPath)

    try {
        $content = Get-Content -LiteralPath $InfPath -ErrorAction Stop
    }
    catch {
        return $null
    }

    # DriverVer=mm/dd/yyyy,w.x.y.z — grab the first one and move on
    $driverVerLine = @(
        $content | Where-Object { $_ -match '^\s*DriverVer\s*=' }
    ) | Select-Object -First 1

    if (-not $driverVerLine) {
        return $null
    }

    if ($driverVerLine -match 'DriverVer\s*=\s*\d{1,2}/\d{1,2}/\d{2,4}\s*,\s*([\d\.]+)') {
        return @{
            Line    = [string]$driverVerLine
            Version = ConvertTo-DriverVersion -VersionString $Matches[1]
            Raw     = $Matches[1]
        }
    }

    return @{
        Line    = [string]$driverVerLine
        Version = $null
        Raw     = $null
    }
}

function Test-ActiveDriver {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [Parameter(Mandatory)][version]$MinVersion
    )

    Write-DetectLog 'Querying Win32_PnPSignedDriver for active/signed drivers...'

    try {
        $signedDrivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
    }
    catch {
        Write-DetectLog "ERROR: Win32_PnPSignedDriver query failed: $($_.Exception.Message)"
        return $false
    }

    foreach ($driver in $signedDrivers) {
        $candidateIds = @()
        if ($driver.HardWareID) { $candidateIds += @($driver.HardWareID) }
        if ($driver.DeviceID) { $candidateIds += [string]$driver.DeviceID }

        $matchedId = $null
        foreach ($candidate in $candidateIds) {
            $matchedId = Test-HardwareIdMatch -Candidate ([string]$candidate) -Ids $Ids
            if ($matchedId) { break }
        }

        if (-not $matchedId) { continue }

        Write-DetectLog "Active match: Device='$($driver.DeviceName)' Inf='$($driver.InfName)' HWID='$matchedId'"

        if ([string]::IsNullOrWhiteSpace($driver.DriverVersion)) {
            Write-DetectLog 'Active driver has empty DriverVersion; skipping.'
            continue
        }

        $versionObj = ConvertTo-DriverVersion -VersionString $driver.DriverVersion
        if (-not $versionObj) {
            Write-DetectLog "VERSION PARSE ERROR (active): '$($driver.DriverVersion)'"
            continue
        }

        Write-DetectLog "Parsed active version: $versionObj"

        if ($versionObj -ge $MinVersion) {
            Write-DetectLog "Version PASS (active): Installed=$versionObj >= Required=$MinVersion"
            return $true
        }

        Write-DetectLog "VERSION FAIL (active): Installed=$versionObj < Required=$MinVersion"
    }

    return $false
}

function Test-StoreDriver {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [Parameter(Mandatory)][version]$MinVersion
    )

    Write-DetectLog 'Querying Get-WindowsDriver -Online for DriverStore packages...'

    try {
        $storeDrivers = Get-WindowsDriver -Online -ErrorAction Stop
    }
    catch {
        Write-DetectLog "Get-WindowsDriver failed ($($_.Exception.Message)); falling back to FileRepository scan."
        return Test-StoreDriverFallback -Ids $Ids -MinVersion $MinVersion
    }

    foreach ($driver in $storeDrivers) {
        $infPath = [string]$driver.Driver
        if ([string]::IsNullOrWhiteSpace($infPath) -or -not (Test-Path -LiteralPath $infPath)) {
            continue
        }

        try {
            $content = Get-Content -LiteralPath $infPath -ErrorAction Stop
        }
        catch {
            Write-DetectLog "ERROR: Could not read INF: $infPath"
            continue
        }

        $joined = ($content -join "`n")
        $matchedId = $null
        foreach ($id in $Ids) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            # Plain substring match. Regex and backslashes in HWIDs do not mix well.
            if ($joined.IndexOf($id, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matchedId = $id
                break
            }
        }

        if (-not $matchedId) { continue }

        Write-DetectLog "Store INF match: $infPath"
        Write-DetectLog "Matched HWID: $matchedId"

        $versionObj = $null
        if ($driver.Version) {
            $versionObj = ConvertTo-DriverVersion -VersionString ([string]$driver.Version)
            if ($versionObj) {
                Write-DetectLog "Parsed store version (Get-WindowsDriver): $versionObj"
            }
        }

        if (-not $versionObj) {
            $fromInf = Get-DriverVerFromInf -InfPath $infPath
            if ($fromInf -and $fromInf.Line) {
                Write-DetectLog "DriverVer Line: $($fromInf.Line)"
            }
            if ($fromInf -and $fromInf.Version) {
                $versionObj = $fromInf.Version
                Write-DetectLog "Parsed store version (INF): $versionObj"
            }
            else {
                Write-DetectLog "DriverVer found but version parsing failed for: $infPath"
                continue
            }
        }

        if ($versionObj -ge $MinVersion) {
            Write-DetectLog "Version PASS (store): Installed=$versionObj >= Required=$MinVersion"
            return $true
        }

        Write-DetectLog "VERSION FAIL (store): Installed=$versionObj < Required=$MinVersion"
    }

    return $false
}

function Test-StoreDriverFallback {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [Parameter(Mandatory)][version]$MinVersion
    )

    $driverStore = 'C:\Windows\System32\DriverStore\FileRepository'
    Write-DetectLog "Fallback: scanning $driverStore for INF files..."

    $infFiles = Get-ChildItem -Path $driverStore -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue
    if (-not $infFiles -or $infFiles.Count -eq 0) {
        Write-DetectLog 'No INF files found in DriverStore'
        return $false
    }

    foreach ($inf in $infFiles) {
        try {
            $content = Get-Content -LiteralPath $inf.FullName -ErrorAction Stop
        }
        catch {
            Write-DetectLog "ERROR: Could not read INF file: $($inf.FullName)"
            continue
        }

        $joined = ($content -join "`n")
        $matchedId = $null
        foreach ($id in $Ids) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if ($joined.IndexOf($id, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matchedId = $id
                break
            }
        }

        if (-not $matchedId) { continue }

        Write-DetectLog "Matching INF found: $($inf.FullName)"
        Write-DetectLog "Matched HWID: $matchedId"

        $fromInf = Get-DriverVerFromInf -InfPath $inf.FullName
        if (-not $fromInf -or -not $fromInf.Line) {
            Write-DetectLog "No DriverVer found in INF: $($inf.Name)"
            continue
        }

        Write-DetectLog "DriverVer Line: $($fromInf.Line)"

        if (-not $fromInf.Version) {
            Write-DetectLog "DriverVer found but version parsing failed for: $($inf.Name)"
            continue
        }

        Write-DetectLog "Parsed INF Version: $($fromInf.Raw)"

        if ($fromInf.Version -ge $MinVersion) {
            Write-DetectLog "Version PASS (fallback): Installed=$($fromInf.Version) >= Required=$MinVersion"
            return $true
        }

        Write-DetectLog "VERSION FAIL (fallback): Installed=$($fromInf.Version) < Required=$MinVersion"
    }

    return $false
}

# ----------------------
# Main
# ----------------------
Write-DetectLog '===== Universal Driver Detection Started ====='
Write-DetectLog "DetectionMode: $DetectionMode"
Write-DetectLog "Minimum Version Required: $minVersion"
Write-DetectLog 'Hardware IDs to scan:'

$configuredIds = @(
    $HardwareIDs |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() }
)

if ($configuredIds.Count -eq 0) {
    Write-DetectLog 'ERROR: $HardwareIDs is empty. Uncomment one or paste your own.'
    Write-DetectLog '===== Driver detection aborted (misconfigured) ====='
    SafeExit 1
    return
}

foreach ($id in $configuredIds) {
    Write-DetectLog "  $id"
}

$detected = $false

switch ($DetectionMode) {
    'Active' {
        $detected = Test-ActiveDriver -Ids $configuredIds -MinVersion $minVersion
    }
    'Store' {
        $detected = Test-StoreDriver -Ids $configuredIds -MinVersion $minVersion
    }
    default {
        Write-DetectLog "ERROR: Unknown DetectionMode '$DetectionMode'. Use 'Active' or 'Store'."
        SafeExit 1
        return
    }
}

if ($detected) {
    Write-Output 'Installed'
    Write-DetectLog '===== Driver detection completed: Installed ====='
    SafeExit 0
    return
}

Write-DetectLog 'No driver found matching HardwareID and minimum version.'
Write-DetectLog '===== Driver detection completed. No matching driver found ====='
SafeExit 1
