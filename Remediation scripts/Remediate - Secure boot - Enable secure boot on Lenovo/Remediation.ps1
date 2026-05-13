<#
.DESCRIPTION
    Intune remediation script to enable Secure Boot on Lenovo devices.
    Supports both old and new Lenovo BIOS WMI methods.

    Features:
    - No model filtering
    - Lenovo manufacturer check only
    - Detects legacy vs modern Lenovo BIOS method
    - Handles BIOS password state detection
    - Supports passwordless flow by default
    - Suspends BitLocker for 1 reboot
    - Stages Secure Boot in BIOS
    - Saves BIOS settings using correct method
    - Schedules reboot at 1 AM
    - Enables Task Scheduler history

.NOTES
    PowerShell 5.1 compatible

    IMPORTANT:
    - If BIOS Supervisor password is set, you must provide it in $SupervisorPassword
    - If password is unknown, script will stop safely
#>

# ============================================================
# Remediate-SecureBoot-Lenovo-Hybrid.ps1
# ============================================================

$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\SecureBoot_Remediation.log"
$RebootTaskName = "Intune-SecureBoot-1AM-Reboot"

# ------------------------------------------------------------
# OPTIONAL BIOS PASSWORD
# Leave blank if no BIOS Supervisor password is configured
# ------------------------------------------------------------
$SupervisorPassword = ""

function Write-Log {
    param([string]$Message)

    $folder = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogPath -Append -Encoding utf8
}

function Stop-WithError {
    param(
        [string]$Message,
        [int]$Code = 1
    )

    Write-Log "ERROR: $Message"
    Write-Error $Message
    exit $Code
}

function Get-Next1AM {
    $now = Get-Date
    $target = Get-Date -Hour 1 -Minute 0 -Second 0

    if ($now -ge $target) {
        $target = $target.AddDays(1)
    }

    return $target
}

function Schedule-RebootAt1AM {
    param([string]$TaskName = "Intune-SecureBoot-1AM-Reboot")

    $rebootTime = Get-Next1AM
    Write-Log "Scheduling reboot task '$TaskName' for $($rebootTime.ToString('yyyy-MM-dd HH:mm:ss'))"

    try {
        wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true
        Write-Log "Task Scheduler history enabled."
    }
    catch {
        Write-Log "Failed to enable Task Scheduler history: $($_.Exception.Message)"
    }

    try {
        $svc = Get-Service -Name Schedule -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Start-Service -Name Schedule -ErrorAction Stop
            Write-Log "Task Scheduler service started."
        }
        else {
            Write-Log "Task Scheduler service already running."
        }
    }
    catch {
        Stop-WithError "Task Scheduler service is not available. $($_.Exception.Message)"
    }

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Removed any existing task named '$TaskName'."
    }
    catch {
        Write-Log "No existing task to remove or removal failed silently."
    }

    $created = $false

    # Method 1 - Register-ScheduledTask
    try {
        $action = New-ScheduledTaskAction -Execute "C:\Windows\System32\shutdown.exe" -Argument "/r /f /t 0"
        $trigger = New-ScheduledTaskTrigger -Once -At $rebootTime
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force | Out-Null

        Start-Sleep -Seconds 2

        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            $info = Get-ScheduledTaskInfo -TaskName $TaskName
            Write-Log "Scheduled task created successfully with Register-ScheduledTask. NextRunTime: $($info.NextRunTime)"
            $created = $true
        }
        else {
            Write-Log "Register-ScheduledTask returned no error, but task was not found afterward."
        }
    }
    catch {
        Write-Log "Register-ScheduledTask failed: $($_.Exception.Message)"
    }

    # Method 2 - schtasks fallback
    if (-not $created) {
        try {
            Write-Log "Falling back to schtasks.exe"

            $taskDate = $rebootTime.ToString("MM/dd/yyyy")
            $taskTime = $rebootTime.ToString("HH:mm")
            $taskCommand = '"C:\Windows\System32\shutdown.exe" /r /f /t 0'

            $output = & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $TaskName /SC ONCE /SD $taskDate /ST $taskTime /RU SYSTEM /RL HIGHEST /TR $taskCommand /F 2>&1
            $exitCode = $LASTEXITCODE

            Write-Log "schtasks create exit code: $exitCode"
            Write-Log "schtasks output: $($output | Out-String)"

            Start-Sleep -Seconds 2

            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if (($exitCode -eq 0) -and ($null -ne $task)) {
                $info = Get-ScheduledTaskInfo -TaskName $TaskName
                Write-Log "Scheduled task created successfully with schtasks fallback. NextRunTime: $($info.NextRunTime)"
                $created = $true
            }
            else {
                Write-Log "schtasks fallback did not create the task."
            }
        }
        catch {
            Write-Log "schtasks.exe fallback failed: $($_.Exception.Message)"
        }
    }

    if (-not $created) {
        Stop-WithError "Failed to create scheduled reboot task."
    }

    Write-Log "Reboot task successfully scheduled."
    return $rebootTime
}

function Invoke-LegacySetBiosSetting {
    param(
        [Parameter(Mandatory = $true)][object]$SetClass,
        [Parameter(Mandatory = $true)][string[]]$CandidateValues
    )

    $setSucceeded = $false
    $usedValue = $null
    $lastReturn = $null

    foreach ($value in $CandidateValues) {
        try {
            Write-Log "Legacy method: trying SetBiosSetting('$value')"
            $result = $SetClass.SetBiosSetting($value)
            $ret = [string]$result.Return
            $lastReturn = $ret
            Write-Log "Legacy SetBiosSetting return: $ret"

            switch ($ret) {
                "Success" {
                    $setSucceeded = $true
                    $usedValue = $value
                    break
                }
                "System Busy" {
                    Stop-WithError "BIOS reports System Busy. Reboot device and retry."
                }
                "Access Denied" {
                    Stop-WithError "BIOS change denied. Supervisor password may be set."
                }
                "Invalid Parameter" {
                    Write-Log "Legacy method rejected value '$value'."
                }
                default {
                    Write-Log "Legacy method returned '$ret' for '$value'."
                }
            }

            if ($setSucceeded) { break }
        }
        catch {
            Write-Log "Legacy SetBiosSetting exception for '$value': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Success    = $setSucceeded
        UsedValue  = $usedValue
        LastReturn = $lastReturn
    }
}

function Save-LegacyBiosSettings {
    param(
        [Parameter(Mandatory = $true)][object]$SaveClass
    )

    try {
        Write-Log "Legacy method: calling SaveBiosSettings()"
        $saveResult = $SaveClass.SaveBiosSettings()
        $saveReturn = [string]$saveResult.Return
        Write-Log "Legacy SaveBiosSettings return: $saveReturn"
        return $saveReturn
    }
    catch {
        Write-Log "Legacy SaveBiosSettings exception: $($_.Exception.Message)"
        return "Exception"
    }
}

function Invoke-ModernOpcode {
    param(
        [Parameter(Mandatory = $true)][object]$OpcodeClass,
        [string]$SupervisorPassword
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SupervisorPassword)) {
            Write-Log "Modern method: no BIOS password provided, skipping password opcode."
        }
        else {
            Write-Log "Modern method: sending supervisor password opcode."
            $r1 = $OpcodeClass.WmiOpcodeInterface("WmiOpcodePasswordAdmin:$SupervisorPassword")
            Write-Log "Opcode password result: $([string]$r1.Return)"
        }

        Write-Log "Modern method: committing opcode sequence."
        $r2 = $OpcodeClass.WmiOpcodeInterface("WmiOpcodePasswordSetUpdate")
        Write-Log "Opcode commit result: $([string]$r2.Return)"

        return [string]$r2.Return
    }
    catch {
        Write-Log "Modern opcode exception: $($_.Exception.Message)"
        return "Exception"
    }
}

Write-Log "===== REMEDIATION START ====="

# ------------------------------------------------------------
# Device info
# ------------------------------------------------------------
try {
    $csp = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
    $cs  = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

    $productName    = ([string]$csp.Name).Trim()
    $productVersion = ([string]$csp.Version).Trim()
    $systemModel    = ([string]$cs.Model).Trim()
    $manufacturer   = ([string]$cs.Manufacturer).Trim()

    Write-Log "Manufacturer: '$manufacturer'"
    Write-Log "Win32_ComputerSystemProduct.Name: '$productName'"
    Write-Log "Win32_ComputerSystemProduct.Version: '$productVersion'"
    Write-Log "Win32_ComputerSystem.Model: '$systemModel'"
}
catch {
    Stop-WithError "Unable to read model information. $($_.Exception.Message)"
}

if ($manufacturer -notmatch 'Lenovo') {
    Write-Log "STATUS: SKIPPED - Manufacturer is not Lenovo."
    Write-Output "SKIPPED - Manufacturer not targeted ($manufacturer)"
    exit 0
}

Write-Log "Device is Lenovo. Proceeding."

# ------------------------------------------------------------
# Secure Boot / UEFI checks
# ------------------------------------------------------------
try {
    $secureBoot = Confirm-SecureBootUEFI 2>$null
    if ($secureBoot -eq $true) {
        Write-Log "Secure Boot already enabled. Nothing to do."
        Write-Output "Secure Boot already enabled"
        exit 0
    }
    else {
        Write-Log "Secure Boot currently disabled."
    }
}
catch {
    Write-Log "Could not confirm current Secure Boot state on first check. Continuing."
}

try {
    $null = Confirm-SecureBootUEFI 2>$null
    Write-Log "UEFI confirmed."
}
catch {
    Stop-WithError "Device is not in UEFI mode or Secure Boot state cannot be queried."
}

# ------------------------------------------------------------
# Lenovo BIOS WMI classes
# ------------------------------------------------------------
try {
    $biosSettings = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosSetting -ErrorAction Stop
    $setClass     = Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting -ErrorAction Stop
    $saveClass    = Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings -ErrorAction SilentlyContinue
    $pwdClass     = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosPasswordSettings -ErrorAction SilentlyContinue
    $opcodeClass  = Get-WmiObject -Namespace root\wmi -Class Lenovo_WmiOpcodeInterface -ErrorAction SilentlyContinue

    Write-Log "Lenovo BIOS WMI classes loaded."
    if ($saveClass)    { Write-Log "Legacy SaveBiosSettings class available." }
    if ($opcodeClass)  { Write-Log "Modern WmiOpcodeInterface class available." }
    if (-not $saveClass)   { Write-Log "Legacy SaveBiosSettings class NOT available." }
    if (-not $opcodeClass) { Write-Log "Modern WmiOpcodeInterface class NOT available." }
}
catch {
    Write-Log "STATUS: SKIPPED - Lenovo BIOS WMI provider/classes not available."
    Write-Output "SKIPPED - Lenovo BIOS WMI provider/classes not available"
    exit 0
}

# ------------------------------------------------------------
# Log relevant BIOS settings
# ------------------------------------------------------------
try {
    $allSettings = @($biosSettings | Select-Object -ExpandProperty CurrentSetting)
    $relatedSettings = $allSettings | Where-Object { $_ -match 'Secure|UEFI|Boot|Platform|Mode' } | Sort-Object

    foreach ($line in $relatedSettings) {
        Write-Log "BIOS_SETTING: $line"
    }
}
catch {
    Stop-WithError "Failed reading Lenovo BIOS settings. $($_.Exception.Message)"
}

$secureCandidates = $allSettings | Where-Object { $_ -match 'SecureBoot|Secure Boot' }
if (-not $secureCandidates -or $secureCandidates.Count -eq 0) {
    Write-Log "STATUS: SKIPPED - Secure Boot BIOS setting not exposed on this model."
    Write-Output "SKIPPED - Secure Boot BIOS setting not exposed on this model"
    exit 0
}

# ------------------------------------------------------------
# BIOS password state
# ------------------------------------------------------------
$biosPasswordSet = $false

try {
    if ($pwdClass) {
        Write-Log "BIOS PasswordState: $($pwdClass.PasswordState)"
        if ([int]$pwdClass.PasswordState -ne 0) {
            $biosPasswordSet = $true
        }
    }
    else {
        Write-Log "Lenovo_BiosPasswordSettings class not available."
    }
}
catch {
    Write-Log "Could not read BIOS password state."
}

if ($biosPasswordSet -and [string]::IsNullOrWhiteSpace($SupervisorPassword)) {
    Stop-WithError "BIOS Supervisor password appears to be set, but no password was provided in the script."
}

# ------------------------------------------------------------
# Suspend BitLocker
# ------------------------------------------------------------
try {
    $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    if ($bl.ProtectionStatus -eq "On") {
        Write-Log "Suspending BitLocker for 1 reboot."
        Suspend-BitLocker -MountPoint "C:" -RebootCount 1 | Out-Null
        Write-Log "BitLocker suspended successfully."
    }
    else {
        Write-Log "BitLocker is already suspended or not enabled."
    }
}
catch {
    Stop-WithError "Failed to suspend BitLocker. $($_.Exception.Message)"
}

# ------------------------------------------------------------
# Stage Secure Boot
# ------------------------------------------------------------
$possibleValues = @(
    "SecureBoot,Enable",
    "Secure Boot,Enable",
    "SecureBoot,Enabled",
    "Secure Boot,Enabled"
)

$stageResult = Invoke-LegacySetBiosSetting -SetClass $setClass -CandidateValues $possibleValues

if (-not $stageResult.Success) {
    Stop-WithError "Could not stage Secure Boot. Last result: $($stageResult.LastReturn)"
}

Write-Log "Secure Boot successfully staged using value '$($stageResult.UsedValue)'."

# ------------------------------------------------------------
# Save BIOS changes
# Try modern opcode first if available, then legacy save
# ------------------------------------------------------------
$saveSucceeded = $false
$saveMethodUsed = $null

if ($opcodeClass) {
    Write-Log "Attempting modern Lenovo save flow first."
    $opcodeReturn = Invoke-ModernOpcode -OpcodeClass $opcodeClass -SupervisorPassword $SupervisorPassword

    if ($opcodeReturn -eq "Success") {
        $saveSucceeded = $true
        $saveMethodUsed = "ModernOpcode"
        Write-Log "Modern opcode save flow succeeded."
    }
    else {
        Write-Log "Modern opcode save flow failed with result: $opcodeReturn"
    }
}

if (-not $saveSucceeded -and $saveClass) {
    Write-Log "Attempting legacy SaveBiosSettings flow."
    $legacySaveReturn = Save-LegacyBiosSettings -SaveClass $saveClass

    if ($legacySaveReturn -eq "Success") {
        $saveSucceeded = $true
        $saveMethodUsed = "LegacySaveBiosSettings"
        Write-Log "Legacy SaveBiosSettings succeeded."
    }
    else {
        Write-Log "Legacy SaveBiosSettings failed with result: $legacySaveReturn"
    }
}

if (-not $saveSucceeded) {
    Write-Log "Both modern and legacy BIOS save methods failed."
    Write-Log "Possible causes:"
    Write-Log "- BIOS Supervisor password required or incorrect"
    Write-Log "- Model requires only one specific Lenovo method"
    Write-Log "- Secure Boot prerequisites are not met in BIOS"
    Write-Log "- Secure Boot cannot be committed through WMI on this model"
    Stop-WithError "Secure Boot staged but BIOS save failed using both modern and legacy methods."
}

Write-Log "BIOS changes committed successfully using method: $saveMethodUsed"

# ------------------------------------------------------------
# Schedule reboot
# ------------------------------------------------------------
try {
    $scheduled = Schedule-RebootAt1AM -TaskName $RebootTaskName
    Write-Log "Reboot successfully scheduled for $($scheduled.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Output "Secure Boot staged successfully using $saveMethodUsed. Reboot scheduled for $($scheduled.ToString('yyyy-MM-dd HH:mm:ss'))"
}
catch {
    Stop-WithError "BIOS change was committed, but failed to schedule reboot. $($_.Exception.Message)"
}

Write-Log "===== REMEDIATION END ====="
exit 0