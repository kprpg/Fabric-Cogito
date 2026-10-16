# 02 - Customer Azure client to Epic Fabric over workspace Private Link

**Use when:** approved Azure clients need private provider SQL access, without a
customer Fabric capacity.

Path: customer private Windows VM -> customer workspace private endpoint -> Epic's
workspace Private Link service -> provider SQL endpoint. No public SQL egress rule
exists. Entra sign-in, management, and updates still have controlled public egress.

First, the Epic owner deploys [shared/provider](../shared/provider/) for an existing
eligible workspace. Pass its ARM resource ID to `providerPrivateLinkServiceId`,
with explicit `privateConnectivityApproved=true` design sign-off. Then deploy
`main.bicep` or generated `main.json` using edited example parameters.

The request stays pending until Epic approves it. After approval, deploy
[shared/consumer-sql-dns](../shared/consumer-sql-dns/) with the actual guest-specific
`privateLinkType=Workspace` SQL hostname and verified SQL-member IP. Full steps,
permissions, probes, and provider public-blocking gates are in the
[runbook](../README.md).

This does not deploy Epic Fabric, establish B2B trust, grant SQL access, or certify
the combined SQL mapping/private-network behavior. Those are separate joint pilot
gates; the endpoint is infrastructure, not an entitlement.
