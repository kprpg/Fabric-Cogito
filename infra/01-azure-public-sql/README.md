# 01 - Customer Azure client to Epic Fabric over public SQL

**Use when:** the customer needs approved SQL queries without buying a customer
Fabric capacity, and Epic/customer security approve public TDS.

Path: customer private Windows VM -> routed Azure Firewall -> Epic's generated
guest-specific Warehouse/SQL analytics endpoint, TCP 1433 with Entra authentication.
The VM is managed through Bastion, not public RDP. Source data stays in Epic;
returned rows can still be cached/exported by the client.

Deploy `main.bicep` or equivalent generated `main.json` with a privately edited copy
of `parameters.example.json`. Follow the [common runbook](../README.md), including
validation, context checks, what-if, and the existing Key Vault password reference.

There is no customer Fabric capacity, storage account, private provider endpoint,
or ingestion pipeline in this variant. Obtain provider consent/mapping, item
`Read`, curated SQL grants, and the actual `privateLinkType=None` guest endpoint
through the separate authorized workflow. Public SQL is not an MFA bypass and is
not acceptable if the provider requires private-only access.
