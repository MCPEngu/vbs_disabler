[CmdletBinding()]
param(
    [ValidateSet("Status", "Disable", "Enforce", "Restore")]
    [string]$Action = "Status",
    [switch]$NoPersistence,
    [switch]$Restart,
    [switch]$Quiet
)

$vbsQuickInvokedFromMemory = [string]::IsNullOrEmpty($PSCommandPath)
if ($vbsQuickInvokedFromMemory) {
    $vbsQuickActionWasBound = $PSBoundParameters.ContainsKey("Action")
    $vbsQuickCallStackFrame = Get-PSCallStack | Select-Object -First 1
    $vbsQuickSource = $null
    if (($null -ne $vbsQuickCallStackFrame) -and ($null -ne $vbsQuickCallStackFrame.Position)) {
        $vbsQuickSource = $vbsQuickCallStackFrame.Position.StartScriptPosition.GetFullScript()
    }

    try {
        & {
            param(
                [string]$SourceText,
                [string]$RequestedAction,
                [bool]$ActionWasBound,
                [bool]$DisablePersistence,
                [bool]$RestartAfterAction,
                [bool]$SuppressOutput
            )

            Set-StrictMode -Version Latest
            $ErrorActionPreference = "Stop"

            function Select-VbsQuickAction {
                Write-Host ""
                Write-Host "VBS (Virtualization-based Security) Disabler"
                Write-Host "1. Check status"
                Write-Host "2. Disable VBS"
                Write-Host "3. Restore original settings"
                Write-Host "Q. Cancel"

                while ($true) {
                    $choice = [string](Read-Host "Select an action [1-3, Q]")
                    switch ($choice.Trim().ToUpperInvariant()) {
                        "1" { return "Status" }
                        "STATUS" { return "Status" }
                        "2" { return "Disable" }
                        "DISABLE" { return "Disable" }
                        "3" { return "Restore" }
                        "RESTORE" { return "Restore" }
                        "Q" { return "Cancel" }
                        "QUIT" { return "Cancel" }
                        default { Write-Warning "Enter 1, 2, 3, or Q." }
                    }
                }
            }

            function Read-VbsQuickBoolean {
                param(
                    [string]$Prompt,
                    [bool]$Default
                )

                $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
                while ($true) {
                    $answer = [string](Read-Host ("{0} {1}" -f $Prompt, $suffix))
                    if ([string]::IsNullOrWhiteSpace($answer)) {
                        return $Default
                    }

                    $normalized = $answer.Trim().ToUpperInvariant()
                    if (($normalized -eq "Y") -or ($normalized -eq "YES")) {
                        return $true
                    }
                    if (($normalized -eq "N") -or ($normalized -eq "NO")) {
                        return $false
                    }

                    Write-Warning "Enter Y or N."
                }
            }

            $quickRunCancelled = $false
            if (-not $ActionWasBound) {
                $RequestedAction = Select-VbsQuickAction
                if ($RequestedAction -eq "Cancel") {
                    $quickRunCancelled = $true
                }
                else {
                    if ($RequestedAction -eq "Disable") {
                        $installPersistence = Read-VbsQuickBoolean -Prompt "Install startup enforcement task?" -Default $true
                        $DisablePersistence = (-not $installPersistence)
                    }
                    if (($RequestedAction -eq "Disable") -or ($RequestedAction -eq "Restore")) {
                        $RestartAfterAction = Read-VbsQuickBoolean -Prompt "Restart Windows automatically after the action?" -Default $false
                    }
                }
            }

            if ($quickRunCancelled) {
                Write-Host "[INFO] No changes were made."
            }
            else {
                if ([string]::IsNullOrWhiteSpace($SourceText)) {
                    throw "Cannot create a temporary script because the in-memory source is unavailable."
                }
                if ($SourceText -match "[^\x00-\x7F]") {
                    throw "The downloaded script contains non-ASCII characters and was not executed."
                }

                $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
                if (-not $tempBase.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
                    $tempBase += [System.IO.Path]::DirectorySeparatorChar
                }
                $tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ("VBSDisabler-{0}" -f [Guid]::NewGuid().ToString("N"))))
                if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to use a temporary path outside the system temporary directory."
                }

                $tempScriptPath = Join-Path $tempRoot "vbs_disabler.ps1"
                $childExitCode = 1
                try {
                    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
                    [System.IO.File]::WriteAllText($tempScriptPath, $SourceText, [System.Text.Encoding]::ASCII)

                    if ($PSVersionTable.PSEdition -eq "Core") {
                        $powerShellExecutable = Join-Path $PSHOME "pwsh.exe"
                    }
                    else {
                        $powerShellExecutable = Join-Path $PSHOME "powershell.exe"
                    }
                    if (-not (Test-Path -LiteralPath $powerShellExecutable)) {
                        throw "PowerShell executable not found at $powerShellExecutable"
                    }

                    $childArguments = @(
                        "-NoProfile"
                        "-ExecutionPolicy"
                        "Bypass"
                        "-File"
                        $tempScriptPath
                        "-Action"
                        $RequestedAction
                    )
                    if ($DisablePersistence) {
                        $childArguments += "-NoPersistence"
                    }
                    if ($RestartAfterAction) {
                        $childArguments += "-Restart"
                    }
                    if ($SuppressOutput) {
                        $childArguments += "-Quiet"
                    }

                    & $powerShellExecutable @childArguments | Out-Host
                    $childExitCode = [int]$LASTEXITCODE
                }
                finally {
                    if ((Test-Path -LiteralPath $tempRoot) -and $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($childExitCode -ne 0) {
                    throw "The temporary script exited with code $childExitCode."
                }
            }
        } `
            -SourceText $vbsQuickSource `
            -RequestedAction $Action `
            -ActionWasBound $vbsQuickActionWasBound `
            -DisablePersistence ([bool]$NoPersistence) `
            -RestartAfterAction ([bool]$Restart) `
            -SuppressOutput ([bool]$Quiet)
    }
    catch {
        Write-Host ("[ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
        throw
    }
    finally {
        Remove-Variable -Name vbsQuickInvokedFromMemory, vbsQuickActionWasBound, vbsQuickCallStackFrame, vbsQuickSource -ErrorAction SilentlyContinue
    }
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ToolName = "VBS (Virtualization-based Security) Disabler"
$script:InstallRoot = Join-Path $env:ProgramData "VBSDisabler"
$script:InstalledScriptPath = Join-Path $script:InstallRoot "vbs_disabler.ps1"
$script:BackupPath = Join-Path $script:InstallRoot "backup.json"
$script:AdditionalBackupPath = Join-Path $script:InstallRoot "backup-extra.json"
$script:BcdBackupPath = Join-Path $script:InstallRoot "bcd-backup.bcd"
$script:LogPath = Join-Path $script:InstallRoot "enforcement.log"
$script:TaskName = "VBS (Virtualization-based Security) Disabler"
$script:PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script:BcdEditPath = Join-Path $env:SystemRoot "System32\bcdedit.exe"

function Write-ToolMessage {
    param(
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level,
        [string]$Message
    )

    $line = "[{0}] {1}" -f $Level, $Message
    if ($Quiet) {
        try {
            if (-not (Test-Path -LiteralPath $script:InstallRoot)) {
                New-Item -ItemType Directory -Path $script:InstallRoot -Force | Out-Null
            }
            if ((Test-Path -LiteralPath $script:LogPath) -and ((Get-Item -LiteralPath $script:LogPath).Length -gt 1048576)) {
                Move-Item -LiteralPath $script:LogPath -Destination ($script:LogPath + ".old") -Force
            }
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -LiteralPath $script:LogPath -Value ("{0} {1}" -f $timestamp, $line) -Encoding ASCII
        }
        catch {
        }
        return
    }

    if ($Level -eq "WARN") {
        Write-Warning $Message
    }
    elseif ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    }
    else {
        Write-Host $line
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-IsAdministrator {
    if (-not (Test-IsAdministrator)) {
        throw "Action '$Action' requires an elevated PowerShell window (Run as administrator)."
    }
}

function Invoke-SelfElevation {
    param([string]$ScriptPath)

    if (Test-IsAdministrator) {
        return $null
    }

    if ([string]::IsNullOrEmpty($ScriptPath)) {
        throw "Cannot request elevation because the current script path is unavailable."
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        $powerShellExecutable = Join-Path $PSHOME "pwsh.exe"
    }
    else {
        $powerShellExecutable = Join-Path $PSHOME "powershell.exe"
    }

    if (-not (Test-Path -LiteralPath $powerShellExecutable)) {
        throw "PowerShell executable not found at $powerShellExecutable"
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action `"$Action`""
    if ($NoPersistence) {
        $arguments += " -NoPersistence"
    }
    if ($Restart) {
        $arguments += " -Restart"
    }
    if ($Quiet) {
        $arguments += " -Quiet"
    }

    if (-not $Quiet) {
        Write-ToolMessage -Level "INFO" -Message "Administrator privileges are required. Requesting elevation through UAC."
    }
    $process = Start-Process -FilePath $powerShellExecutable -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    return [int]$process.ExitCode
}

function Get-RegistrySettings {
    return @(
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "HypervisorEnforcedCodeIntegrity"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "HVCIMATRequired"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "LsaCfgFlags"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "ConfigureSystemGuardLaunch"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "RequirePlatformSecurityFeatures"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Locked"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Mandatory"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Locked"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "HVCIMATRequired"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"; Name = "Enabled"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard"; Name = "Enabled"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\KernelShadowStacks"; Name = "Enabled"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "LsaCfgFlags"; Value = 0 }
    )
}

function Get-AdditionalRegistrySettings {
    return @(
        # Hyper-V/WSL can automatically start VBS unless the host opts out.
        [pscustomobject]@{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "HyperVVirtualizationBasedSecurityOptout"; Value = 1 }
    )
}

function Get-RegistrySnapshot {
    param([object[]]$Settings)

    $snapshot = @()
    foreach ($setting in $Settings) {
        $exists = $false
        $value = $null
        if (Test-Path -LiteralPath $setting.Path) {
            $item = Get-ItemProperty -LiteralPath $setting.Path
            $property = $item.PSObject.Properties[$setting.Name]
            if ($null -ne $property) {
                $exists = $true
                $value = $property.Value
            }
        }

        $snapshot += [pscustomobject]@{
            Path = $setting.Path
            Name = $setting.Name
            Exists = $exists
            Value = $value
        }
    }

    return $snapshot
}

function Set-RegistryDword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-VbsRegistryDisabled {
    foreach ($setting in (Get-RegistrySettings)) {
        Set-RegistryDword -Path $setting.Path -Name $setting.Name -Value $setting.Value
    }
    foreach ($setting in (Get-AdditionalRegistrySettings)) {
        Set-RegistryDword -Path $setting.Path -Name $setting.Name -Value $setting.Value
    }
    Write-ToolMessage -Level "OK" -Message "VBS, Credential Guard, Memory Integrity, Secure Launch, and kernel shadow stack policies are disabled."
}

function Get-BcdValue {
    param([string]$Name)

    $output = & $script:BcdEditPath /enum "{current}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = $output -join " "
        throw "BCDEdit read failed: $message"
    }

    foreach ($line in $output) {
        if ($line -match ("^\s*{0}\s+(\S+)\s*$" -f [regex]::Escape($Name))) {
            return [pscustomobject]@{ Exists = $true; Value = $matches[1] }
        }
    }
    return [pscustomobject]@{ Exists = $false; Value = $null }
}

function Set-BcdValue {
    param(
        [string]$Name,
        [string]$Value
    )

    $output = & $script:BcdEditPath /set "{current}" $Name $Value 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = $output -join " "
        throw "BCDEdit failed while setting $Name`: $message"
    }
}

function Remove-BcdValue {
    param([string]$Name)

    $output = & $script:BcdEditPath /deletevalue "{current}" $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = $output -join " "
        throw "BCDEdit failed while deleting $Name`: $message"
    }
}

function Set-BcdForVbsOffWslOn {
    Set-BcdValue -Name "vsmlaunchtype" -Value "Off"
    Set-BcdValue -Name "hypervisorlaunchtype" -Value "Auto"
    Write-ToolMessage -Level "OK" -Message "VSM launch is Off; Hyper-V hypervisor launch remains Auto."
}

function Show-BitLockerWarning {
    $command = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        Write-ToolMessage -Level "WARN" -Message "BitLocker status could not be checked. Keep the recovery key available before rebooting."
        return
    }

    try {
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
        if ([string]$volume.ProtectionStatus -eq "On") {
            Write-ToolMessage -Level "WARN" -Message "BitLocker is active on $env:SystemDrive. Keep the recovery key available before changing BCD and rebooting."
        }
    }
    catch {
        Write-ToolMessage -Level "WARN" -Message "BitLocker status could not be checked. Keep the recovery key available before rebooting."
    }
}

function Export-BcdStore {
    if (Test-Path -LiteralPath $script:BcdBackupPath) {
        return
    }

    $output = & $script:BcdEditPath /export $script:BcdBackupPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = $output -join " "
        throw "BCDEdit export failed: $message"
    }
    Write-ToolMessage -Level "OK" -Message "Full BCD store exported to $script:BcdBackupPath"
}

function Save-OriginalState {
    if (Test-Path -LiteralPath $script:BackupPath) {
        Write-ToolMessage -Level "INFO" -Message "Existing backup preserved at $script:BackupPath"
        return
    }

    if (-not (Test-Path -LiteralPath $script:InstallRoot)) {
        New-Item -ItemType Directory -Path $script:InstallRoot -Force | Out-Null
    }

    Export-BcdStore

    $settings = Get-RegistrySettings
    $backup = [ordered]@{
        Version = 1
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
        ComputerName = $env:COMPUTERNAME
        Registry = @(Get-RegistrySnapshot -Settings $settings)
        Bcd = [ordered]@{
            Vsmlaunchtype = Get-BcdValue -Name "vsmlaunchtype"
            Hypervisorlaunchtype = Get-BcdValue -Name "hypervisorlaunchtype"
        }
    }

    $backup | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $script:BackupPath -Encoding UTF8
    Write-ToolMessage -Level "OK" -Message "Original state saved to $script:BackupPath"
}

function Save-AdditionalState {
    if (Test-Path -LiteralPath $script:AdditionalBackupPath) {
        Write-ToolMessage -Level "INFO" -Message "Existing additional backup preserved at $script:AdditionalBackupPath"
        return
    }

    if (-not (Test-Path -LiteralPath $script:InstallRoot)) {
        New-Item -ItemType Directory -Path $script:InstallRoot -Force | Out-Null
    }

    $settings = Get-AdditionalRegistrySettings
    $backup = [ordered]@{
        Version = 1
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
        Registry = @(Get-RegistrySnapshot -Settings $settings)
    }

    $backup | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $script:AdditionalBackupPath -Encoding UTF8
    Write-ToolMessage -Level "OK" -Message "Additional VBS state saved to $script:AdditionalBackupPath"
}

function Restore-AdditionalState {
    if (-not (Test-Path -LiteralPath $script:AdditionalBackupPath)) {
        return
    }

    $backup = Get-Content -LiteralPath $script:AdditionalBackupPath -Raw | ConvertFrom-Json
    foreach ($entry in @($backup.Registry)) {
        if ([bool]$entry.Exists) {
            Set-RegistryDword -Path ([string]$entry.Path) -Name ([string]$entry.Name) -Value ([int]$entry.Value)
        }
        elseif (Test-Path -LiteralPath ([string]$entry.Path)) {
            Remove-ItemProperty -LiteralPath ([string]$entry.Path) -Name ([string]$entry.Name) -ErrorAction SilentlyContinue
        }
    }
}

function Restore-OriginalState {
    if (-not (Test-Path -LiteralPath $script:BackupPath)) {
        throw "Backup not found at $script:BackupPath. Restore was not attempted."
    }

    $backup = Get-Content -LiteralPath $script:BackupPath -Raw | ConvertFrom-Json
    foreach ($entry in @($backup.Registry)) {
        if ([bool]$entry.Exists) {
            Set-RegistryDword -Path ([string]$entry.Path) -Name ([string]$entry.Name) -Value ([int]$entry.Value)
        }
        elseif (Test-Path -LiteralPath ([string]$entry.Path)) {
            Remove-ItemProperty -LiteralPath ([string]$entry.Path) -Name ([string]$entry.Name) -ErrorAction SilentlyContinue
        }
    }

    foreach ($bcdName in @("Vsmlaunchtype", "Hypervisorlaunchtype")) {
        $entry = $backup.Bcd.$bcdName
        $actualName = $bcdName.ToLowerInvariant()
        if ([bool]$entry.Exists) {
            Set-BcdValue -Name $actualName -Value ([string]$entry.Value)
        }
        else {
            $current = Get-BcdValue -Name $actualName
            if ($current.Exists) {
                Remove-BcdValue -Name $actualName
            }
        }
    }

    Restore-AdditionalState

    Write-ToolMessage -Level "OK" -Message "Registry and BCD values were restored from backup."
}

function Get-WindowsFeatureState {
    param([string]$FeatureName)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName
        return [string]$feature.State
    }
    catch {
        return "Unavailable"
    }
}

function Report-WslFeatureStates {
    foreach ($featureName in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        $state = Get-WindowsFeatureState -FeatureName $featureName
        if ($state -eq "Enabled") {
            Write-ToolMessage -Level "OK" -Message "Windows feature remains enabled: $featureName"
        }
        else {
            Write-ToolMessage -Level "WARN" -Message "Windows feature is $state and was left unchanged: $featureName"
        }
    }
}

function Install-PersistenceTask {
    if (-not $PSCommandPath) {
        throw "Cannot install persistence because the current script path is unavailable."
    }

    if (-not (Test-Path -LiteralPath $script:InstallRoot)) {
        New-Item -ItemType Directory -Path $script:InstallRoot -Force | Out-Null
    }

    $sourcePath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $destinationPath = [System.IO.Path]::GetFullPath($script:InstalledScriptPath)
    if ($sourcePath -ne $destinationPath) {
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$destinationPath`" -Action Enforce -Quiet"
    $taskAction = New-ScheduledTaskAction -Execute $script:PowerShellPath -Argument $arguments
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $script:TaskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Keeps VBS/VSM disabled while leaving the Windows hypervisor enabled for WSL2." -Force | Out-Null
    Write-ToolMessage -Level "OK" -Message "Startup enforcement task installed: $script:TaskName"
}

function Remove-PersistenceTask {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
        Write-ToolMessage -Level "OK" -Message "Startup enforcement task removed."
    }
}

function Convert-VbsStatus {
    param([int]$Value)

    switch ($Value) {
        0 { return "Not enabled" }
        1 { return "Enabled but not running" }
        2 { return "Enabled and running" }
        default { return "Unknown ($Value)" }
    }
}

function Get-ObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Convert-SecurityProperties {
    param(
        [object]$Values,
        [string]$ZeroLabel
    )

    if ($null -eq $Values) {
        return "Unavailable"
    }

    $names = @{
        0 = $ZeroLabel
        1 = "Hypervisor support"
        2 = "Secure Boot"
        3 = "DMA protection"
        4 = "Secure Memory Overwrite"
        5 = "NX protections"
        6 = "SMM mitigations"
        7 = "MBEC/GMET"
        8 = "APIC virtualization"
    }

    $result = @()
    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        $number = [int]$value
        if ($names.ContainsKey($number)) {
            $result += $names[$number]
        }
        else {
            $result += "Unknown ($number)"
        }
    }

    if ($result.Count -eq 0) {
        return "None reported"
    }
    return ($result -join ", ")
}

function Convert-CodeIntegrityStatus {
    param([object]$Value)

    if ($null -eq $Value) {
        return "Unavailable"
    }

    $number = [int]$Value
    switch ($number) {
        0 { return "Off" }
        1 { return "Audit" }
        2 { return "Enforced" }
        default { return "Unknown ($number)" }
    }
}

function Convert-SecurityServices {
    param([object]$Values)

    $names = @{
        0 = "None"
        1 = "Credential Guard"
        2 = "Memory Integrity"
        3 = "System Guard Secure Launch"
        4 = "SMM Firmware Measurement"
        5 = "Kernel-mode Hardware-enforced Stack Protection"
        6 = "Kernel-mode Hardware-enforced Stack Protection (Audit)"
        7 = "Hypervisor-Enforced Paging Translation"
    }

    $result = @()
    foreach ($value in @($Values)) {
        $number = [int]$value
        if ($names.ContainsKey($number)) {
            $result += $names[$number]
        }
        else {
            $result += "Unknown ($number)"
        }
    }

    if ($result.Count -eq 0) {
        return "None reported"
    }
    return ($result -join ", ")
}

function Get-PolicyWarnings {
    $warnings = @()
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    if ($computerSystem.PartOfDomain) {
        $warnings += "This PC is domain-joined; domain policy can re-enable VBS after local changes."
    }

    $mdmPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceGuard"
    if (Test-Path -LiteralPath $mdmPath) {
        $item = Get-ItemProperty -LiteralPath $mdmPath
        foreach ($name in @("EnableVirtualizationBasedSecurity", "LsaCfgFlags", "HypervisorEnforcedCodeIntegrity", "ConfigureSystemGuardLaunch")) {
            $property = $item.PSObject.Properties[$name]
            if (($null -ne $property) -and ([int]$property.Value -ne 0)) {
                $warnings += "MDM policy $name is nonzero and may re-enable VBS."
            }
        }
    }

    $deviceGuardPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    if (Test-Path -LiteralPath $deviceGuardPath) {
        $deviceGuard = Get-ItemProperty -LiteralPath $deviceGuardPath
        $optOutProperty = $deviceGuard.PSObject.Properties["HyperVVirtualizationBasedSecurityOptout"]
        if (($null -eq $optOutProperty) -or ([int]$optOutProperty.Value -ne 1)) {
            $warnings += "Hyper-V can automatically start VBS; HyperVVirtualizationBasedSecurityOptout is not 1."
        }
    }

    $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    if (Test-Path -LiteralPath $lsaPath) {
        $lsa = Get-ItemProperty -LiteralPath $lsaPath
        $runAsPplProperty = $lsa.PSObject.Properties["RunAsPPL"]
        if (($null -ne $runAsPplProperty) -and ([int]$runAsPplProperty.Value -ne 0)) {
            $warnings += "LSA protection is enabled (RunAsPPL=$($runAsPplProperty.Value)); Windows Hello Enhanced Sign-in Security or Key Guard may require VBS."
        }
    }

    $uefiLockIndicators = @(
        [pscustomobject]@{ Feature = "VBS"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "Locked"; LockedValue = 1 }
        [pscustomobject]@{ Feature = "Memory Integrity"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Locked"; LockedValue = 1 }
        [pscustomobject]@{ Feature = "Credential Guard"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "LsaCfgFlags"; LockedValue = 1 }
        [pscustomobject]@{ Feature = "Credential Guard policy"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "LsaCfgFlags"; LockedValue = 1 }
        [pscustomobject]@{ Feature = "Memory Integrity policy"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Name = "HypervisorEnforcedCodeIntegrity"; LockedValue = 1 }
    )
    $detectedLocks = @()
    foreach ($indicator in $uefiLockIndicators) {
        if (-not (Test-Path -LiteralPath $indicator.Path)) {
            continue
        }

        $item = Get-ItemProperty -LiteralPath $indicator.Path
        $property = $item.PSObject.Properties[$indicator.Name]
        if (($null -ne $property) -and ([int]$property.Value -eq [int]$indicator.LockedValue)) {
            $detectedLocks += $indicator.Feature
        }
    }
    if ($detectedLocks.Count -gt 0) {
        $warnings += "UEFI-lock indicators detected for: $($detectedLocks -join ', '). EFI variable removal requires physical presence and is intentionally not automated."
    }

    return $warnings
}

function Show-Status {
    $deviceGuard = Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName "Win32_DeviceGuard"
    $computerInfo = Get-ComputerInfo -Property HyperVisorPresent
    $vbsStatus = Convert-VbsStatus -Value ([int]$deviceGuard.VirtualizationBasedSecurityStatus)
    $configuredValues = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "SecurityServicesConfigured"
    $runningValues = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "SecurityServicesRunning"
    $availableValues = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "AvailableSecurityProperties"
    $requiredValues = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "RequiredSecurityProperties"
    $kernelCiValue = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "CodeIntegrityPolicyEnforcementStatus"
    $userCiValue = Get-ObjectPropertyValue -InputObject $deviceGuard -Name "UsermodeCodeIntegrityPolicyEnforcementStatus"
    $configured = Convert-SecurityServices -Values $configuredValues
    $running = Convert-SecurityServices -Values $runningValues
    $available = Convert-SecurityProperties -Values $availableValues -ZeroLabel "No relevant properties"
    $required = Convert-SecurityProperties -Values $requiredValues -ZeroLabel "Nothing required"
    $kernelCi = Convert-CodeIntegrityStatus -Value $kernelCiValue
    $userCi = Convert-CodeIntegrityStatus -Value $userCiValue

    Write-Host ""
    Write-Host $script:ToolName
    Write-Host ("VBS status                  : {0}" -f $vbsStatus)
    Write-Host ("Security services configured: {0}" -f $configured)
    Write-Host ("Security services running   : {0}" -f $running)
    Write-Host ("Available security properties: {0}" -f $available)
    Write-Host ("Required security properties : {0}" -f $required)
    Write-Host ("Kernel CI policy             : {0}" -f $kernelCi)
    Write-Host ("User-mode CI policy          : {0}" -f $userCi)
    Write-Host ("Windows hypervisor present  : {0}" -f $computerInfo.HyperVisorPresent)
    Write-Host ("WSL feature                 : {0}" -f (Get-WindowsFeatureState -FeatureName "Microsoft-Windows-Subsystem-Linux"))
    Write-Host ("VirtualMachinePlatform      : {0}" -f (Get-WindowsFeatureState -FeatureName "VirtualMachinePlatform"))

    $deviceGuardPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    $optOutValue = "Not set"
    if (Test-Path -LiteralPath $deviceGuardPath) {
        $deviceGuardSettings = Get-ItemProperty -LiteralPath $deviceGuardPath
        $optOutProperty = $deviceGuardSettings.PSObject.Properties["HyperVVirtualizationBasedSecurityOptout"]
        if ($null -ne $optOutProperty) {
            $optOutValue = [string]$optOutProperty.Value
        }
    }
    Write-Host ("Hyper-V VBS opt-out         : {0}" -f $optOutValue)

    if (Test-IsAdministrator) {
        $vsmLaunch = Get-BcdValue -Name "vsmlaunchtype"
        $hypervisorLaunch = Get-BcdValue -Name "hypervisorlaunchtype"
        $vsmValue = if ($vsmLaunch.Exists) { $vsmLaunch.Value } else { "Default/Auto" }
        $hypervisorValue = if ($hypervisorLaunch.Exists) { $hypervisorLaunch.Value } else { "Default/Auto" }
        Write-Host ("BCD vsmlaunchtype           : {0}" -f $vsmValue)
        Write-Host ("BCD hypervisorlaunchtype    : {0}" -f $hypervisorValue)
    }
    else {
        Write-Host "BCD settings                : Run Status as administrator to read"
    }

    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    $taskState = if ($null -ne $task) { [string]$task.State } else { "Not installed" }
    Write-Host ("Persistence task            : {0}" -f $taskState)

    foreach ($warning in (Get-PolicyWarnings)) {
        Write-ToolMessage -Level "WARN" -Message $warning
    }

    if (@($configuredValues) -contains 1) {
        Write-ToolMessage -Level "WARN" -Message "Credential Guard remains configured. After Disable and reboot, check Domain/MDM policy or a UEFI lock if this value is still present."
    }

    if ([int]$deviceGuard.VirtualizationBasedSecurityStatus -eq 0) {
        Write-ToolMessage -Level "OK" -Message "VBS is not enabled. Re-check WSL with 'wsl --status' and 'wsl -l -v'."
    }
    else {
        Write-ToolMessage -Level "INFO" -Message "A reboot is required after Disable. If Credential Guard remains configured, a UEFI-lock removal may also be required."
    }
}

function Disable-Vbs {
    param([bool]$InstallPersistence)

    Assert-IsAdministrator
    Show-BitLockerWarning
    Save-OriginalState
    Save-AdditionalState
    Set-VbsRegistryDisabled
    Set-BcdForVbsOffWslOn
    Report-WslFeatureStates
    if ($InstallPersistence) {
        Install-PersistenceTask
    }

    Write-ToolMessage -Level "WARN" -Message "This reduces Windows credential and kernel protections."
    Write-ToolMessage -Level "OK" -Message "Changes applied. Reboot, then run: .\vbs_disabler.ps1 -Action Status"
}

try {
    $elevationExitCode = Invoke-SelfElevation -ScriptPath $PSCommandPath
    if ($null -ne $elevationExitCode) {
        exit $elevationExitCode
    }

    switch ($Action) {
        "Status" {
            Show-Status
        }
        "Disable" {
            Disable-Vbs -InstallPersistence (-not $NoPersistence)
        }
        "Enforce" {
            Assert-IsAdministrator
            Save-AdditionalState
            Set-VbsRegistryDisabled
            Set-BcdForVbsOffWslOn
        }
        "Restore" {
            Assert-IsAdministrator
            Remove-PersistenceTask
            Restore-OriginalState
            Write-ToolMessage -Level "OK" -Message "Restore completed. A reboot is required."
        }
    }

    if ($Restart) {
        Assert-IsAdministrator
        Write-ToolMessage -Level "INFO" -Message "Restarting Windows now."
        Restart-Computer -Force
    }
}
catch {
    Write-ToolMessage -Level "ERROR" -Message $_.Exception.Message
    exit 1
}
