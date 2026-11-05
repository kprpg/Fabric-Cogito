# Pattern 4 - Managed private endpoint + Private Link Service

```mermaid
flowchart LR
  subgraph F[Fabric workspace  F SKU or Trial]
    NB[Spark notebook / job] --> MPE[Managed private endpoint\n+ FQDN sql01.corp.contoso.lab]
  end
  subgraph A[rg-fabcn-p4-net  10.40.0.0/16]
    PLS[Private Link Service\nsnet-pls-nat 10.40.1.0/27] --> ILB[Internal Standard LB 10.40.2.10:1433]
    ILB --> FW1[NAT forwarder 1] & FW2[NAT forwarder 2]
    VGW[GatewaySubnet BGP VPN gateway ASN 65040]
  end
  subgraph O[rg-fabcn-p4-onprem  10.140.0.0/16]
    EDGE[Edge VPN gateway ASN 65140] --- SQL[(Hyper-V host + SQL 10.140.1.4)]
  end
  MPE -->|Private Link, Microsoft backbone| PLS
  FW1 & FW2 -->|DNAT 1433| VGW
  VGW <== IPsec + BGP ==> EDGE
```

| | |
|---|---|
| Deploy | `..\Deploy-Pattern.ps1 -Pattern 4` or `.\azd-init.ps1; azd up` (`-HybridLinkMode expressRoute` for a real ER gateway) |
| Test network | `..\common\scripts\Test-Pattern.ps1 -Pattern 4` |
| Create + approve the endpoint | `..\common\scripts\Fabric-Configure.ps1 -Pattern 4 [-CapacityId <guid>]`: creates workspace, `POST /managedPrivateEndpoints` with the PLS id and FQDN, approves the pending PLS connection |
| End-to-end proof | `..\common\scripts\Test-FabricSpark.ps1 -WorkspaceId <guid> -SqlPassword <secure>` runs a notebook that reads `dbo.Orders` (5000 rows) through the endpoint |
| PLS visibility | defaults to `*` with manual approval (the Fabric requester subscription is not published); tighten via `plsVisibilitySubscriptions` |
| Notes | workspaces with managed private endpoints need a custom Spark pool; delete the endpoint before deleting the workspace |
| Resource groups | `rg-fabcn-p4-{net,onprem,gov,fabric}-dev-eus2` |
