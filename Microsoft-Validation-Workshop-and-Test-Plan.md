# Microsoft Validation Workshop and Test Plan

## Proposed ZAVA-to-Epic Fabric cross-tenant SQL access

**Prepared:** October 15, 2026.  
**Status:** Research-derived agenda and proposed acceptance plan. **Not Microsoft-approved; no tests executed.**  
**Primary analysis:** [Cross-Tenant Authorization and MFA](./Cross-Tenant-Authorization-and-MFA.md).  
**Diagram:** [Home-tenant enforcement and provider authorization](./04-cross-tenant-mfa-enforcement.svg).

## 1. Meeting objective

Obtain a joint Microsoft Fabric/Entra answer identifying the supported identity/group model, the actual Conditional Access target resources, the mechanism enforcing original-human MFA, and the session/offboarding limits. Agree on and execute a controlled, synthetic-data test plan before broad enablement.

**Proposed roles, to confirm:** ZAVA is the guest/home identity tenant; Epic is the provider/resource tenant. Do not treat these labels or actual use of the Fabric special cross-tenant feature as verified.

## 2. Microsoft escalation route

Suggested private case title:

> Design validation: Fabric Warehouse cross-tenant SQL authentication, mapped groups, and end-to-end Conditional Access/MFA

Open through the applicable organization's established Microsoft support/account route and the official Fabric/Power BI support process, subject to entitlement. Request linked Fabric and Entra expertise, with a named coordinating owner assigned by support. If Cosmos data access is in scope, add Cosmos NoSQL data-plane identity expertise. The Fabric provider-preview form is enrollment, not a substitute for an owned support/design-validation case.[^support][^provider]

No personal Microsoft contact names are asserted here. No ticket or meeting was created.

### Required attendees and accountability

| Owner / attendee | Required contribution |
|---|---|
| ZAVA identity/Conditional Access administrator | Home policies, actual resource/audience evidence, MFA strength, device conditions, pilot user/group lifecycle. |
| ZAVA client/network owner | SSMS/driver/application versions, auth configuration, egress, client/token/pooling behavior. |
| ZAVA data/security owner | Required MFA assurance, approved data scope, evidence handling, and rollout authorization. |
| Epic Fabric administrator / data owner | Feature enrollment, workspace/item IDs, mapping-generated objects, permissions, provider MFA setting, audit visibility. |
| Epic identity owner | Provider-side object model and log evidence; distinguish managed projection objects from B2B guests. |
| Both Microsoft account/support coordinators | Identify the correct specialists on each side; keep one linked case and decision record. |
| Microsoft Fabric DW / SQL analytics endpoint specialist | Cross-tenant mapping and guest SQL authentication, provider MFA gate, item permissions, sessions/revocation. |
| Microsoft Entra CA / External Identities specialist | Supported CA target resources and authentication evidence; whether any B2B-specific control is relevant to this distinct flow. |
| Microsoft Cosmos NoSQL identity specialist, if needed | Supported external-user/token-tenant model, native data roles, client audience, key removal and data-plane CA coverage. |

This is a role-based routing recommendation, not an assertion that a particular Microsoft contact or support entitlement exists.

## 3. Before the meeting

Collect only approved, necessary diagnostics through a private channel:

- Actual feature name and documentation/version used by Epic.
- Guest/provider tenant IDs and provider feature-enablement confirmation.
- Workspace, Warehouse or SQL endpoint IDs; actual connection-string retrieval method.
- Pilot users/groups and relevant directory object IDs; generated provider identity object IDs.
- Supported client/driver versions and explicit authentication mode.
- Relevant home CA policy scope, grant controls, policy state, and exclusions.
- Provider outside-organization MFA setting state and proposed impact.
- One controlled sign-in's UTC time, client/application, resource, relevant policy results, and sanitized error details.
- Existing-session requirements and acceptable offboarding delays.

Do **not** include passwords, secrets, account keys, bearer tokens, PHI, query result sets containing customer data, or a full unfiltered tenant-log export.

## 4. Proposed 75-minute agenda

| Minutes | Topic | Required outcome |
|---:|---|---|
| 0-10 | Identify the actual feature and tenant roles. | Confirm Fabric special mapping versus B2B/shortcut/gateway; provider enablement and owners. |
| 10-20 | Walk one source group through mapping and authorization. | Concrete object/ID diagram; no ambiguous "nesting" shorthand. |
| 20-35 | Walk the approved client through authentication. | Actual resource applications, CA scope, original-human MFA evidence, and provider MFA handling. |
| 35-45 | Review device/session/app-only behavior. | Supported controls, explicit limits, and treatment of noninteractive clients. |
| 45-60 | Agree on controlled tests and evidence. | Owner, environment, expected result, evidence, and rollback for each test. |
| 60-75 | Record decisions and release gates. | Written answers, remaining blockers, escalation owners, and no-go conditions. |

## 5. Questions requiring written answers

### A. Feature and group model

1. Is this exactly the documented Fabric Warehouse `crosstenantauth/mappings` feature, and is the specific provider tenant enabled?
2. For the approved source group, what provider-side SPs/groups does Fabric create? Is any additional provider-owned group used?
3. Does any actual cross-directory nesting occur, or is "nesting" shorthand for mapping/projection and expansion?
4. Which direct/transitive/nested memberships are supported by this specific feature? How are user removals and disabled users handled?
5. Which local object receives item `Read` and SQL view permissions? How is the correct object reliably identified?

The documentation describes managed representations and hourly expansion; it does not establish literal nesting or every transitive-membership case.[^provider]

### B. Authentication and CA/MFA

6. What resource application/audience does each approved TDS client request? Provide the resource application IDs and show them in the actual home sign-in evidence.
7. How does the generic five-resource Fabric CA guidance apply to this external-human mapping flow? Is Power BI-only CA demonstrably insufficient for this client?
8. What exactly does **Enforce multi-factor authentication on access requests from outside the organization** evaluate for the original user?
9. How is that evidence preserved/evaluated when the provider uses a Fabric-managed service-principal representation?
10. Is the provider setting checking an MFA claim, method registration, a particular authentication strength, or something else? What rejects a weak/noncompliant sign-in?
11. Are phishing-resistant strength, device compliance, authentication context, and sign-in frequency supported for this path and client? Which are not?
12. Are any classic B2B inbound MFA/device-trust settings relevant here? If yes, provide feature-specific support guidance instead of assuming B2B behavior.
13. What happens to mapped guest service-principal/app-only access when the organization-wide external MFA setting is enabled?

Guest home CA/MFA and the provider MFA setting are documented; detailed claim/session/application behavior still needs product validation. Generic Fabric CA includes Power BI Service, Azure Data Explorer, Azure SQL Database, Azure Storage, and Azure Cosmos DB.[^guest][^provider][^fabric-ca]

### C. Session and offboarding

14. What is rechecked on a new physical SQL connection, a pooled connection, token refresh, and an already-open TDS session?
15. What does mapping deletion do to an already-open session? Do not answer only for new sign-ins.
16. Which supported operational control terminates existing access during an incident, and what access it cannot revoke?
17. How should the documented consent-revocation and group-expansion delays be accepted or mitigated? What happens after inactive managed identities are reclaimed?
18. Given Fabric's documented CAE non-support, what session-lifetime guarantee can actually be made for this scenario?

Existing sessions are documented as unaffected by consent revocation and the per-user deny toggle. Mapping deletion's existing-session outcome must be established separately.[^guest][^provider][^fabric-ca]

### D. Cosmos, only if it is an actual data path

19. Does the exact Cosmos NoSQL client support a B2B external human/local guest data-role assignment, and which tenant must issue the token?
20. What actual data-plane resource/audience and CA policy result are observable?
21. Are keys still enabled or used? How will management-plane MFA be distinguished from actual data-plane authentication?

Cosmos-native data-plane RBAC and local-authentication controls are documented; this report does not certify the proposed external-human Cosmos path.[^cosmos]

## 6. Pilot safety and change gates

**Design gate before consent/configuration**

- Microsoft, ZAVA, and Epic agree on the test design and supported feature.
- Authorized administrators approve the provider-specific, tenant-level consent action.
- The pilot has one isolated synthetic-data Warehouse, named test identities, and narrow permissions.
- No production CA/MFA policy is disabled to obtain a successful connection.
- No required Fabric Graph permission is removed as a negative test.
- No unrelated tenant is invited, mapped, or probed.
- No load/rate-limit testing or token interception is needed.
- An approved rollback removes the pilot permission/mapping and records the existing-session caveat.

**Pilot authorization is not broad rollout authorization.** A narrow group mapping does not turn tenant-level provider consent into group-scoped consent.[^guest][^provider]

## 7. Test matrix

All tests below are proposals, to be agreed with Microsoft and executed only in the authorized pilot. Exact error codes are asserted only where documented.

| ID | Controlled test | Expected acceptance result | Required evidence | Owner |
|---|---|---|---|---|
| P01 | Before consent, attempt the approved pilot mapping. | Documented guest-not-consented `401`; if consent already exists, do not revoke a production relationship just to run this test. | API outcome and approved environment state. | Provider Fabric admin |
| P02 | Use a pilot user with no approved mapping/membership. | No access to the pilot item; authentication success alone must not authorize it. | SQL result plus mapping/permission inventory. | Provider data owner |
| P03 | Attempt native SQL Authentication against the Fabric endpoint. | Unsupported/denied. | Client auth mode and sanitized error; no real passwords needed. | Client owner |
| P04 | With an applicable enforced MFA policy, use an approved password-only Entra test attempt. | Cannot satisfy the MFA requirement; no policy weakening. | Appropriate user sign-in category, actual resource, CA/authentication failure evidence. | ZAVA identity owner |
| P05 | Use approved MFA-capable interactive SQL client. | Human authenticates; applicable enforced policies succeed; intended view can be queried. | Resource/audience, CA results, Auth Details, SQL view test. | Joint |
| P06 | Use a deliberately noncompliant pilot device when device compliance is required. | Denied by the intended device grant control, not an unrelated network problem. | Device info and specific CA policy failure. | ZAVA identity/client owners |
| P07 | Grant item `Read` without data-object permission. | Connect prerequisite may succeed; view/table read remains denied until explicitly granted. | Effective permissions and SQL result. | Provider data owner |
| P08 | Add view-only `SELECT`; query allowed view and prohibited base table/unrelated item. | View succeeds; prohibited access denied. | Narrow grants, inherited-role check, positive/negative SQL outcomes. | Provider data owner |
| P09 | Validate provider MFA setting behavior with Microsoft-approved pilot controls. | MFA-compliant human accepted; noncompliant case rejected for the intended reason. | Provider setting state, home evidence, provider result. | Provider + Microsoft |
| P10 | Repeat connection with an already-MFA-satisfied session. | No new prompt may be legitimate; evidence still proves the required MFA/policy state. | Token/session state description without token capture, Auth Details. | ZAVA identity/client owners |
| P11 | Remove approved pilot group membership; test new physical connections separately from open/pooled sessions. | Documented hourly expansion behavior understood; no unbounded unexpected access. | UTC timestamps, membership/mapping state, new/open-session outcomes. | Joint |
| P12 | Delete a pilot mapping. | New access stops as documented; stale GET metadata is not mistaken for working access. Existing-session behavior recorded separately. | Delete result, new connection, open-session outcome. | Provider admin |
| P13 | Revoke pilot-only provider consent if safely isolated and approved. | New access lost within documented day-long behavior; existing-session caveat observed. | Guest audit, timing, new/open-session outcomes. | Guest admin |
| P14 | Reconcile human sign-in, provider SP activity, and Purview events. | Evidence chain reviewed without assuming shared correlation IDs or that SP activity proves human MFA. | Approved diagnostic package and Microsoft interpretation. | Joint |
| P15 | Evaluate any service-principal/managed-identity/daemon requirement separately. | Explicitly accepted as workload access or excluded from the human-only rollout; no false human-MFA claim. | Principal type, approved auth mechanism, data grants, access-policy decision. | Security/data owners |
| P16 | If Cosmos is needed, repeat separate management- and data-plane tests with the supported identity path. | Data-role scope, actual CA evaluation, and local-auth posture demonstrated; portal MFA alone insufficient. | Supported path statement, data-plane allow/deny tests, relevant sign-in evidence. | Cosmos SME + identity/data owners |

Test expectations derive from the feature, SQL authentication, granular-permission, logging, and CA references. They are not claims that the deployed environment passed.[^guest][^provider][^fabric-auth][^sql-permissions][^signin][^fabric-ca][^cosmos]

### Evidence worksheet for every test

```text
Test ID:
Approved environment and owner:
UTC start/end:
Client and driver version:
Principal type and approved test identity:
Home/resource tenant context:
Authentication mode:
Application/client and resource/audience:
Policy state: report-only or enforced:
Policy name/result and relevant grant control:
MFA method or earlier-claim satisfaction:
Device-control evidence, if required:
Mapping and effective item/SQL permission state:
New physical, pooled, or already-open SQL session:
Observed allow/deny and sanitized error:
Relevant log references:
Expected versus observed:
Microsoft/support interpretation and case reference:
Open issue or sign-off:
```

Report-only policy results are **not enforcement proof**. CA results establish authentication-policy decisions, not Warehouse object authorization. Provider SP activity establishes activity of that representation, not human MFA by itself.[^signin][^report-only][^provider]

## 8. Release decision

Do not enable broad access until:

- [ ] Actual feature, tenant roles, and provider enrollment are recorded.
- [ ] Group mapping/projection and any additional provider grouping are explained.
- [ ] Each approved client has a documented authentication mode and observed resource/audience.
- [ ] Applicable human CA/MFA and required device controls have enforce-mode positive and negative evidence.
- [ ] Provider MFA behavior and service-principal/app-only handling have written answers.
- [ ] Item/view least privilege and unintended-access denial are demonstrated.
- [ ] Existing-session, membership-removal, and revocation behavior meet approved risk requirements.
- [ ] Network path and any private-only requirement are separately confirmed.
- [ ] Microsoft findings, unresolved limitations, and business acceptance are recorded.
- [ ] ZAVA and Epic identity/data owners approve rollout scope and support ownership.

**No-go conditions:** unclear MFA coverage; reliance on native SQL passwords or Cosmos keys where Entra enforcement is required; app-only reads incorrectly represented as human MFA; assumed literal group nesting; or an offboarding requirement that cannot be met by the observed session controls.

### Required written output from the workshop

An updated diagram, per-client resource/authentication matrix, accepted group-object model, test results and log references, unresolved support-case items, owners/dates, rollback/incident procedure, and explicit rollout decision. A meeting invitation or a screenshot showing "MFA enabled" is not a substitute.

## Sources

[^guest]: Microsoft Learn, [Fabric cross-tenant access for guests](https://learn.microsoft.com/en-us/fabric/enterprise/cross-tenant-access), consent, home-tenant identity/MFA responsibilities, setup, and revocation.
[^provider]: Microsoft Learn, [Fabric cross-tenant access for providers](https://learn.microsoft.com/en-us/fabric/enterprise/cross-tenant-access-for-providers), mapping/group expansion, provider permissions, connection strings, provider MFA setting, governance, and restrictions.
[^fabric-ca]: Microsoft Learn, [Conditional Access in Fabric](https://learn.microsoft.com/en-us/fabric/security/security-conditional-access), target resources, existing Power BI policy guidance, and CAE non-support.
[^fabric-auth]: Microsoft Learn, [Fabric Entra authentication](https://learn.microsoft.com/en-us/fabric/data-warehouse/entra-id-authentication) and [Warehouse connectivity](https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity), authentication modes and SQL Authentication restriction.
[^sql-permissions]: Microsoft Learn, [SQL granular permissions](https://learn.microsoft.com/en-us/fabric/data-warehouse/sql-granular-permissions) and [Share your Warehouse and manage permissions](https://learn.microsoft.com/en-us/fabric/data-warehouse/share-warehouse-manage-permissions), connect-level item access versus data permissions.
[^signin]: Microsoft Learn, [Sign-in log activity details](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/concept-sign-in-log-activity-details) and [Troubleshooting Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/troubleshoot-conditional-access), authentication/policy evidence and audience reporting.
[^report-only]: Microsoft Learn, [Conditional Access report-only mode](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-report-only), evaluation versus enforcement.
[^cosmos]: Microsoft Learn, [Cosmos DB for NoSQL RBAC](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-connect-role-based-access-control) and [Data Explorer](https://learn.microsoft.com/en-us/azure/cosmos-db/data-explorer), native data-plane roles, local authentication, and Entra data-operation mode.
[^support]: Microsoft Learn, [Create a Power BI/Fabric support ticket](https://learn.microsoft.com/en-us/power-bi/support/create-support-ticket), support eligibility and ticket routing.
