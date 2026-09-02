# Disabling Virtualization-based Security (VBS) on Windows

The `vbs_disabler.ps1` script disables Virtualization-based Security (VBS), Credential Guard, Memory Integrity, and Secure Launch, while **keeping the Windows hypervisor enabled**.

This script handles both layers:

1. Set policy and runtime registry values to `0`.
2. Set `HyperVVirtualizationBasedSecurityOptout=1` so Hyper-V, WSL2 does not automatically re-enable VBS.
3. Set `vsmlaunchtype Off` so Virtual Secure Mode (VSM) does not start.
4. Keep `hypervisorlaunchtype Auto` so Hyper-V, WSL2 continues to run.
5. Report the state of `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` without enabling or disabling them.
6. Create a Scheduled Task that runs as `SYSTEM` at startup to restore these settings if Windows Security or a local process changes them.


## How to Run
Open PowerShell then run

```powershell
irm https://raw.githubusercontent.com/MCPEngu/vbs_disabler/main/vbs_disabler.ps1 | iex
```

The  menu provides `Status`, `Disable`, `Restore`, and `Cancel`:

- `Status` checks the current configuration without changing it. The script still requests elevation so it can read the full BCD configuration.
- `Disable` creates the persistence Scheduled Task by default. The menu lets you disable persistence and choose whether to restart immediately.
- `Restore` removes the Scheduled Task, restores the first snapshot stored in `C:\ProgramData\VBSDisabler`, and requires a restart.
- `Cancel` exits without making changes.

## Disclaimer

Use this script at your own risk. I am not responsible for bricked devices, data loss, system instability, or any other damage resulting from its use.

## Security Notes

Disabling VBS reduces protection for credentials and kernel integrity. The script does not disable Secure Boot, TPM, Windows Defender or the Windows hypervisor. If BitLocker is enabled, make sure you have the recovery key before rebooting; the script only warns and does not automatically suspend BitLocker.

## Documentations

- <https://learn.microsoft.com/windows/security/identity-protection/credential-guard/configure>
- <https://learn.microsoft.com/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity>
- <https://learn.microsoft.com/windows-hardware/design/device-experiences/windows-hello-enhanced-sign-in-security>
- <https://learn.microsoft.com/windows-hardware/drivers/devtest/bcdedit--set>
