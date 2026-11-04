# Epic Cogito Cloud / Microsoft Fabric cross-tenant architecture

This repository contains architecture research and deployable Azure infrastructure
reference templates for consuming Epic-managed Fabric from a customer tenant.
Epic's actual tenant ownership, feature enrollment, and supported client integration
must be confirmed with Epic; these artifacts do not establish its production design.

Customer and personal identifiers in these artifacts use the fictional placeholders
**ZAVA** and **Sam Cook**. Data-center locations use **Site A** and **Site B**.
PowerPoint and PDF deliverables are sanitized exports; their original
account-identifying rights-management envelopes are not retained.

## Infrastructure combinations

The two independent choices are **customer Azure only vs. customer-owned Fabric**
and **public SQL/TDS vs. workspace-level Private Link**. All four combinations are
implemented, exceeding the minimum of three:

| Combination | Customer infrastructure | Epic data path | Templates |
|---|---|---|---|
| 1. Azure client / public SQL | Private Windows client, Bastion, filtered firewall egress, logs | Entra-authenticated TDS on TCP 1433 | [01-azure-public-sql](infra/01-azure-public-sql/) |
| 2. Azure client / private SQL | Same foundation plus cross-tenant workspace private endpoint and DNS | Approved workspace Private Link; no public SQL egress rule | [02-azure-private-sql](infra/02-azure-private-sql/) |
| 3. Customer Fabric / public SQL | Foundation plus customer F capacity and private, keyless ADLS landing storage | Gateway-host foundation for approved SQL ingestion over public TDS | [03-customer-fabric-public-sql](infra/03-customer-fabric-public-sql/) |
| 4. Customer Fabric / private SQL | Combination 3 plus cross-tenant workspace private endpoint and DNS | Gateway-host foundation for approved ingestion over private TDS | [04-customer-fabric-private-sql](infra/04-customer-fabric-private-sql/) |

Each folder contains Bicep, its generated standalone ARM JSON, example parameters,
and scenario guidance. [Shared components](infra/shared/) include modular networking,
compute, monitoring, storage, Fabric capacity, and **separately deployed** provider
Private Link and post-approval SQL DNS templates.

Start with the [architecture analysis](infra/ARCHITECTURE.md) and
[deployment runbook](infra/README.md). The templates provision Azure infrastructure,
not tenant consent, SQL permissions, Fabric workspaces/items, or a running ingestion
pipeline. Those control/data-plane handoffs are explicit release gates, not hidden
automation or assumed success. No deployment or PHI processing has been performed.

## Visual assets

Diagrams are grouped by topic, with original PNGs and their editable SVG variants
kept together. Filenames and file contents are unchanged.

| Folder | Contents |
|---|---|
| [Cross-tenant access](assets/diagrams/cross-tenant-access/) | Tenant architecture, physical deployment, implementation swimlane, MFA, and Azure-only access diagrams. |
| [Customer Fabric](assets/diagrams/customer-fabric/) | Customer-owned Fabric architecture and implementation diagrams, including the one-page PNG and both SVG variants. |
| [Hybrid connectivity](assets/diagrams/hybrid-connectivity/) | Customer Azure/AWS composite PNG and editable SVG. |
| [Security and PHI](assets/diagrams/security-and-phi/) | Reverse-direction collaboration diagram with PHI controls. |
| [Presentations](assets/presentations/) | Original HIPAA and Fabric cross-tenant access PowerPoint decks. |

PDF references remain at the repository root. The self-contained
[on-premises private-connectivity deck project](OnPrem-Private-Connectivity-Deck/)
remains in its existing folder with its build source and exports.

## Existing architecture evidence

- [Fabric SQL cross-tenant research](Fabric-Cogito-Cross-Tenant-Access.md):
  provider/guest roles, APIs, least-privilege SQL access, and operational caveats.
- [Authorization and MFA](Cross-Tenant-Authorization-and-MFA.md):
  distinction between special Fabric mappings, B2B, human MFA, and workload access.
- [Microsoft validation workshop and test plan](Microsoft-Validation-Workshop-and-Test-Plan.md):
  proposed joint sign-off and synthetic-data acceptance tests.
- [Editable one-page architecture](assets/diagrams/customer-fabric/One-Page-Arch-Epic-Cogito-Fabric-2-Azure-Fabric.svg):
  styled vector redraw of the [original PNG](assets/diagrams/customer-fabric/One-Page-Arch-Epic-Cogito-Fabric-2-Azure-Fabric.png),
  which is retained unchanged.
- [Scout-style one-page architecture, v1](assets/diagrams/customer-fabric/One-Page-Arch-Epic-Cogito-Fabric-2-Azure-Fabric-v1.svg):
  alternate editable infographic inspired by the architecture-and-implementation
  sample, with paired logical/private-access panels and a five-stage overview.
  The original PNG and earlier SVG are retained unchanged.
- [Scout-style customer composite architecture, v1](assets/diagrams/hybrid-connectivity/Customer-Composite-Architecure-Azure-AWS-v1.svg):
  editable Azure/AWS and on-premises overview with five planning cards and the
  source configuration checklist. The [original composite PNG](assets/diagrams/hybrid-connectivity/Customer-Composite-Architecure-Azure-AWS.png)
  is retained unchanged; its Power BI question remains explicitly unconfirmed.
- [SVG/PNG diagram collection](assets/diagrams/) and the readable `cogito-cloud-connectivity (1).pdf`:
  conceptual public/private connectivity, customer Fabric, and hybrid network context.

Some diagrams mix identity mechanisms or imply broader Private Link support than
the evidence establishes. The new analysis reconciles these differences and cites
Microsoft's specific **workspace-level cross-tenant** guidance, rather than applying
tenant-level Private Link restrictions indiscriminately.
