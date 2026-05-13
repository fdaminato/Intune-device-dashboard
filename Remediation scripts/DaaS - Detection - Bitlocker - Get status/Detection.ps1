#Requires -Version 5.1

$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogPath = Join-Path $LogDir 'BitLockerStatus_Detection.log'

function Write-Log {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        $TimeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $LogPath -Value "[$TimeStamp] $Message"
    } catch {}
}

try {
    $MountPoint = 'C:'
    $BLV = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

    $ProtectionStatus = $BLV.ProtectionStatus
    $VolumeStatus     = $BLV.VolumeStatus
    $EncryptionPct    = [int]$BLV.EncryptionPercentage
    $KeyProtectors    = ($BLV.KeyProtector | Select-Object -ExpandProperty KeyProtectorType -ErrorAction SilentlyContinue) -join ', '

    $ProtectionText = switch ($ProtectionStatus) {
        0 { 'Off' }
        1 { 'On' }
        default { "Unknown ($ProtectionStatus)" }
    }

    $Result = "Drive=$MountPoint | Protection=$ProtectionText | VolumeStatus=$VolumeStatus | EncryptionPercentage=$EncryptionPct | KeyProtectors=$KeyProtectors"
    Write-Output $Result
    Write-Log $Result

    # Compliance rule:
    # - Protection must be ON
    # - Encryption percentage must be 100
    if (($ProtectionStatus -eq 1) -and ($EncryptionPct -eq 100)) {
        Write-Log "Compliant"
        exit 0
    }
    else {
        Write-Log "Non-compliant"
        exit 1
    }
}
catch {
    $ErrorMessage = "Detection error: $($_.Exception.Message)"
    Write-Output $ErrorMessage
    Write-Log $ErrorMessage
    exit 1
}