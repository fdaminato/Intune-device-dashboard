<#
.SYNOPSIS
    Intune remediation detection inventory for reboot pending state.

.REMEDIATION NAME
    Monitoring - Detection - RebootPending - Get status

.OUTPUT EXAMPLE
    RebootPending=True | CBSRebootPending=False | WindowsUpdateRebootRequired=True | PendingFileRename=False | ComputerRenamePending=False | CCMRebootPending=False
#>

$ErrorActionPreference = "SilentlyContinue"

function Test-RegPath {
    param([string]$Path)
    return Test-Path -Path $Path
}

function Get-RegValueExists {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $Value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

$CBSRebootPending = Test-RegPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
$WindowsUpdateRebootRequired = Test-RegPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$PendingFileRename = Get-RegValueExists -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations"
$ComputerRenamePending = $false
$CCMRebootPending = $false

try {
    $ActiveName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName").ComputerName
    $PendingName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName").ComputerName

    if ($ActiveName -and $PendingName -and $ActiveName -ne $PendingName) {
        $ComputerRenamePending = $true
    }
}
catch {
}

try {
    $CCM = Invoke-WmiMethod -Namespace "root\ccm\ClientSDK" -Class "CCM_ClientUtilities" -Name "DetermineIfRebootPending" -ErrorAction Stop

    if ($CCM -and ($CCM.RebootPending -eq $true -or $CCM.IsHardRebootPending -eq $true)) {
        $CCMRebootPending = $true
    }
}
catch {
}

$RebootPending = $CBSRebootPending -or $WindowsUpdateRebootRequired -or $PendingFileRename -or $ComputerRenamePending -or $CCMRebootPending

Write-Output ("RebootPending={0} | CBSRebootPending={1} | WindowsUpdateRebootRequired={2} | PendingFileRename={3} | ComputerRenamePending={4} | CCMRebootPending={5}" -f `
    $RebootPending,
    $CBSRebootPending,
    $WindowsUpdateRebootRequired,
    $PendingFileRename,
    $ComputerRenamePending,
    $CCMRebootPending
)

exit 0
