# Intune-device-dashboard

> Export Intune device dashboard to HTML + CSV + JSON

## About The Project

* Windows, macOS, and Android devices: device name, Intune ID, Entra device ID, serial number, manufacturer, model, OS, OS version, compliance, owner type, enrollment date, and last check-in.
* Storage: total disk space, free disk space, and free storage percentage.
* Primary user: assigned Intune primary user, display name, UPN, email, and user ID.
* User account status: whether the primary user account is enabled, disabled, missing, or unknown in Entra ID.
* OS / UBR status: Windows build, Windows version, UBR level, and whether it meets the configured target.
* Secure Boot: Secure Boot enabled, disabled, unknown, not supported, or not applicable.
* Lenovo Secure Boot remediation: run state, status, and remediation error details from Remediate - Secure boot - Enable secure boot on Lenovo.
* Microsoft Defender: Defender deployment status, protection state, real-time protection, signature status, engine version, and reboot requirement.
* BitLocker: encryption percentage, volume status, protection state, key protectors, encryption method, and last remediation run.
* Device encryption fallback: Intune encryption status when BitLocker remediation data is missing.
* Reboot pending: pending reboot status from Windows Update, CBS, file rename, computer rename, or ConfigMgr indicators.
* Firmware / BIOS: BIOS version, firmware version, release date, BIOS mode, device SKU, system board model, TPM version, and TPM readiness.
* Lenovo Secure Boot 2023 readiness: whether the BIOS version meets Lenovo’s Secure Boot 2023 certificate requirements.
* Dell Secure Boot 2023 readiness: whether the BIOS version meets Dell's minimum BIOS containing the 2023 certificates.
* HP Secure Boot 2023 readiness: whether SMBIOS Type 1 version contains the HP SBKPFV3 marker required for Microsoft certificate rollout.
* Autopilot: Autopilot enrollment status, deployment profile, group tag, assignment status, enrollment state, and last contacted date.
* Device health: stale check-in status, enrollment quality, duplicate device name, duplicate serial number, storage health, and overall risk score.

## Installation

```bash
git clone https://github.com/fdaminato/Intune-device-dashboard
cd Intune-device-dashboard
npm install
```

## Usage

```bash
.\Export-IntuneDashboard.ps1 -MinimumUBR_26100 8037 -MinimumUBR_26200 8037 -MaxBitLockerRunStates 5000 -MaxDefenderDetailQueries 5000 -MaxInventoryRunStates 5000 -MaxSecureBootRunStates 5000 -OpenReport
```

## Screenshots
<img width="1912" height="914" alt="image" src="https://github.com/user-attachments/assets/878eaacf-e87f-4b0e-9b2e-14461672aeae" />


## License

Distributed under the MIT License. See `LICENSE` for more information.
