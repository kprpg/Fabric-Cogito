# 02 - IP addressing and naming conventions

## Naming

`<abbr>-<workload>-<pattern>-<role>-<env>-<region>[-nnn]` following Cloud Adoption Framework abbreviations.
`workload` = `fabcn` (Fabric connectivity), `pattern` = `p1`..`p4`, `env` = `dev`, region = short code (`eus2`).

| Resource | Example |
|---|---|
| Resource group | `rg-fabcn-p1-net-dev-eus2`, `-onprem-`, `-gov-`, `-fabric-` |
| VNet / subnet | `vnet-fabcn-p1-hub-dev-eus2`, `snet-vnetgw`, `snet-lan`, `GatewaySubnet` |
| NSG / NAT | `nsg-fabcn-p1-vnetgw-dev-eus2`, `ng-fabcn-p1-spoke-dev-eus2` |
| VPN / ER gateway | `vgw-fabcn-p1-hub-dev-eus2`, `ergw-...` (public IP `pip-<name>`) |
| Local gateway / connection | `lgw-fabcn-p1-onprem-dev-eus2`, `cn-fabcn-p1-hub-to-onprem-dev-eus2` |
| VM | `vm-fabcn-p1-sql01-dev-eus2` (Arc twin: `<vm>-arc`) |
| Governance | `log-fabcn-p1-dev-eus2`, `kv-fabcn-p1-dev-<5>`, `stfabcnp1dev<6>` |
| Fabric capacity | `fcfabcnp1deveus2` (lowercase alphanumeric only) |

Each pattern has its own resource groups, so deleting a pattern is deleting 3-4 groups. Tags: `workload`, `pattern`,
`environment`, `purpose`, `managed-by` (the scripts discover a pattern's groups by these tags).

## Address plan (nothing overlaps, so any patterns can later be peered or share one tenant)

| Pattern | Azure side | Simulated on-prem | BGP ASN (Azure / on-prem) |
|---|---|---|---|
| 1 | hub `10.10.0.0/22`, spoke `10.10.4.0/22` | `10.110.0.0/16` | 65010 / 65110 |
| 2 | `10.20.0.0/16` | `10.120.0.0/16` | 65020 / 65120 |
| 3 | (none) | `10.130.0.0/16` | - |
| 4 | `10.40.0.0/16` | `10.140.0.0/16` | 65040 / 65140 |

Detail per pattern (`.4` is the first usable host in an Azure subnet):

| Pattern | Subnet | CIDR | Purpose |
|---|---|---|---|
| 1 hub | GatewaySubnet / snet-dns-out | 10.10.0.0/26 / 10.10.0.64/28 | hub gateway / DNS resolver outbound |
| 1 spoke | snet-vnetgw / snet-test | 10.10.4.0/27 / 10.10.4.32/27 | delegated `Microsoft.PowerPlatform/vnetaccesslinks` / test client |
| 2 | GatewaySubnet, snet-dns-out, snet-vnetgw, snet-test | 10.20.0.0/26, 10.20.0.64/28, 10.20.1.0/27, 10.20.1.32/27 | |
| 4 | GatewaySubnet, snet-pls-nat, snet-fwd, snet-test | 10.40.0.0/26, 10.40.1.0/27, 10.40.2.0/27 (ILB 10.40.2.10), 10.40.3.0/27 | |
| on-prem N | GatewaySubnet / snet-lan | 10.N0.0.0/27 / 10.N0.1.0/24 | edge VPN gateway / SQL host `.1.4` |
| on-prem N | nested Hyper-V LAN | 10.N0.2.0/24 (host `.2.1`) | internal vSwitch for nested guests |
| 3 | snet-lan | 10.130.1.0/24 | SQL `.4`, gateway nodes `.5`, `.6` |

Reserved/avoided: ASNs 8074, 8075, 12076, 65515-65520 (Azure); the VNet data gateway subnet may not be named
`GatewaySubnet`/`AzureBastionSubnet`.
