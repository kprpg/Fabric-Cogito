# Deployment runbook

Read [ARCHITECTURE.md](ARCHITECTURE.md) before deployment. These are four separate
reference deployments, not four stacks to deploy into the same resource group.
Use an isolated customer resource group and nonoverlapping private `/16` per
chosen variant. The examples are commercial Azure, synthetic-data pilots.

## Contents and generated ARM

Each numbered directory contains `main.bicep`, `main.json`, and
`parameters.example.json`. Bicep is the source of truth. `main.json` embeds all
nested modules and needs no template storage account, linked URLs, or Bicep at
deployment time. Shared modules also have generated ARM equivalents.
`shared/types.bicep` is a compile-time type library, not a deployable ARM resource.

| Directory | Intended use |
|---|---|
| `01-azure-public-sql` | Query Epic SQL from a customer Azure client, without customer Fabric |
| `02-azure-private-sql` | Same with an approved cross-tenant workspace private endpoint |
| `03-customer-fabric-public-sql` | Customer Fabric analytics foundation with public provider SQL egress |
| `04-customer-fabric-private-sql` | Customer Fabric analytics foundation with private provider SQL access |
| `shared/provider` | Epic-admin deployment of an existing workspace's Private Link service |
| `shared/consumer-sql-dns` | Customer post-approval SQL hostname/private-IP binding |
| `shared/modules` | Reused network, client, monitoring, capacity, storage, and endpoint resources |
| `scripts`, `tests` | Local compiler/parity/parameter validation and architecture contracts |

## Prerequisites and approval

The customer needs Azure deployment rights, an approved VM size and image,
region/SKU availability for Firewall/Bastion/Storage/Fabric, and quota. Register
`Microsoft.Network`, `Microsoft.Compute`, `Microsoft.OperationalInsights`,
`Microsoft.Insights`, and, for 03/04, `Microsoft.Storage` and `Microsoft.Fabric`.
Private variants require registration/re-registration of `Microsoft.Fabric`
in **both participating subscriptions**, including the customer endpoint
subscription, as directed by Microsoft's workspace Private Link setup.
An optional data role assignment requires `Microsoft.Authorization/roleAssignments/write`
(for example, appropriately scoped Role Based Access Control Administrator).

Epic must separately confirm the resource tenant, SQL item type, provider feature
enablement, provider capacity/workspace/region, authentication mechanism, approved
data scope, and public/private posture. Public variants are forbidden if Epic
blocks public SQL access. Private variants require an existing eligible F-capacity
workspace, tenant-level permission to configure workspace inbound network rules,
an Epic workspace admin, and an Epic Azure resource owner for service/approval.

Use the existing [workshop plan](../Microsoft-Validation-Workshop-and-Test-Plan.md)
for identity, MFA, least privilege, offboarding, and existing-session sign-off.
Do not relax CA/MFA or enable SQL passwords to make the pilot pass.

**Cost warning:** every variant creates an always-on Firewall Standard, Bastion
Standard, VM/disk, and logs. 03/04 also start a billable F capacity and ZRS storage.
This is an isolated pilot design, not a cost estimate or a replacement for an
existing shared enterprise hub. Plan lifecycle/teardown before deployment.

## Prepare and validate

Install Azure CLI for deployment and **Bicep 0.38.33** for local compilation.
Use standalone `bicep`, or set `BICEP` to the compiler executable. The optional
GitHub Actions definition at `ci/validate-infra.yml.example` downloads the pinned
Linux compiler and verifies its SHA-256. It is inactive: an administrator with
workflow-management permission can copy it to `.github/workflows/validate-infra.yml`
to enable repository automation.

From the repository root:

```bash
python3 infra/scripts/validate.py
python3 -m unittest discover -s infra/tests -v
```

After Bicep changes, regenerate all ARM equivalents and rerun the checks:

```bash
python3 infra/scripts/validate.py --write
python3 -m unittest discover -s infra/tests -v
```

These are local build/type/lint, ARM parity, example-parameter, and contract checks,
not cloud deployment or authentication tests. The provider workspace Private Link
resource uses Microsoft's exact published ARM contract; Bicep 0.38.33 has no type
metadata for it, so that one diagnostic is locally suppressed with an explanation.
Azure validation is still required for that provider/API combination.

Copy the selected example to `parameters.local.json` in its directory (ignored by
Git), or keep it in an approved private location. Replace every `REPLACE-*`, zero
UUID, example administrator UPN, and sample address/region as appropriate.
`environment.namePrefix` must be 3-12 lowercase letters/digits starting with a
letter; the network must be a private nonoverlapping IPv4 `/16`.

The `adminPassword` example is an **existing Key Vault reference**, never a
plaintext secret. Supply a real Windows-complexity password of at least 12
characters in that vault. The vault must allow ARM template deployment, and the
deployment identity must have the required `Microsoft.KeyVault/vaults/deploy/action`
access; a template reference does not grant it. Do not commit credentials or
change a production vault's network policy just to make this sample work.

For 03/04, set `fabric.administrators` to actual approved customer capacity
administrators and choose the supported capacity region/SKU. Optional
`landingDataPrincipalId` is the **customer directory object ID of an approved
service principal**, not an app/client ID, human/group ID, or Epic mapping object.
Leave it empty until an actual data-transfer identity is approved.

Review `httpsAllowedFqdns` against the current Microsoft endpoint requirements,
gateway region, selected sign-in flow, and package distribution. The examples
are a starting allow list, not a universal guarantee. Add only verified required
destinations, using firewall deny logs for diagnosis. Do not add `*` or arbitrary
public TCP 1433. Public `sqlServiceTags` should cover actual provider regions;
the example global `PowerBI`/`Sql` tags are broader pilot defaults.

## Customer deployment: ARM or Bicep

For example, deploy combination 01 after preparing its real local parameters:

```bash
az login --tenant "$CUSTOMER_TENANT_ID"
az account set --subscription "$CUSTOMER_SUBSCRIPTION_ID"
az account show --query '{tenant:tenantId,subscription:id}' -o json
az group create --name "$CUSTOMER_RG" --location "$LOCATION"

python3 infra/scripts/validate.py \
  --template infra/01-azure-public-sql/main.json \
  --parameters infra/01-azure-public-sql/parameters.local.json

az deployment group validate --resource-group "$CUSTOMER_RG" \
  --template-file infra/01-azure-public-sql/main.json \
  --parameters @infra/01-azure-public-sql/parameters.local.json
az deployment group what-if --resource-group "$CUSTOMER_RG" \
  --template-file infra/01-azure-public-sql/main.json \
  --parameters @infra/01-azure-public-sql/parameters.local.json
az deployment group create --name cogito01 --resource-group "$CUSTOMER_RG" \
  --template-file infra/01-azure-public-sql/main.json \
  --parameters @infra/01-azure-public-sql/parameters.local.json
```

Choose the corresponding folder for another combination. To use Bicep instead,
replace only `--template-file .../main.json` with `.../main.bicep` in Azure commands.
The same JSON parameter file works with both. Verify the Azure CLI-selected Bicep
version or deploy the pinned generated ARM directly to avoid compiler drift.

Inspect the customer output with:

```bash
az deployment group show --resource-group "$CUSTOMER_RG" --name cogito01 \
  --query properties.outputs.connections.value -o json
```

Use the returned Bastion resource to access the private VM through the Azure
portal with authorized Azure management access. No direct public RDP path exists.
Install SSMS/an approved current Entra-capable driver through managed distribution.
The local Windows login does not authorize provider SQL.

## Extra sequence for private variants 02/04

1. **Epic/provider admin:** sign into the Epic tenant/subscription, verify context,
   and deploy `shared/provider/main.json` or `.bicep` with a real existing workspace
   ID. Use the same `validate` / `what-if` / `create` commands in the Epic resource
   group, never the customer identity. Return `privateLinkServiceResourceId`.
2. **Customer admin:** set `providerPrivateLinkServiceId` to that exact output and
   set `privateConnectivityApproved=true` only after design sign-off. Deploy 02/04.
   Deployment creates a **pending manual request**, not permission to query.
3. **Epic admin:** approve the pending endpoint on the provider service. Check the
   connection state on both sides. Do not remove production public access before
   an authorized private pilot is working; then apply the approved workspace
   inbound restriction and verify it takes effect. The customer stack cannot
   enforce an Epic-owned workspace policy.
4. **Provider SQL admin:** retrieve the real connection string using the correct
   Warehouse or SQL endpoint API, with both `guestTenantId` and
   `privateLinkType=Workspace`. Do not derive its hostname from GUIDs or reuse a
   same-tenant/public endpoint. Confirm the intended database/catalog.
5. **Joint DNS/network owners:** inspect the approved endpoint's DNS configuration
   and NIC IP configurations. Match the actual SQL member with provider/Microsoft
   guidance; do not select IP index 0 or copy the example IP. Verify automatic
   Fabric API records in `privatelink.fabric.microsoft.com`.
6. **Customer DNS admin:** prepare `shared/consumer-sql-dns/parameters.local.json`
   with that exact SQL hostname, verified SQL-member IPv4 address, and deployed
   customer VNet ARM ID. Validate the parameter file and deploy the DNS template
   into the customer DNS-owning resource group. It creates a host-specific zone
   with an apex A record. If a central zone already owns that hostname, integrate
   the record there instead of deploying conflicting zones.
7. **Joint pilot owners:** verify DNS, TCP, actual TLS/Entra SQL access, negative
   authorization, provider public blocking, and authentication evidence from the
   real private VM. A successful Azure deployment is not private-path sign-off.

Example network probes from the VM:

```powershell
Resolve-DnsName '<actual-provider-returned-sql-hostname>'
Test-NetConnection -ComputerName '<actual-provider-returned-sql-hostname>' -Port 1433
```

The DNS result must match the verified endpoint SQL IP. Connect with TLS
certificate validation enabled; keep the real hostname, not an IP literal, as the
SQL server. Fail the pilot if it only works with certificate trust bypass.
Forwarding from on-premises/other VNets needs an approved existing DNS resolver and
conditional forwarding; VNet links do not install corporate DNS forwarding.

## Extra sequence for customer Fabric 03/04

The Azure deployment only provides capacity, a gateway-capable Windows host, and
optional private staging storage. It does **not** create a working ingestion job.

Create customer Fabric workspaces, assign the capacity identified by
`customerCapacityName`, and provision
approved Lakehouse/Warehouse/raw/curated items through Fabric. Install/register a
standard-mode on-premises data gateway in the customer tenant if the validated
connector uses it. Secure its recovery key and enable **HTTPS-only gateway relay**
because the egress policy intentionally does not open Service Bus's alternative
AMQP/relay ports. Keep software current through approved distribution.
`customerCapacityId` is an **Azure ARM resource ID**, not the GUID expected by
Fabric workspace assignment APIs. Select the capacity by name in the portal or
resolve its actual Fabric capacity GUID through the authorized customer Fabric API.

Validate the exact organizational-account or other explicitly supported
authentication/refresh model with Epic/Microsoft before creating the connection
and schedule. Do not infer support from a generic SQL Server connector or a
managed identity existing in Azure. The native Warehouse connector is documented
with organizational-account authentication; access to Epic via its item picker
or unattended special SQL mapping is not established by this IaC.

If staging is used, grant its approved customer workload access to the landing
container and use an approved private-reachable connector/gateway. The storage
firewall does not trust arbitrary Fabric SaaS egress, and shared-key-backed SAS fallback
is intentionally disabled. Direct Fabric access to private ADLS requires its own
supported network/identity integration; do not enable public storage as a shortcut.

## Acceptance, operations, and teardown

Use only synthetic data until the root workshop's release gates pass. At minimum:

- Verify the intended tenant, provider enrollment/consent/mapping, item `Read`,
  curated-view SQL permission, generated endpoint, and database/catalog.
- Verify allowed view access and denied base-table/unrelated-item access; inspect
  inherited workspace roles and broad `ReadData`, not just the new narrow grant.
- Capture actual home sign-in resource/CA/MFA/device evidence and provider MFA
  behavior. Test workloads separately from humans; a successful refresh is not MFA.
- For private variants, verify approved endpoint state, private DNS/IP, no public
  SQL fallback, and Epic workspace public-access restriction. Record SQL IP changes
  and revalidate after endpoint replacement.
- Confirm firewall/Bastion/storage logs arrive; collect Entra/Purview/provider
  evidence separately. Apply approved retention, PHI access, alerting, and incident
  response controls before production.
- Measure membership removal, mapping deletion, consent revocation, pooled
  connections, and already-open sessions. Do not assume immediate session kill.
- For 03/04, prove the actual connector/job, gateway network path, private storage
  access, target data scope, recovery, and governance. Until then, ingestion is
  deliberately **not operational**.

Redeploy incrementally with the same prefix/resource group; never use complete
mode or switch a live deployment between variants as an implicit migration.
Conditional resources omitted in a later incremental deployment are not deleted.
Use an explicit reviewed migration to remove old public rules/endpoints/capacities.
Do not deploy these new-VNet templates over an existing enterprise VNet.

For teardown, first revoke only approved pilot grants/mappings and stop scheduled
jobs; preserve required evidence and understand existing-session limits. Remove
the customer endpoint and associated DNS after use ends. The Epic owner separately
removes its service only if no other customer endpoints use it. Delete only the
isolated pilot Azure resources after reviewing retained data/soft deletion.
Customer Fabric workspaces/items and billable capacity lifecycle need explicit
coordination; deleting Azure infrastructure is not consent revocation or an
automatic SaaS/data cleanup policy.
