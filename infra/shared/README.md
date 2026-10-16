# Shared infrastructure

`customer-environment.bicep` composes the customer foundation used by all four
entry points. Its flags are internal wiring; deploy a numbered scenario instead
of calling it directly with arbitrary flag combinations. `types.bicep` supplies
shared sealed parameter types, constraints, and the supported Fabric SKU set.

| Module | Responsibility |
|---|---|
| `modules/monitoring` | Log Analytics and resource-authorized log access |
| `modules/network` | New VNet/subnets, workload NSG, filtered Firewall policy, routes, Bastion, network diagnostics |
| `modules/client` | Private Windows Trusted Launch SQL client / gateway-capable host |
| `modules/workspace-private-endpoint` | Manual request to Epic's workspace Private Link resource, Fabric DNS zone/link/group |
| `modules/fabric-capacity` | Customer-owned regional F capacity and approved administrators |
| `modules/landing-storage` | Private keyless ADLS Gen2, blob/DFS endpoints and DNS, optional container-scoped workload role, logs |
| `provider/main` | **Separate Epic-tenant deployment**: Private Link service for an existing provider workspace |
| `consumer-sql-dns/main` | **Separate post-approval customer deployment**: exact SQL host record mapped to verified SQL-member IP |

Every deployable `.bicep` has a generated sibling `.json`. Each JSON is a
standalone ARM deployment template, not a hand-maintained alternative source.
The type-only file has no ARM counterpart.

The provider and SQL DNS templates are separate because an Epic approval and
verified multi-IP DNS handoff cannot honestly be represented as a dependency
executed by a customer Azure deployment. Neither template changes consent,
identity mappings, SQL permissions, or Fabric workspace communication policy.
See the [runbook](../README.md) for sequencing and permissions.
