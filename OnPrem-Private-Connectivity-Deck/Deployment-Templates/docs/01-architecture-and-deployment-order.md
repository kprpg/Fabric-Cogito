# 01 - Architecture and deployment order

Every pattern is a subscription-scope Bicep deployment (`pattern*/infra/main.bicep`) that composes shared modules from
`common/modules`. Resource-group isolation and ordering:

```
rg-fabcn-pN-gov-...     Log Analytics  Key Vault  ADLS Gen2 storage                       (1st: diagnostics + secrets exist before anything uses them)
rg-fabcn-pN-net-...     VNet(s) NSG NAT  [hub gateway | VNet-data-gateway subnet | DNS resolver | ILB+forwarders+PLS]
rg-fabcn-pN-onprem-...  simulated site: VNet, NAT, Bastion Developer, edge VPN gateway, SQL/Hyper-V host (looks non-Azure)
rg-fabcn-pN-fabric-...  Microsoft.Fabric/capacities (F SKU)                                  (last: explicit dependsOn so billing starts late)
```

| Step | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| 1 governance | yes | yes | yes | yes |
| 2 network | hub + spoke (delegated `snet-vnetgw`), NAT, DNS resolver | single VNet (delegated `snet-vnetgw`), NAT, DNS resolver | - | VNet with `snet-pls-nat`, `snet-fwd` |
| 3 simulated on-prem | yes | yes | yes (SQL + 2 gateway nodes, no VPN) | yes |
| 4 hybrid link | BGP VPN (ER stand-in) or ER gateway | BGP IPsec VPN | none (outbound 443/5671-5672/9350-9354) | BGP VPN or ER gateway |
| 5 specifics | hub<->spoke peering with gateway transit | - | NSG egress allow-list for the gateway | internal LB, 2 NAT forwarders, Private Link Service |
| 6 Fabric capacity | yes | yes | yes | yes |
| 7 post-deploy (scripts) | VNet data gateway (+SQL connection) | same | install on-prem gateway (interactive) | managed private endpoint + PLS approval |

Why the order matters: the hub gateway must exist before the spoke peering can set `useRemoteGateways`; both VPN gateways
must exist (public IPs, BGP IPs) before either side's local network gateway/connection; the DNS resolver forwards to the
on-prem DNS server that only works once the tunnel is up; the PLS fronts a load balancer whose forwarders need a route to
on-prem; the Fabric capacity is the last (and most expensive per hour of idle) resource.

## Module map (`common/modules`)

`vnet`, `nsg`, `nat-gateway`, `vpn-gateway`, `er-gateway`, `s2s-connection`, `vnet-peering`, `dns-resolver`,
`governance`, `fabric-capacity`, `onprem-site` (composes `onprem-host`, `bastion-developer`, optional `vpn-gateway`),
`private-link-service` (ILB + forwarders + PLS), `test-client`, `shared` (region short names, role IDs).

## Per-pattern data flow

- **P1/P2**: Fabric semantic model/pipeline -> VNet data gateway container in `snet-vnetgw` -> VNet DNS -> resolver rule
  `corp.contoso.lab` -> on-prem DNS -> `sql01` -> route via hub gateway (BGP) -> tunnel -> on-prem SQL :1433.
- **P3**: Gateway service <- outbound TLS/AMQP from the gateway nodes (Azure Relay); gateway reads SQL on the LAN.
- **P4**: Fabric Spark -> managed private endpoint -> your PLS -> ILB 10.40.2.10:1433 -> forwarder DNAT -> tunnel -> SQL.
  PLS Direct Connect (preview, East US 2 supported) can replace ILB + forwarders; keep it as an alternative once enabled.
