# 03 - Customer Fabric analytics foundation with public Epic SQL

**Use when:** the customer wants its own Fabric analytics/copies and Epic approves
public SQL. The exact gateway/connector/authentication path must also be approved.

Deploys the common private Windows client/gateway-capable host and filtered
network, plus a customer F capacity and private keyless ADLS landing store.
Provider SQL uses controlled public TCP 1433; the customer landing store remains
private. It is not Epic's OneLake storage.

Deploy `main.bicep` or generated `main.json` using a privately edited example.
Set real customer capacity administrators, approved SKU/region, and optionally an
approved customer service principal object ID for container-scoped data access.
Use the [runbook](../README.md) for deployment and Fabric handoff.

Capacity does not create a workspace, Lakehouse, registered gateway, connection,
or copy schedule. Install/register the standard gateway only for a supported
integration, configure HTTPS-only relay, and validate the actual SQL connector and
token/refresh behavior. Generic SQL Server service-principal support does not
prove cross-tenant Fabric support. No unattended job is claimed by this template.

Copies require customer-approved PHI minimization, retention, lineage, access,
and export controls before production. Neither staging nor a new capacity is
required merely to query the provider; choose 01 if copies/customer Fabric are
not needed.
