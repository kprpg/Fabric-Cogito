# 04 - Customer Fabric analytics foundation with private Epic SQL

**Use when:** both customer-owned Fabric analytics and private provider SQL are
required, and the combined network/identity/gateway/connector path is approved.

Includes the customer F capacity, private keyless ADLS staging, private Windows
gateway-capable host, filtered egress, monitoring, and a manual cross-tenant
workspace private endpoint. It has no public TCP 1433 egress rule.

Deploy [shared/provider](../shared/provider/) separately as Epic, then this
scenario as the customer with the returned `providerPrivateLinkServiceId` and
explicit `privateConnectivityApproved=true`. Epic approval and the
[post-approval SQL DNS deployment](../shared/consumer-sql-dns/) are mandatory.
Follow the [runbook](../README.md) for exact sequencing and acceptance.

The customer's Fabric SaaS does not inherit the VM's private network. Only a
separately registered and validated gateway/connector path can use that network.
The templates do not deploy a native Fabric managed private endpoint, shortcut,
workspace, ingestion job, or private Epic tenant-wide connection. Registering a
gateway alone does not prove special cross-tenant SQL authentication/refresh
support. Keep ingestion disabled until the joint pilot passes.

This is the most isolated provider SQL topology, not a compliance certificate or
an assertion that Epic runs the topology pictured in the source diagrams.
