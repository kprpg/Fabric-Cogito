# Pattern 3 - On-premises data gateway (outbound only)

```mermaid
flowchart LR
  subgraph O[rg-fabcn-p3-onprem  10.130.0.0/16  snet-lan 10.130.1.0/24]
    GW1[gateway node 01 .5] --> SQL[(Hyper-V host + SQL .4\nArc-enabled, IMDS blocked)]
    GW2[gateway node 02 .6] --> SQL
    NSG{{NSG egress: 443, 5671-5672, 9350-9354\nno inbound}}
  end
  subgraph M[Microsoft cloud]
    RELAY[Azure Relay / gateway service] --> F[Fabric / Power BI]
  end
  GW1 -- outbound TLS/AMQP --> RELAY
  GW2 -- outbound TLS/AMQP --> RELAY
```

| | |
|---|---|
| Deploy | `..\Deploy-Pattern.ps1 -Pattern 3` (about 10 min, no gateways) or `.\azd-init.ps1; azd up` |
| Test | `..\common\scripts\Test-Pattern.ps1 -Pattern 3` (Arc/non-Azure for 3 hosts) |
| Gateway install | interactive: `..\common\scripts\Install-OnPremGateway.ps1 -GatewayName gw-fabcn-p3-dev` on node 01, `-JoinExisting` on node 02 (see [docs/05](../docs/05-post-deployment-testing-cost.md)) |
| SQL for the connection | server `10.130.1.4`, database `OnPremSalesDemo`, login `fabricsvc` |
| Resource groups | `rg-fabcn-p3-{onprem,gov,fabric}-dev-eus2` (no Azure network by design) |
| Optional hardening | add a deny-internet outbound rule after the allow rules; use Fabric Private Link for user access |
