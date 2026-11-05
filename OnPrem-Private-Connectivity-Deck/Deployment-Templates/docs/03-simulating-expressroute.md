# 03 - Simulating ExpressRoute when it is not authorized

A real ExpressRoute circuit needs a connectivity provider (or ExpressRoute Direct) and an authorized subscription.
For the lab, what matters to Fabric / the VNet data gateway is the *Azure-side* behaviour: a gateway in the hub
that learns on-prem prefixes over BGP, advertises VNet prefixes, and is consumed by a spoke through peering with
**gateway transit**. All of that is identical for a VPN gateway.

## Options (pick with `-HybridLinkMode` on patterns 1 and 4)

| Option | What it is | Cost / lead time | Fidelity |
|---|---|---|---|
| **`simulatedVpn` (default)** | Hub BGP VPN gateway tunnels to a second VPN gateway in the isolated "on-prem" VNet. Hub-and-spoke, `allowGatewayTransit` / `useRemoteGateways`, BGP, ASNs all as in the real design. | ~$0.19/h per gateway; 30-45 min | Routing, DNS, NSG/UDR and VNet data gateway behaviour identical; not private-peering latency/SLA |
| `expressRoute` (no circuit) | Deploys the real ER gateway (`ErGw1AZ`) in `GatewaySubnet` only; rehearses subnet sizing, peering flags, IaC | ER gateway hourly | Control-plane only; no traffic |
| `expressRoute` + circuit | Pass `-ExpressRouteCircuitId` and `-ExpressRouteAuthorizationKey`: the gateway is connected to your circuit | Provider circuit | Real; set `deployOnPremSite` false |
| Provider lab | NaaS partners (e.g. virtual cross connects) provision an ER circuit in minutes | partner fees | Real |

## Moving from the stand-in to real ExpressRoute

1. Redeploy hub with `-HybridLinkMode expressRoute` (GatewaySubnet stays `/26`, which fits both gateways).
2. Delete the VPN gateway/connection; peering flags are unchanged because they reference "the gateway in the hub".
3. Advertise the on-prem SQL prefix over private peering; keep the same on-prem firewall rule (delegated subnet to 1433).
4. VNet data gateway, delegated subnet, DNS Private Resolver forwarding rule and NSGs need no change.

## What the simulation does not prove

ER bandwidth/latency, ER circuit failover and Global Reach, provider-side route filters. Validate those in the pilot.
