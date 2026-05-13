<#
.SYNOPSIS
    Intune remediation detection inventory for BIOS / firmware / TPM state.

.REMEDIATION NAME
    DaaS - Detection - Firmware - Get status

.OUTPUT EXAMPLE
    FirmwareManufacturer=LENOVO | FirmwareVersion=R1MET63W (1.33) | FirmwareReleaseDate=2025-11-18 | BiosMode=UEFI | DeviceSKU=20XLS1R900 | SystemBoardModel=20XLS1R900 | TPMVersion=2.0 | TpmReady=True
#>

$ErrorActionPreference = "SilentlyContinue"

function Normalize-Value {
    param($Value)

    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Convert-WmiDate {
    param($WmiDate)

    if ([string]::IsNullOrWhiteSpace($WmiDate)) { return "" }

    try {
        return ([System.Management.ManagementDateTimeConverter]::ToDateTime($WmiDate)).ToString("yyyy-MM-dd")
    }
    catch {
        return ""
    }
}

function Get-BiosMode {
    try {
        $FirmwareType = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction Stop).PEFirmwareType

        switch ($FirmwareType) {
            1 { return "BIOS" }
            2 { return "UEFI" }
            default { return "Unknown" }
        }
    }
    catch {
        return "Unknown"
    }
}

$Bios = Get-CimInstance -ClassName Win32_BIOS
$ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$ComputerSystemProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct
$BaseBoard = Get-CimInstance -ClassName Win32_BaseBoard

$FirmwareManufacturer = Normalize-Value $Bios.Manufacturer
$FirmwareVersion = Normalize-Value $Bios.SMBIOSBIOSVersion

if ([string]::IsNullOrWhiteSpace($FirmwareVersion)) {
    $FirmwareVersion = Normalize-Value (($Bios.BIOSVersion | Select-Object -First 1))
}

$FirmwareReleaseDate = Convert-WmiDate $Bios.ReleaseDate
$BiosMode = Get-BiosMode
$DeviceSKU = Normalize-Value $ComputerSystemProduct.SKUNumber
$SystemBoardModel = Normalize-Value $BaseBoard.Product
$TPMVersion = ""
$TpmReady = ""

try {
    $Tpm = Get-Tpm -ErrorAction Stop
    $TpmReady = Normalize-Value $Tpm.TpmReady

    if ($Tpm.SpecVersion) {
        $TPMVersion = Normalize-Value $Tpm.SpecVersion
    }
    elseif ($Tpm.ManufacturerVersionFull20) {
        $TPMVersion = Normalize-Value $Tpm.ManufacturerVersionFull20
    }
}
catch {
}

Write-Output ("FirmwareManufacturer={0} | FirmwareVersion={1} | FirmwareReleaseDate={2} | BiosVersion={1} | BiosReleaseDate={2} | BiosMode={3} | DeviceManufacturer={4} | DeviceModel={5} | DeviceSKU={6} | SystemBoardManufacturer={7} | SystemBoardModel={8} | TPMVersion={9} | TpmReady={10}" -f `
    $FirmwareManufacturer,
    $FirmwareVersion,
    $FirmwareReleaseDate,
    $BiosMode,
    (Normalize-Value $ComputerSystem.Manufacturer),
    (Normalize-Value $ComputerSystem.Model),
    $DeviceSKU,
    (Normalize-Value $BaseBoard.Manufacturer),
    $SystemBoardModel,
    $TPMVersion,
    $TpmReady
)

exit 0
