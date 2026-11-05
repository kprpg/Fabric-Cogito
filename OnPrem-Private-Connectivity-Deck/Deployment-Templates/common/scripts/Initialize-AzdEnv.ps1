<#
.SYNOPSIS
  Seeds the azd environment for a pattern (run from the pattern folder via its azd-init.ps1, then `azd up`).
  azd validates required secure inputs before any hook runs, so secrets must exist in the environment first.
  Re-run it right before `azd up` if more than ~45 minutes have passed (it refreshes the short-lived Arc token).
#>
param(
    [Parameter(Mandatory)][string]$EnvName,
    [string]$Location = 'eastus2'
)
$ErrorActionPreference = 'Stop'

$envList = (azd env list --output json | ConvertFrom-Json)
if (-not ($envList | Where-Object Name -eq $EnvName)) {
    $sub = (az account show --query id -o tsv).Trim()
    azd env new $EnvName --subscription $sub --location $Location --no-prompt | Out-Null
}
else { azd env select $EnvName | Out-Null }

$values = @{}
(azd env get-values) | ForEach-Object {
    if ($_ -match '^([^=]+)="?(.*?)"?$') { $values[$Matches[1]] = $Matches[2] }
}
function Set-Default([string]$Name, [string]$Value) {
    if (-not $values.ContainsKey($Name) -or [string]::IsNullOrEmpty($values[$Name])) {
        azd env set $Name $Value | Out-Null
        $values[$Name] = $Value
    }
}
function New-RandomSecret([int]$Length = 24) {
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '-_=+!@#%^*')
    $chars = foreach ($s in $sets) { $s[(Get-Random -Maximum $s.Length)] }
    $all = ($sets -join '').ToCharArray()
    while ($chars.Count -lt $Length) { $chars += $all[(Get-Random -Maximum $all.Length)] }
    -join ($chars | Sort-Object { Get-Random })
}

Set-Default 'ENV_SUFFIX' 'dev'
Set-Default 'ONPREM_ADMIN_PASSWORD' (New-RandomSecret)
Set-Default 'SQL_PASSWORD' (New-RandomSecret)
Set-Default 'VPN_SHARED_KEY' (New-RandomSecret 32)
Set-Default 'FABRIC_SKU' 'F2'
Set-Default 'RUN_BOOTSTRAP' 'true'

$upn = $null; $oid = ''
try { $upn = (az ad signed-in-user show --query userPrincipalName -o tsv).Trim(); $oid = (az ad signed-in-user show --query id -o tsv).Trim() } catch { }
if ($upn) { Set-Default 'FABRIC_ADMIN_UPN' $upn }
elseif (-not $values.ContainsKey('FABRIC_ADMIN_UPN')) { throw 'Set FABRIC_ADMIN_UPN: azd env set FABRIC_ADMIN_UPN user@contoso.com' }

# Without Owner/UAA the host cannot get an Arc-onboarding role; use the caller's short-lived ARM token instead.
$roles = ''
if ($oid) {
    $roles = (az role assignment list --assignee $oid --include-inherited --include-groups --all `
            --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='User Access Administrator' || roleDefinitionName=='Role Based Access Control Administrator'].roleDefinitionName" -o tsv)
}
if ($roles) {
    azd env set DEPLOYER_OBJECT_ID $oid | Out-Null
    azd env set ARC_ACCESS_TOKEN '' | Out-Null
}
else {
    azd env set DEPLOYER_OBJECT_ID '' | Out-Null
    azd env set ARC_ACCESS_TOKEN ((az account get-access-token --resource https://management.azure.com --query accessToken -o tsv).Trim()) | Out-Null
    Write-Host 'No role-assignment rights detected: using your ARM token for Arc onboarding.' -ForegroundColor Yellow
}
