<#
.SYNOPSIS
  Run ON a gateway VM (Pattern 3, e.g. p3-onprem-gw01 via Bastion). Installs the on-premises data gateway and
  registers it (first node) or joins it (-JoinExisting, subsequent nodes) using the official DataGateway module.
  Registration needs an interactive Microsoft Entra sign-in; there is no unattended option.
#>
param(
    [Parameter(Mandatory)][string]$GatewayName,
    [string]$RegionKey,
    [switch]$JoinExisting
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run in PowerShell 7 (winget install Microsoft.PowerShell).' }
Install-Module -Name DataGateway -Scope AllUsers -Force
Import-Module DataGateway

Install-DataGateway -AcceptConditions
Connect-DataGatewayServiceAccount          # interactive Entra sign-in (tenant admin / gateway admin)
$recovery = Read-Host 'Recovery key (min 8 chars; keep it, needed to add nodes)' -AsSecureString
$gwArgs = @{ RecoveryKey = $recovery; GatewayName = $GatewayName; OverwriteExistingGateway = $true }
if ($RegionKey) { $gwArgs.RegionKey = $RegionKey }
if ($JoinExisting) { Add-DataGatewayClusterMember @gwArgs } else { Add-DataGatewayCluster @gwArgs }
Get-DataGatewayStatus
