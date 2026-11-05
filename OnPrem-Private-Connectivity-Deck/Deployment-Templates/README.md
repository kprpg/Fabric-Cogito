# Private connectivity from Microsoft Fabric / Power BI to on-premises SQL Server: deployable lab

Four patterns from `Fabric-PBI-OnPrem-Private-Connectivity.pdf`, each deployable with one command into its own set of
resource groups. No ExpressRoute circuit and no physical on-premises site are needed: both are simulated in Azure.

| # | Pattern | Hybrid link in the lab | Folder |
|---|---------|------------------------|--------|
| 1 | VNet data gateway + ExpressRoute (hub & spoke) | BGP VPN gateway as ExpressRoute stand-in (or a real ER gateway/circuit) | [pattern1-vnetgw-expressroute](pattern1-vnetgw-expressroute) |
| 2 | VNet data gateway + S2S VPN (single VNet) | IPsec/IKEv2 + BGP between two Azure VPN gateways | [pattern2-vnetgw-s2s-vpn](pattern2-vnetgw-s2s-vpn) |
| 3 | On-premises data gateway (outbound only) | none (outbound 443/5671-5672/9350-9354 to Azure Relay) | [pattern3-onprem-gateway](pattern3-onprem-gateway) |
| 4 | Managed private endpoint + Private Link Service | same as pattern 1 | [pattern4-mpe-pls](pattern4-mpe-pls) |

## Quick start

```powershell
az login
.\Deploy-Pattern.ps1 -Pattern 2                 # or 1, 3, 4   (~45 min: VPN gateways dominate)
.\common\scripts\Test-Pattern.ps1 -Pattern 2    # tunnel, BGP, Arc/non-Azure, DNS, TCP 1433
.\common\scripts\Fabric-Configure.ps1 -Pattern 4   # workspace (+ managed private endpoint + PLS approval for P4)
.\Deploy-Pattern.ps1 -Pattern 2 -Action Pause   # stop VM + Fabric capacity spend
.\Deploy-Pattern.ps1 -Pattern 2 -Action Destroy
```

Alternatives per pattern: `cd pattern2-vnetgw-s2s-vpn; .\azd-init.ps1; azd up` (azd needs its secure inputs before it runs, so
`azd-init.ps1` seeds the environment with generated secrets first) or the thin `deploy.ps1` wrapper.
Other actions: `-Action Validate | WhatIf`. Useful switches: `-HybridLinkMode expressRoute`, `-NoBastion`, `-NoArc`, `-NoDnsResolver`, `-FabricSku F4`.

## What gets deployed (dependency order)

```
Subscription-scope main.bicep
 1. Resource groups  rg-fabcn-pN-{net|onprem|gov|fabric}-<env>-<region>
 2. Governance (gov)         Log Analytics, Key Vault (RBAC, secrets), ADLS Gen2 storage
 3. Network (net)            VNets, NSGs, NAT gateway, delegated subnets, DNS Private Resolver
 4. Simulated on-prem (onprem) VNet, NAT egress, Bastion Developer, VPN gateway (edge device), Hyper-V/SQL host
 5. Hybrid link              VPN gateways + BGP tunnels  (or ER gateway [+ circuit connection])
 6. Pattern specifics        peering | internal LB + NAT forwarders + Private Link Service | gateway nodes
 7. Fabric (fabric)          Fabric capacity F SKU  (last)
 8. Post-deploy (scripts)    Fabric workspace, managed private endpoint + approval, gateway registration
```

## Documents

- [01 Architecture and deployment order](docs/01-architecture-and-deployment-order.md)
- [02 IP addressing and naming conventions](docs/02-ip-addressing-and-naming.md)
- [03 Simulating ExpressRoute when it is not authorized](docs/03-simulating-expressroute.md)
- [04 Simulating on-premises: nested Hyper-V host that looks non-Azure, and the VPN peer](docs/04-simulating-onprem-and-vpn.md)
- [05 Post-deployment, testing and cost control](docs/05-post-deployment-testing-cost.md)

## Prerequisites

Azure CLI 2.60+ (Bicep is installed on demand), PowerShell 7, Contributor on the subscription, a Fabric-enabled tenant,
and vCPU quota for `Standard_D4s_v5` (Dsv5 supports nested virtualization). Owner/User Access Administrator is optional:
without it the scripts skip role assignments and use your short-lived ARM token for Azure Arc onboarding.

> The simulated on-premises hosts use Microsoft's *evaluate Azure Arc on an Azure VM* technique. It is supported for
> evaluation and testing only, never production.
