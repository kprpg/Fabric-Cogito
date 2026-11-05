# Stage 1 - runs once via the Azure Run Command (guest agent still enabled).
# It only stages files, installs Windows roles and schedules Stage 2 to run at boot, because
# Stage 2 disables the Azure guest agent and must not be a child of that agent.
param(
    [Parameter(Mandatory = $true)][string]$ConfigB64
)
$ErrorActionPreference = 'Stop'
$root = 'C:\OnPremSim'
New-Item -ItemType Directory -Path $root -Force | Out-Null

if (Test-Path "$root\stage2.done") { Write-Output 'OnPremSim already completed; nothing to do.'; return }

$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConfigB64))
$cfg = $json | ConvertFrom-Json
Set-Content -Path "$root\config.json" -Value $json -Encoding UTF8
icacls $root /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null

$stage2 = @'
#STAGE2_PLACEHOLDER#
'@
Set-Content -Path "$root\Stage2.ps1" -Value $stage2 -Encoding UTF8

$features = @()
if ($cfg.installHyperV) { $features += 'Hyper-V' }
if ($cfg.dnsZone) { $features += 'DNS' }
if ($features.Count -gt 0) {
    $r = Install-WindowsFeature -Name $features -IncludeManagementTools
    if (-not $r.Success) { throw "Install-WindowsFeature failed: $($r.ExitCode)" }
}

Unregister-ScheduledTask -TaskName 'OnPremSim-Stage2' -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File $root\Stage2.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -StartWhenAvailable
Register-ScheduledTask -TaskName 'OnPremSim-Stage2' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

# Reboot (required for Hyper-V) so Stage 2 runs outside the guest agent's process tree.
shutdown.exe /r /t 60 /c 'OnPremSim: role installation complete, restarting to continue configuration'
Write-Output 'Stage 1 complete. Stage 2 will run at next boot (log: C:\OnPremSim\stage2.log).'
