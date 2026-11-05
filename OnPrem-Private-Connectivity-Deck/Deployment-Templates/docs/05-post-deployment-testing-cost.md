# 05 - Post-deployment, testing and cost control

## Verified results (this template set was deployed and tested in East US 2)

| Check | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| Templates deploy end to end with `Deploy-Pattern.ps1` | yes | yes | yes | yes |
| IPsec tunnel `Connected` + BGP peer + on-prem prefix learned | yes | yes | n/a | yes |
| Host shows in Azure Arc, cloud provider `N/A`, guest agent not reporting | yes | yes | yes (3 hosts) | yes |
| DNS `sql01.corp.contoso.lab` via Private Resolver -> on-prem DNS | yes | yes | n/a | n/a |
| TCP 1433 from Azure VNet to on-prem SQL | yes (hub-spoke transit) | yes | yes (LAN, from gateway node) | yes (via ILB 10.40.2.10 / NAT forwarder) |
| SQL data + SQL login (`OnPremSalesDemo`, 500 + 5000 rows) | yes | - | yes | yes |
| Fabric end-to-end | - (see below) | - (see below) | not automatable | **Spark notebook read 5000 rows through managed private endpoint -> PLS -> tunnel** |
| Pause / Resume, host survives deallocate/start | yes | - | - | - |

Known environment-dependent items: (a) creating the VNet data gateway through the Fabric API returned
`PowerPlatformVirtualNetworkSubnetNotConfiguredForDelegation` in the test tenant even for a bare, correctly delegated subnet;
`Fabric-Configure.ps1` falls back to printing the portal steps. (b) F-SKU capacities created through ARM did not appear in
that tenant's Fabric capacity list, so the Fabric tests used an existing trial capacity (`-CapacityId`).

## Commands

```powershell
.\Deploy-Pattern.ps1 -Pattern N                      # deploy (re-runnable; secrets reused, host bootstrap skipped)
.\common\scripts\Test-Pattern.ps1 -Pattern N         # tunnel/BGP/Arc/DNS/TCP checks (exit code 1 on failure)
.\common\scripts\Fabric-Configure.ps1 -Pattern N [-CapacityId <guid>] [-SqlPassword <secure>]
.\common\scripts\Test-FabricSpark.ps1 -WorkspaceId <guid> -SqlPassword <secure>   # P4 notebook proof
.\Deploy-Pattern.ps1 -Pattern N -Action Pause|Resume|Destroy [-Force] [-PurgeKeyVault]
```

## Secrets

Generated on first deployment: VM admin (`azureadmin`), SQL `fabricsvc`, VPN pre-shared key. Stored in Key Vault
(`vm-admin-password`, `sql-fabricsvc-password`, `vpn-shared-key`) and cached in the gitignored `.secrets\pN-<env>.json`
because some org policies block vault data-plane access from your workstation (`ForbiddenByConnection`). Without Owner/UAA the
vault uses access policies instead of RBAC. To reset the SQL password on a host whose guest agent is disabled use an Arc Run
Command (`az connectedmachine run-command create ...`), not `az vm run-command`.

## Working on the non-Azure hosts

The Azure guest agent is disabled by design, so `az vm run-command` and VM extensions no longer work on those VMs. Use
Bastion Developer (RDP) or Arc Run Command, e.g.:

```powershell
az connectedmachine run-command create --machine-name vm-fabcn-p3-sql01-dev-eus2-arc -g rg-fabcn-p3-onprem-dev-eus2 `
  --run-command-name q1 --location eastus2 --script "Get-Content C:\OnPremSim\stage2.log -Tail 30"
az connectedmachine run-command show --machine-name <vm>-arc -g <rg> --run-command-name q1
```

## Pattern 3: install the on-premises data gateway

RDP to `p3-onprem-gw01` (Bastion Developer), copy `common/scripts/Install-OnPremGateway.ps1`, run it in PowerShell 7
(interactive Entra sign-in + recovery key), repeat with `-JoinExisting` on `gw02`, then add a SQL data source with server
`10.130.1.4`, database `OnPremSalesDemo`, Basic auth `fabricsvc`.

## Cost (East US 2, rough, pay-as-you-go)

Per pattern with simulated VPN: 2 x VpnGw1AZ (~$0.19/h each) + 2 NAT gateways + D4s_v5 host (+B2s test VM) + F2 capacity
(~$0.36/h while running) + DNS resolver. Patterns 1/2/4 are therefore roughly $0.8-1.0/h each; P3 about $0.7/h (3 x D4s_v5
+ F2) . VMs auto-shut-down at 21:00 Central; `-Action Pause` deallocates VMs and suspends the capacity; only `-Action Destroy`
stops gateways. Deleting a pattern removes everything for it (3-4 resource groups); `-PurgeKeyVault` also purges the
soft-deleted vault so the name can be reused.
