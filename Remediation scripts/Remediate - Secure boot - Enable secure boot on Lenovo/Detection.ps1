#Requires -Version 5.1
<#
.SYNOPSIS
    Intune Proactive Remediation detection script for Lenovo Secure Boot.

.DESCRIPTION
    Detects whether Secure Boot is enabled on supported Lenovo Windows devices.
    Exit codes:
      0 = compliant or not applicable
      1 = remediation required

.NOTES
    - Safe for Intune Proactive Remediations.
    - Non-Lenovo devices return 0 (not applicable) so they don't remediate.
    - Legacy BIOS / unsupported firmware return 0 (not applicable) by default.
#>

$LogDir  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$LogPath = Join-Path $LogDir 'SecureBoot_Lenovo_Detect.log'

function Write-Log {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $LogPath -Value ("{0} - {1}" -f $timestamp, $Message) -Encoding UTF8
    }
    catch {}
}

function Exit-WithResult {
    param(
        [int]$Code,
        [string]$Message
    )
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

Write-Log '===== DETECTION START ====='

try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $manufacturer = [string]$cs.Manufacturer
    $model = [string]$cs.Model
    Write-Log ("Manufacturer='{0}', Model='{1}', BIOS='{2}'" -f $manufacturer, $model, $bios.SMBIOSBIOSVersion)

    if ($manufacturer -notmatch 'Lenovo') {
        Exit-WithResult 0 "NOT APPLICABLE - Device manufacturer is not Lenovo."
    }

    try {
        $secureBootState = Confirm-SecureBootUEFI -ErrorAction Stop
    }
    catch {
        Exit-WithResult 0 'NOT APPLICABLE - Device is not booted in UEFI mode or firmware does not expose Secure Boot state.'
    }

    if ($secureBootState -eq $true) {
        Exit-WithResult 0 'COMPLIANT - Secure Boot is already enabled.'
    }
    else {
        Exit-WithResult 1 'NON-COMPLIANT - Secure Boot is disabled and remediation is required.'
    }
}
catch {
    $err = $_.Exception.Message
    Exit-WithResult 1 ("ERROR - Detection failed: {0}" -f $err)
}
finally {
    Write-Log '===== DETECTION END ====='
}
