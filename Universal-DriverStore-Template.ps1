###############################################################################
# DriverStore Detection Template
#
# This script detects any Windows driver installed by scanning DriverStore
# INF files and looking for the hardware ID(s) and DriverVer entries.
#
# How to use:
# 1. Set $HardwareIDs to the VID/PID/HWIDs of the driver you want to detect.
# 2. Set the minimum acceptable version.
# 3. Deploy with SCCM/Intune — tested under SYSTEM account.
#
###############################################################################

# ----------------------
# DEBUG MODE HANDLING
# ----------------------
$DebugMode = $true   # Manual debug override

# Auto-enable debug mode inside PowerShell ISE
if ($psISE -ne $null) {
    $DebugMode = $true
}

function SafeExit {
    param([int]$code)
    if ($DebugMode) {
        Write-Output "DEBUG MODE: Would exit with code $code"
    } else {
        exit $code
    }
}

# ----------------------
# Config
# ----------------------

# Minimum acceptable driver version
$minVersion = [version]"1.0.0.0"

# Hardware ID(s) to detect
$HardwareIDs = @(
    # ------------------------
    # Realtek USB NIC (8153)
    # ------------------------
    # "VID_0BDA&PID_8153"

    # ------------------------
    # Realtek Audio
    # ------------------------
    # "HDAUDIO\\FUNC_01&VEN_10EC"

    # ------------------------
    # Intel Wi-Fi / Bluetooth
    # ------------------------
    # "VID_8087&PID_0AAA"          # Intel BT
    # "PCI\\VEN_8086&DEV_2725"     # Intel AX201 Wi-Fi
    # "PCI\\VEN_8086&DEV_7A70"     # Intel Wi-Fi 6 AX411

    # ------------------------
    # Intel Chipset / MEI
    # ------------------------
    # "PCI\\VEN_8086&DEV_A0E0"
    # "PCI\\VEN_8086&DEV_43E0"

    # ------------------------
    # NVIDIA GPU
    # ------------------------
    # "PCI\\VEN_10DE&DEV_1C82"     # GTX 1050 Ti
    # "PCI\\VEN_10DE&DEV_2684"     # RTX 3080

    # ------------------------
    # AMD GPU
    # ------------------------
    # "PCI\\VEN_1002&DEV_73BF"     # Radeon RX 6800 XT
    # "PCI\\VEN_1002&DEV_164D"     # Radeon RX 7800 XT

    # ------------------------
    # Dell Touchpad
    # ------------------------
    # "ACPI\\DLL06E4"

    # ------------------------
    # Dell Camera
    # ------------------------
    # "USB\\VID_05A9&PID_08C0"

    # ------------------------
    # *** ADD YOUR DRIVER ID HERE ***
    # ------------------------
)

# Log file location
$logPath = "C:\Windows\CCM\Logs\UniversalDriverDetection.log"

# ----------------------
# Logging
# ----------------------
function Log {
    param([string]$msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $logPath -Value "$timestamp $msg"
}

Log "===== Universal DriverStore Detection Started ====="
Log "Minimum Version Required: $minVersion"
Log "Hardware IDs to scan:"
foreach ($id in $HardwareIDs) { Log "  $id" }

# ----------------------
# DriverStore Scan
# ----------------------
$driverStore = "C:\Windows\System32\DriverStore\FileRepository"

Log "Scanning DriverStore recursively for INF files..."
$infFiles = Get-ChildItem -Path $driverStore -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue

if ($infFiles.Count -eq 0) {
    Log "No INF files found in DriverStore"
    SafeExit 1
}

$found = $false

foreach ($inf in $infFiles) {

    try {
        $content = Get-Content $inf.FullName -ErrorAction Stop
    }
    catch {
        Log "ERROR: Could not read INF file: $($inf.FullName)"
        continue
    }

    # Does the INF contain any matching hardware ID?
    foreach ($hwid in $HardwareIDs) {
        $match = $content | Where-Object { $_ -match $hwid }
        if ($match) {
            Log "Matching INF found: $($inf.FullName)"
            Log "Matched HWID: $hwid"

            # Extract DriverVer line
            $driverVerLine = $content | Where-Object { $_ -match "DriverVer" }
            if (-not $driverVerLine) {
                Log "No DriverVer found in INF: $($inf.Name)"
                continue
            }

            Log "DriverVer Line: $driverVerLine"

            # Extract version after the comma
            if ($driverVerLine -match "DriverVer\s*=\s*\d+/\d+/\d+,\s*([\d\.]+)") {
                $versionString = $Matches[1]
                Log "Parsed INF Version: $versionString"

                try {
                    $versionObj = [version]$versionString
                    
                if ($versionObj -ge $minVersion) {
                    Log "Version PASS: Installed=$versionObj >= Required=$minVersion"

                    Write-Host "Installed"
                    SafeExit 0

                    if ($DebugMode) { 
                        Log "DebugMode active. Exiting nested loops."
                        break 2
                    }
                }
                else {
                        Log "VERSION FAIL: Installed=$versionObj < Required=$minVersion"
                    }
                }
                catch {
                    Log "VERSION PARSE ERROR for INF: $($inf.Name)"
                }
            }
            else {
                Log "DriverVer found but version parsing failed."
            }
        }
    }
}

Log "No driver found matching HardwareID and minimum version."
Log "===== DriverStore detection completed. No matching driver found ====="
SafeExit 1
if ($DebugMode) { break }
