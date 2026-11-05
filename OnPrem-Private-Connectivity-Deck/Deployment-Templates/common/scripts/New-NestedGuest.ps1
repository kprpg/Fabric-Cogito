<#
.SYNOPSIS
  Run ON the Hyper-V host (RDP via Bastion Developer or Arc Run Command). Creates a nested guest VM on the
  internal 'vsw-onprem-lan' switch from a VHDX you supply (for example a Windows Server evaluation VHDX).
  The guest needs a static IP in the nested LAN prefix, default gateway = the host's vEthernet address.
  To make the guest reachable from Azure, add a UDR (next hop = host NIC, IP forwarding is already on) -
  see docs/04-simulating-onprem-and-vpn.md.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$VhdxPath,
    [int]$MemoryGB = 4,
    [int]$CpuCount = 2
)
$ErrorActionPreference = 'Stop'
$dest = "F:\Hyper-V\Disks\$Name.vhdx"
Copy-Item -Path $VhdxPath -Destination $dest
New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -VHDPath $dest -SwitchName 'vsw-onprem-lan' | Out-Null
Set-VMProcessor -VMName $Name -Count $CpuCount
Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows'
Start-VM -Name $Name
Get-VM -Name $Name | Format-Table Name, State, CPUUsage, MemoryAssigned
