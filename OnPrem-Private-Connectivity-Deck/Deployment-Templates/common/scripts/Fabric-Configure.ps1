<#
.SYNOPSIS
  Post-deployment Fabric steps that ARM cannot do: create/assign a Fabric workspace and, for Pattern 4,
  create the managed private endpoint (Fabric REST) and approve the pending connection on the Private Link Service.
  Patterns 1-3 additionally print the manual portal steps (VNet data gateway / on-premises data gateway).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(1, 2, 3, 4)][int]$Pattern,
    [string]$Environment = 'dev',
    [string]$Workload = 'fabcn',
    [string]$WorkspaceName,
    [string]$CapacityId,
    [SecureString]$SqlPassword
)
$ErrorActionPreference = 'Stop'
$tags = @{ 1 = 'p1-vnetgw-expressroute'; 2 = 'p2-vnetgw-s2s-vpn'; 3 = 'p3-onprem-gateway'; 4 = 'p4-mpe-pls' }
$tag = $tags[$Pattern]
if (-not $WorkspaceName) { $WorkspaceName = "ws-$Workload-p$Pattern-$Environment" }
$fabricApi = 'https://api.fabric.microsoft.com/v1'

function Az-Json { $o = & az @args -o json 2>&1; if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed: $o" }; if ($o) { $o | ConvertFrom-Json } }
$token = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv).Trim()
$h = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
function Wait-Lro($resp) {
    if ($resp.StatusCode -ne 202) { return $resp.Content | ConvertFrom-Json }
    $loc = $resp.Headers['Location'] | Select-Object -First 1
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 5
        $s = Invoke-WebRequest -Uri $loc -Headers $h -SkipHttpErrorCheck
        $st = ($s.Content | ConvertFrom-Json).status
        if ($st -eq 'Succeeded') { return Invoke-RestMethod -Uri "$loc/result" -Headers $h -ErrorAction SilentlyContinue }
        if ($st -eq 'Failed') { throw "Fabric operation failed: $($s.Content)" }
    }
    throw 'Timed out waiting for Fabric operation.'
}

$rgs = Az-Json group list --query "[?tags.pattern=='$tag' && tags.environment=='$Environment' && tags.workload=='$Workload'].name"
$fabricRg = $rgs | Where-Object { $_ -like '*-fabric-*' }
$netRg = $rgs | Where-Object { $_ -like '*-net-*' }
$capName = (Az-Json resource list -g $fabricRg --resource-type Microsoft.Fabric/capacities)[0].name

# 1. Capacity id in Fabric (capacity must be Active). Use -CapacityId to target an existing F/Trial capacity.
if ($CapacityId) { $cap = [pscustomobject]@{ id = $CapacityId; displayName = $CapacityId; state = 'n/a' } }
else {
    $uri = "$fabricApi/capacities"; $all = @()
    do { $page = Invoke-RestMethod -Uri $uri -Headers $h; $all += $page.value; $uri = $page.continuationUri } while ($uri)
    $cap = $all | Where-Object { $_.displayName -ieq $capName }
    if (-not $cap) { throw "Capacity $capName not visible to your Fabric identity (resumed? you must be a capacity admin; the Fabric admin portal may need a few minutes). Pass -CapacityId <guid> to use another F/Trial capacity." }
}
Write-Host "Capacity: $($cap.displayName) ($($cap.id)) state=$($cap.state)"

# 2. Workspace
$ws = (Invoke-RestMethod -Uri "$fabricApi/workspaces" -Headers $h).value | Where-Object { $_.displayName -eq $WorkspaceName }
if (-not $ws) {
    $r = Invoke-WebRequest -Method Post -Uri "$fabricApi/workspaces" -Headers $h -Body (@{ displayName = $WorkspaceName; capacityId = $cap.id } | ConvertTo-Json)
    $ws = $r.Content | ConvertFrom-Json
    Write-Host "Created workspace $WorkspaceName ($($ws.id))" -ForegroundColor Green
}
else { Write-Host "Workspace exists: $($ws.id)" }
if ($ws.capacityId -ne $cap.id) {
    $null = Invoke-RestMethod -Method Post -Uri "$fabricApi/workspaces/$($ws.id)/assignToCapacity" -Headers $h -Body (@{ capacityId = $cap.id } | ConvertTo-Json)
    Write-Host 'Workspace assigned to capacity.'
}

switch ($Pattern) {
    4 {
        $pls = (Az-Json network private-link-service list -g $netRg)[0]
        $mpeName = 'mpe-onprem-sql'
        $existing = (Invoke-RestMethod -Uri "$fabricApi/workspaces/$($ws.id)/managedPrivateEndpoints" -Headers $h).value | Where-Object { $_.name -eq $mpeName }
        if (-not $existing) {
            $body = @{
                name                        = $mpeName
                targetPrivateLinkResourceId = $pls.id
                targetFQDNs                 = @('sql01.corp.contoso.lab')
                requestMessage              = 'Fabric Spark to on-prem SQL (simulated) via PLS'
            } | ConvertTo-Json
            $r = Invoke-WebRequest -Method Post -Uri "$fabricApi/workspaces/$($ws.id)/managedPrivateEndpoints" -Headers $h -Body $body -SkipHttpErrorCheck
            if ($r.StatusCode -ge 400) { throw "MPE creation failed ($($r.StatusCode)): $($r.Content)" }
            Write-Host 'Managed private endpoint requested.' -ForegroundColor Green
        }
        Write-Host 'Waiting for the pending connection on the Private Link Service ...'
        for ($i = 0; $i -lt 30; $i++) {
            $conns = (Az-Json network private-link-service show -g $netRg -n $pls.name --query privateEndpointConnections)
            $pending = $conns | Where-Object { $_.privateLinkServiceConnectionState.status -eq 'Pending' }
            if ($pending) {
                foreach ($c in $pending) {
                    & az network private-link-service connection update -g $netRg --service-name $pls.name -n $c.name --connection-status Approved --description 'Approved by Fabric-Configure.ps1' -o none
                    Write-Host "Approved $($c.name)" -ForegroundColor Green
                }
                break
            }
            Start-Sleep -Seconds 10
        }
        Write-Host @"

Use from a Fabric notebook in workspace '$WorkspaceName' (credentials in Key Vault secret sql-fabricsvc-password):
  jdbc:sqlserver://sql01.corp.contoso.lab:1433;database=OnPremSalesDemo;encrypt=true;trustServerCertificate=true
  user=fabricsvc   table: dbo.Customers / dbo.Orders
"@
    }
    { $_ -in 1, 2 } {
        $v = $rgs | Where-Object { $_ -like '*-net-*' }
        $vnet = (Az-Json network vnet list -g $v | Where-Object { $_.name -like '*-spoke-*' -or $_.name -like '*-azure-*' } | Select-Object -First 1).name
        $subId = (Az-Json account show).id
        $gwName = "gw-vnet-$Workload-p$Pattern-$Environment"
        $gw = (Invoke-RestMethod -Uri "$fabricApi/gateways" -Headers $h).value | Where-Object { $_.displayName -eq $gwName }
        if (-not $gw) {
            $body = @{
                type                          = 'VirtualNetwork'
                displayName                   = $gwName
                capacityId                    = $cap.id
                inactivityMinutesBeforeSleep  = 30
                numberOfMemberGateways        = 1
                virtualNetworkAzureResource   = @{ subscriptionId = $subId; resourceGroupName = $v; virtualNetworkName = $vnet; subnetName = 'snet-vnetgw' }
            } | ConvertTo-Json -Depth 5
            $r = Invoke-WebRequest -Method Post -Uri "$fabricApi/gateways" -Headers $h -Body $body -SkipHttpErrorCheck
            if ($r.StatusCode -ge 400) {
                Write-Warning "VNet data gateway creation via API failed ($($r.StatusCode)): $($r.Content)"
                Write-Host @"

Create it in the portal instead: Settings > Manage connections and gateways > Virtual network data gateways > New
  Capacity: $($cap.displayName) | Subscription: $subId | Resource group: $v | Virtual network: $vnet | Subnet: snet-vnetgw
(subnet is delegated to Microsoft.PowerPlatform/vnetaccesslinks; Microsoft.PowerPlatform provider is registered by Deploy-Pattern.ps1)
Then add a SQL connection: server sql01.corp.contoso.lab, database OnPremSalesDemo, Basic auth fabricsvc.
"@
                return
            }
            $gw = $r.Content | ConvertFrom-Json
            Write-Host "Created VNet data gateway $gwName ($($gw.id))" -ForegroundColor Green
        }
        else { Write-Host "VNet data gateway exists: $($gw.id)" }

        if ($SqlPassword) {
            $plain = [System.Net.NetworkCredential]::new('', $SqlPassword).Password
            $conn = @{
                connectivityType  = 'VirtualNetworkGateway'
                gatewayId         = $gw.id
                displayName       = "conn-onprem-sql-p$Pattern-$Environment"
                connectionDetails = @{ type = 'SQL'; creationMethod = 'SQL'; parameters = @(
                        @{ dataType = 'Text'; name = 'server'; value = 'sql01.corp.contoso.lab' },
                        @{ dataType = 'Text'; name = 'database'; value = 'OnPremSalesDemo' }) }
                privacyLevel      = 'Organizational'
                credentialDetails = @{ singleSignOnType = 'None'; connectionEncryption = 'NotEncrypted'; skipTestConnection = $false
                    credentials = @{ credentialType = 'Basic'; username = 'fabricsvc'; password = $plain } }
            } | ConvertTo-Json -Depth 8
            Write-Host 'Creating SQL connection on the gateway (this tests connectivity through the VNet data gateway) ...'
            $r = Invoke-WebRequest -Method Post -Uri "$fabricApi/connections" -Headers $h -Body $conn -SkipHttpErrorCheck
            if ($r.StatusCode -ge 400) { throw "Connection creation/test failed ($($r.StatusCode)): $($r.Content)" }
            Write-Host "Connection created and tested through the VNet data gateway: $(($r.Content | ConvertFrom-Json).id)" -ForegroundColor Green
        }
        else { Write-Host 'Re-run with -SqlPassword to create a SQL connection on the gateway and test the private path.' }
    }
    3 {
        Write-Host @"

MANUAL STEP: install the on-premises data gateway on the gateway VM(s) (RDP via Bastion Developer), then run
  common\scripts\Install-OnPremGateway.ps1 -GatewayName gw-$Workload-p3-$Environment
and add a SQL connection: server 10.130.1.4, database OnPremSalesDemo, Basic auth fabricsvc.
"@
    }
}
