<#
.SYNOPSIS
  Verifies a deployed pattern: tunnel/BGP state, non-Azure appearance of the on-prem host (Arc), DNS and TCP 1433
  from the Azure side. Uses `az vm run-command` on the Azure test VM (which keeps its guest agent).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(1, 2, 3, 4)][int]$Pattern,
    [string]$Environment = 'dev',
    [string]$Workload = 'fabcn'
)
$ErrorActionPreference = 'Continue'
$tags = @{ 1 = 'p1-vnetgw-expressroute'; 2 = 'p2-vnetgw-s2s-vpn'; 3 = 'p3-onprem-gateway'; 4 = 'p4-mpe-pls' }
$tag = $tags[$Pattern]
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($Name, [bool]$Ok, $Detail) {
    $results.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}
function Az-Json { $o = & az @args -o json 2>$null; if ($LASTEXITCODE -eq 0 -and $o) { $o | ConvertFrom-Json } }

$rgs = Az-Json group list --query "[?tags.pattern=='$tag' && tags.environment=='$Environment' && tags.workload=='$Workload'].name"
$net = $rgs | Where-Object { $_ -like '*-net-*' }
$onprem = $rgs | Where-Object { $_ -like '*-onprem-*' }
$fabric = $rgs | Where-Object { $_ -like '*-fabric-*' }
Add-Result 'Resource groups present' ($rgs.Count -ge 3) ($rgs -join ', ')

# 1. Fabric capacity
if ($fabric) {
    $cap = Az-Json resource list -g $fabric --resource-type Microsoft.Fabric/capacities
    Add-Result 'Fabric capacity provisioned' ($cap -and $cap[0].provisioningState -eq 'Succeeded') ($cap | ForEach-Object { "$($_.name) ($($_.sku.name))" })
}

# 2. Hybrid link
if ($net) {
    $conns = Az-Json network vpn-connection list -g $net
    if ($conns) {
        foreach ($c in $conns) {
            $st = Az-Json network vpn-connection show -g $net -n $c.name
            Add-Result "VPN tunnel $($c.name)" ($st.connectionStatus -eq 'Connected') $st.connectionStatus
        }
        $gw = Az-Json network vnet-gateway list -g $net --query "[?gatewayType=='Vpn'] | [0]"
        if ($gw) {
            $peers = Az-Json network vnet-gateway list-bgp-peer-status -g $net -n $gw.name
            Add-Result 'BGP peer established' ([bool]($peers.value | Where-Object { $_.state -eq 'Connected' })) (($peers.value | ForEach-Object { "$($_.neighbor)=$($_.state)" }) -join ',')
            $routes = Az-Json network vnet-gateway list-learned-routes -g $net -n $gw.name
            $onpremRoute = $routes.value | Where-Object { $_.origin -eq 'EBgp' } | Select-Object -First 3
            Add-Result 'On-prem prefix learned via BGP' ([bool]$onpremRoute) (($onpremRoute | ForEach-Object { "$($_.network) via $($_.nextHop)" }) -join '; ')
        }
    }
}

# 3. Host looks non-Azure
if ($onprem) {
    $vms = Az-Json vm list -g $onprem -d
    foreach ($vm in $vms) {
        $iv = Az-Json vm get-instance-view -g $onprem -n $vm.name
        $agent = if ($iv.vmAgent.statuses) { $iv.vmAgent.statuses[0].displayStatus } else { 'not reporting (disabled)' }
        $arc = Az-Json connectedmachine show -g $onprem -n "$($vm.name)-arc"
        Add-Result "Arc machine for $($vm.name)" ($arc.status -eq 'Connected') "$($arc.status); cloud provider seen by Arc: '$($arc.cloudMetadata.provider)'; Azure guest agent: $agent"
        Add-Result "Azure origin hidden from Arc ($($vm.name))" (@('', 'N/A', 'Unknown') -contains [string]$arc.cloudMetadata.provider) "cloudMetadata.provider='$($arc.cloudMetadata.provider)'"
    }
}

# 4. Data path from the Azure side
if ($net -and $Pattern -ne 3) {
    $test = (Az-Json vm list -g $net | Where-Object { $_.name -like '*-test-*' } | Select-Object -First 1).name
    if ($test) {
        $target = if ($Pattern -eq 4) { '10.40.2.10' } else { @{ 1 = '10.110.1.4'; 2 = '10.120.1.4' }[$Pattern] }
        $dnsName = 'sql01.corp.contoso.lab'
        $script = @(
            "echo DNS=`$(getent hosts $dnsName | awk '{print `$1}')",
            "nc -vz -w 8 $target 1433 2>&1 && echo TCP1433=OK || echo TCP1433=FAIL"
        )
        $r = Az-Json vm run-command invoke -g $net -n $test --command-id RunShellScript --scripts @script
        $msg = $r.value[0].message
        if ($Pattern -ne 4) { Add-Result 'DNS: sql01.corp.contoso.lab resolves via resolver->on-prem DNS' ($msg -match "DNS=$([regex]::Escape($target))") ($msg -replace "`n", ' | ') }
        Add-Result "TCP 1433 from Azure VNet to $target" ($msg -match 'TCP1433=OK') ($msg -replace "`n", ' | ')
    }
}

$results | Format-Table -AutoSize -Wrap
if ($results.Result -contains 'FAIL') { exit 1 }
