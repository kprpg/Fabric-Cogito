# Pattern 2 - VNet data gateway over Site-to-Site VPN (single VNet)

```mermaid
flowchart LR
  subgraph F[Fabric / Power BI]
    SM[Semantic model / Dataflow Gen2 / pipeline]
  end
  subgraph A[rg-fabcn-p2-net  10.20.0.0/16]
    GW[snet-vnetgw delegated\nVNet data gateway] --- VGW[GatewaySubnet\nVpnGw1AZ BGP ASN 65020]
    DNS[DNS Private Resolver]
  end
  subgraph O[rg-fabcn-p2-onprem  10.120.0.0/16]
    EDGE[Edge VPN gateway ASN 65120] --- SQL[(Hyper-V host + SQL 10.120.1.4\nIMDS blocked, Arc-enabled)]
  end
  SM -->|Microsoft backbone| GW
  VGW <== IPsec IKEv2 + BGP ==> EDGE
```

| | |
|---|---|
| Deploy | `..\Deploy-Pattern.ps1 -Pattern 2` or `.\deploy.ps1` or `.\azd-init.ps1; azd up` |
| Test | `..\common\scripts\Test-Pattern.ps1 -Pattern 2` (tunnel, BGP, Arc, DNS, TCP 1433) |
| Fabric | `..\common\scripts\Fabric-Configure.ps1 -Pattern 2 ...` (same as pattern 1) |
| Bring your own device | set `deployVpnDevice` false in the site call and add a local network gateway + connection for your real device |
| Resource groups | `rg-fabcn-p2-{net,onprem,gov,fabric}-dev-eus2` |
