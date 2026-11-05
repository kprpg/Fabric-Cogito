<#
.SYNOPSIS
  Deploy, validate, pause/resume or destroy one of the four private-connectivity patterns with Azure CLI + Bicep.

.EXAMPLE
  ./Deploy-Pattern.ps1 -Pattern 2                      # deploy pattern 2 to eastus2 (dev)
  ./Deploy-Pattern.ps1 -Pattern 1 -Action WhatIf       # preview
  ./Deploy-Pattern.ps1 -Pattern 4 -ConfigureFabric     # deploy, then create workspace + managed private endpoint
  ./Deploy-Pattern.ps1 -Pattern 1 -HybridLinkMode expressRoute -ExpressRouteCircuitId <id> -ExpressRouteAuthorizationKey <key>
  ./Deploy-Pattern.ps1 -Pattern 3 -Action Pause        # stop spend (VMs deallocated, Fabric capacity suspended)
  ./Deploy-Pattern.ps1 -Pattern 3 -Action Destroy -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(1, 2, 3, 4)][int]$Pattern,
    [ValidateSet('Deploy', 'Validate', 'WhatIf', 'Pause', 'Resume', 'Destroy')][string]$Action = 'Deploy',
    [string]$Location = 'eastus2',
    [string]$Environment = 'dev',
    [string]$Workload = 'fabcn',
    [string]$SubscriptionId,
    [ValidateSet('simulatedVpn', 'expressRoute')][string]$HybridLinkMode = 'simulatedVpn',
    [string]$ExpressRouteCircuitId = '',
    [string]$ExpressRouteAuthorizationKey = '',
    [string[]]$FabricAdminUpns,
    [string]$FabricSku = 'F2',
    [string]$HostVmSize = 'Standard_D4s_v5',
    [SecureString]$AdminPassword,
    [SecureString]$SqlPassword,
    [SecureString]$VpnSharedKey,
    [switch]$NoBastion,
    [switch]$NoArc,
    [switch]$AssumeRoleAdmin,
    [switch]$NoTestVm,
    [switch]$NoDnsResolver,
    [switch]$ForceBootstrap,
    [switch]$ConfigureFabric,
    [switch]$PurgeKeyVault,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$patterns = @{
    1 = @{ Dir = 'pattern1-vnetgw-expressroute'; Tag = 'p1-vnetgw-expressroute' }
    2 = @{ Dir = 'pattern2-vnetgw-s2s-vpn'; Tag = 'p2-vnetgw-s2s-vpn' }
    3 = @{ Dir = 'pattern3-onprem-gateway'; Tag = 'p3-onprem-gateway' }
    4 = @{ Dir = 'pattern4-mpe-pls'; Tag = 'p4-mpe-pls' }
}
$p = $patterns[$Pattern]
$template = Join-Path $PSScriptRoot "$($p.Dir)\infra\main.bicep"

function Invoke-Az {
    $out = & az @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed:`n$out" }
    $out
}
function ConvertTo-Plain([SecureString]$s) { [System.Net.NetworkCredential]::new('', $s).Password }
function New-RandomSecret([int]$Length = 24) {
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '-_=+!@#%^*')
    $chars = foreach ($s in $sets) { $s[(Get-Random -Maximum $s.Length)] }
    $all = ($sets -join '').ToCharArray()
    while ($chars.Count -lt $Length) { $chars += $all[(Get-Random -Maximum $all.Length)] }
    -join ($chars | Sort-Object { Get-Random })
}
function Get-PatternResourceGroups {
    (Invoke-Az group list --query "[?tags.pattern=='$($p.Tag)' && tags.environment=='$Environment' && tags.workload=='$Workload'].name" -o tsv) -split "`r?`n" | Where-Object { $_ }
}

# ---- Subscription context ----
$null = Invoke-Az account show
if ($SubscriptionId) { $null = Invoke-Az account set --subscription $SubscriptionId }
$sub = (Invoke-Az account show --query id -o tsv).Trim()
Write-Host "Subscription: $sub | Pattern $Pattern ($($p.Tag)) | $Location | $Environment" -ForegroundColor Cyan

# ---- Lifecycle actions that don't need the template ----
if ($Action -in 'Pause', 'Resume', 'Destroy') {
    $rgs = @(Get-PatternResourceGroups)
    if ($rgs.Count -eq 0) { Write-Warning 'No resource groups found for this pattern/environment.'; return }
    switch ($Action) {
        'Pause' {
            foreach ($rg in $rgs) {
                foreach ($id in (Invoke-Az resource list -g $rg --resource-type Microsoft.Fabric/capacities --query '[].id' -o tsv) -split "`r?`n" | Where-Object { $_ }) {
                    Write-Host "Suspending Fabric capacity $id"; $null = Invoke-Az rest --method post --url "https://management.azure.com$id/suspend?api-version=2023-11-01"
                }
                $vms = @((Invoke-Az vm list -g $rg --query '[].id' -o tsv) -split "`r?`n" | Where-Object { $_ })
                if ($vms.Count) { Write-Host "Deallocating VMs in $rg"; $null = Invoke-Az vm deallocate --ids @vms --no-wait }
            }
            Write-Host 'Note: VPN/ER gateways and NAT gateways bill while idle; use -Action Destroy to stop them.' -ForegroundColor Yellow
        }
        'Resume' {
            foreach ($rg in $rgs) {
                foreach ($id in (Invoke-Az resource list -g $rg --resource-type Microsoft.Fabric/capacities --query '[].id' -o tsv) -split "`r?`n" | Where-Object { $_ }) {
                    Write-Host "Resuming Fabric capacity $id"; $null = Invoke-Az rest --method post --url "https://management.azure.com$id/resume?api-version=2023-11-01"
                }
                $vms = @((Invoke-Az vm list -g $rg --query '[].id' -o tsv) -split "`r?`n" | Where-Object { $_ })
                if ($vms.Count) { Write-Host "Starting VMs in $rg"; $null = Invoke-Az vm start --ids @vms --no-wait }
            }
        }
        'Destroy' {
            Write-Host "Resource groups to delete:`n  $($rgs -join "`n  ")" -ForegroundColor Yellow
            if (-not $Force -and (Read-Host 'Type DELETE to confirm') -ne 'DELETE') { Write-Host 'Aborted.'; return }
            $kvs = @()
            foreach ($rg in $rgs) {
                if ($PurgeKeyVault) { $kvs += (Invoke-Az keyvault list -g $rg --query '[].name' -o tsv) -split "`r?`n" | Where-Object { $_ } }
                $null = Invoke-Az group delete --name $rg --yes --no-wait
            }
            Write-Host 'Deletion started (gateways take 20-40 minutes).'
            if ($PurgeKeyVault -and $kvs) {
                foreach ($rg in $rgs) { & az group wait --name $rg --deleted 2>$null }
                foreach ($kv in $kvs) { Write-Host "Purging soft-deleted Key Vault $kv"; & az keyvault purge --name $kv --location $Location -o none }
            }
        }
    }
    return
}

# ---- Resource providers ----
$providers = 'Microsoft.Network', 'Microsoft.Compute', 'Microsoft.Storage', 'Microsoft.KeyVault', 'Microsoft.OperationalInsights',
'Microsoft.Insights', 'Microsoft.Fabric', 'Microsoft.PowerPlatform', 'Microsoft.HybridCompute', 'Microsoft.GuestConfiguration',
'Microsoft.HybridConnectivity', 'Microsoft.DevTestLab', 'Microsoft.Authorization'
foreach ($ns in $providers) {
    $state = (Invoke-Az provider show --namespace $ns --query registrationState -o tsv).Trim()
    if ($state -ne 'Registered') { Write-Host "Registering $ns ..."; $null = Invoke-Az provider register --namespace $ns --wait }
}

# ---- Existing deployment? reuse secrets and skip the one-shot host bootstrap ----
$rgs = @(Get-PatternResourceGroups)
$existingKv = $null; $govRg = $rgs | Where-Object { $_ -like '*-gov-*' } | Select-Object -First 1
if ($govRg) { $existingKv = (Invoke-Az keyvault list -g $govRg --query '[0].name' -o tsv).Trim() }
$onpremRg = $rgs | Where-Object { $_ -like '*-onprem-*' } | Select-Object -First 1
$runBootstrap = $true
if ($onpremRg -and -not $ForceBootstrap) {
    $vmCount = @((Invoke-Az vm list -g $onpremRg --query '[].name' -o tsv) -split "`r?`n" | Where-Object { $_ }).Count
    if ($vmCount -gt 0) { $runBootstrap = $false; Write-Host 'Existing on-prem VMs found: skipping first-boot bootstrap (use -ForceBootstrap to override).' -ForegroundColor Yellow }
}
function Get-KvSecret([string]$name) {
    if ($existingKv) { try { return (Invoke-Az keyvault secret show --vault-name $existingKv --name $name --query value -o tsv).Trim() } catch { } }
    $null
}
# Fallback cache (gitignored) for environments where the vault is not reachable from this machine (private/policy-restricted vaults).
$secretFile = Join-Path $PSScriptRoot ".secrets\p$Pattern-$Environment.json"
$cache = if (Test-Path $secretFile) { Get-Content $secretFile -Raw | ConvertFrom-Json } else { $null }
function Get-CachedSecret([string]$name) { if ($cache -and $cache.$name) { [string]$cache.$name } else { $null } }
$admin = if ($AdminPassword) { ConvertTo-Plain $AdminPassword } else { (Get-KvSecret 'vm-admin-password') ?? (Get-CachedSecret 'adminPassword') }
$sql = if ($SqlPassword) { ConvertTo-Plain $SqlPassword } else { (Get-KvSecret 'sql-fabricsvc-password') ?? (Get-CachedSecret 'sqlPassword') }
$psk = if ($VpnSharedKey) { ConvertTo-Plain $VpnSharedKey } else { (Get-KvSecret 'vpn-shared-key') ?? (Get-CachedSecret 'vpnSharedKey') }
if ($existingKv -and -not ($admin -and $sql)) { throw "Existing deployment found but its secrets are unavailable (vault unreachable and no local cache at $secretFile). Pass -AdminPassword/-SqlPassword/-VpnSharedKey explicitly." }
if (-not $admin) { $admin = New-RandomSecret }
if (-not $sql) { $sql = New-RandomSecret }
if (-not $psk) { $psk = New-RandomSecret 32 }
if ($Action -eq 'Deploy') {
    New-Item -ItemType Directory -Path (Split-Path $secretFile) -Force | Out-Null
    @{ adminPassword = $admin; sqlPassword = $sql; vpnSharedKey = $psk } | ConvertTo-Json | Set-Content $secretFile -Encoding UTF8
}

# ---- Caller identity ----
$deployerId = ''
try { $deployerId = (Invoke-Az ad signed-in-user show --query id -o tsv).Trim() } catch { Write-Warning 'Not a user sign-in: Key Vault role for the deployer will be skipped.' }

# Role assignments (Key Vault officer for you, Arc-onboarding for the host identity) need Owner / UAA / RBAC Admin.
$canAssign = $AssumeRoleAdmin.IsPresent
$arcToken = ''
$kvAccessPolicies = $false
if (-not $canAssign -and $deployerId) {
    $roles = (Invoke-Az role assignment list --assignee $deployerId --include-inherited --include-groups --all `
            --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='User Access Administrator' || roleDefinitionName=='Role Based Access Control Administrator'].roleDefinitionName" -o tsv)
    $canAssign = [bool]$roles
}
if (-not $canAssign) {
    Write-Warning 'No permission to create role assignments detected: using Key Vault access policies for you and YOUR ARM token (short-lived) for Azure Arc onboarding instead of the host managed identity. Use -AssumeRoleAdmin to override.'
    $kvAccessPolicies = $true
    if (-not $NoArc) { $arcToken = (Invoke-Az account get-access-token --resource https://management.azure.com --query accessToken -o tsv).Trim() }
}
if (-not $FabricAdminUpns) {
    try { $FabricAdminUpns = @((Invoke-Az ad signed-in-user show --query userPrincipalName -o tsv).Trim()) }
    catch { throw 'Provide -FabricAdminUpns (could not infer the signed-in user).' }
}

# ---- Parameters (secure values go through a temp file, never the command line) ----
$params = [ordered]@{
    location            = $Location
    environment         = $Environment
    workload            = $Workload
    adminPassword       = $admin
    sqlPassword         = $sql
    fabricAdminUpns     = @($FabricAdminUpns)
    fabricSku           = $FabricSku
    hostVmSize          = $HostVmSize
    deployerPrincipalId = $deployerId
    kvUseAccessPolicies = $kvAccessPolicies
    runBootstrap        = $runBootstrap
    deployBastionDeveloper = (-not $NoBastion.IsPresent)
    onboardToArc        = (-not $NoArc.IsPresent)
    arcAccessToken      = $arcToken
}
if ($Pattern -ne 3) { $params.vpnSharedKey = $psk; $params.deployTestVm = (-not $NoTestVm.IsPresent) }
if ($Pattern -in 1, 2) { $params.deployDnsResolver = (-not $NoDnsResolver.IsPresent) }
if ($Pattern -in 1, 4) {
    $params.hybridLinkMode = $HybridLinkMode
    $params.expressRouteCircuitId = $ExpressRouteCircuitId
    $params.expressRouteAuthorizationKey = $ExpressRouteAuthorizationKey
    if ($HybridLinkMode -eq 'expressRoute') { $params.deployOnPremSite = $false }
}
$paramDoc = @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = @{} }
foreach ($k in $params.Keys) { $paramDoc.parameters[$k] = @{ value = $params[$k] } }
$paramFile = Join-Path ([IO.Path]::GetTempPath()) "fabcn-p$Pattern-$([guid]::NewGuid().ToString('N')).json"
$paramDoc | ConvertTo-Json -Depth 6 | Set-Content -Path $paramFile -Encoding UTF8
$deployName = "fabcn-p$Pattern-$(Get-Date -Format 'yyyyMMddHHmmss')"

try {
    switch ($Action) {
        'Validate' { Invoke-Az deployment sub validate --name $deployName --location $Location --template-file $template --parameters "@$paramFile" -o none; Write-Host 'Template validation succeeded.' -ForegroundColor Green }
        'WhatIf' { & az deployment sub what-if --name $deployName --location $Location --template-file $template --parameters "@$paramFile"; if ($LASTEXITCODE) { throw 'what-if failed' } }
        'Deploy' {
            Write-Host "Deploying $deployName (gateways take 30-45 min)..." -ForegroundColor Cyan
            & az deployment sub create --name $deployName --location $Location --template-file $template --parameters "@$paramFile" -o none
            if ($LASTEXITCODE) { throw "Deployment failed. Inspect: az deployment operation sub list --name $deployName" }
            $out = Invoke-Az deployment sub show --name $deployName --query properties.outputs -o json | ConvertFrom-Json
            Write-Host "`n=== Outputs ===" -ForegroundColor Green
            $out.PSObject.Properties | ForEach-Object { '{0,-22} {1}' -f $_.Name, ($_.Value.value | ConvertTo-Json -Compress -Depth 5) }
            Write-Host "`nSecrets (VM admin, SQL fabricsvc, VPN PSK) are in Key Vault '$($out.keyVault.value)'. Admin user: azureadmin" -ForegroundColor Yellow
            Write-Host "Host bootstrap continues after the first reboot (~10-15 min). Check: .\common\scripts\Test-Pattern.ps1 -Pattern $Pattern -Environment $Environment" -ForegroundColor Yellow
            $out | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $PSScriptRoot "$($p.Dir)\.last-outputs.json")
            if ($ConfigureFabric) { & (Join-Path $PSScriptRoot 'common\scripts\Fabric-Configure.ps1') -Pattern $Pattern -Environment $Environment -Workload $Workload }
        }
    }
}
finally { Remove-Item $paramFile -Force -ErrorAction SilentlyContinue }
