# Exploration: Duplicate Management Console

**Change**: `duplicate-management-console`
**Date**: 2026-06-04
**Stack**: Apex, LWC, SOQL — Salesforce DX API v66.0 (Summer '25)
**State**: Greenfield — `force-app/main/default/` is empty

---

## Current State

The org is a greenfield Salesforce DX project. No existing Apex classes, LWC components, custom objects, or duplicate-handling logic exist. The `sfdx-project.json` targets API v66.0, and `openspec/config.yaml` confirms no test runner is configured yet (strict TDD off). This exploration defines the full architecture from scratch.

---

## Q1 — Custom Objects for Cluster Storage

### Problem
Duplicate detection runs in Batch Apex asynchronously. Results must be persisted so the LWC can query them without re-running the batch. We need two layers: the **cluster** (a group of likely-duplicate records) and its **members** (the individual record references inside that cluster).

### Data Model Design

#### `DuplicateCluster__c` — one record per group
| Field | Type | Purpose |
|---|---|---|
| `Name` (auto-number) | Auto Number | Human-readable ID: `DC-{0000}` |
| `ObjectType__c` | Picklist (`Contact`, `Lead`, `Mixed`) | Drives merge route |
| `Status__c` | Picklist (`Open`, `Ignored`, `Merged`, `Partial`) | Lifecycle state |
| `ClusterScore__c` | Number(5,2) | Aggregate similarity score (0–100) |
| `BlockingKey__c` | Text(255) | The key that brought these records together (debugging/audit) |
| `RecordCount__c` | Number(3,0) | Count of members (2–4); roll-up summary from members |
| `DetectedDate__c` | DateTime | When the batch last touched this cluster |
| `BatchJobId__c` | Text(18) | `AsyncApexJob.Id` for traceability |

#### `DuplicateClusterMember__c` — one record per record-in-cluster
| Field | Type | Purpose |
|---|---|---|
| `Cluster__c` | Master-Detail → `DuplicateCluster__c` | Parent |
| `RecordId__c` | Text(18) | Polymorphic: ContactId or LeadId |
| `ObjectType__c` | Picklist (`Contact`, `Lead`) | Allows mixed clusters |
| `IsMaster__c` | Checkbox | UI pre-selection; updated before merge |
| `IgnoredPairKey__c` | Text(255) | Hash of sorted pair IDs (dedup ignore list) |
| `FieldSnapshotJSON__c` | LongTextArea(131072) | Serialized comparison fields at detection time (for side-by-side view). **Decided fields**: `Email`, `Phone`, `FirstName + LastName`, `Company`. No other fields. |

#### `DuplicateIgnore__c` — permanent ignore registry
| Field | Type | Purpose |
|---|---|---|
| `PairKey__c` | Text(255), ExternalId, Unique | Sorted hash: `min(id1,id2) + '_' + max(id1,id2)` |
| `IgnoredBy__c` | Lookup → User | Audit |
| `IgnoredDate__c` | DateTime | Audit |
| `Reason__c` | Text(255) | Optional user note |

> **Why a separate ignore object?** Storing the ignore state on `DuplicateCluster__c` would be reset every time the batch re-detects. `DuplicateIgnore__c` persists across re-runs and is cheap to query (ExternalId index on `PairKey__c`).

### Architecture Decision
Use **Master-Detail** (not Lookup) for `DuplicateClusterMember__c → DuplicateCluster__c` so that:
- Deleting a cluster cascade-deletes its members (no orphan cleanup needed)
- Roll-up summary fields work natively (`RecordCount__c`)

---

## Q2 — Blocking Key Strategy

### Problem
Comparing every Contact against every Contact is O(n²). At 100K Contacts + 100K Leads that is 10 billion comparisons — completely infeasible in any Apex context. Blocking keys partition the dataset so only records within the same block are compared.

### Three-Layer Blocking Key Strategy

#### Layer 1 — Email domain prefix (strongest signal)
```
email_block = LOWER(LEFT(Email, FIND('@', Email) - 1))
```
Groups: `john.smith@company.com` → `john.smith`
- Handles same-email-different-domain edge cases at Layer 2
- Skips records with no email (fallback to Layer 2/3)

#### Layer 2 — Phone digits normalized
```
phone_block = REGEXP_REPLACE(Phone, '[^0-9]', '').RIGHT(7)
```
Last 7 digits (drops country/area code prefix variation): `+1 (555) 123-4567` → `1234567`

#### Layer 3 — Name prefix key
```
name_block = LOWER(LEFT(LastName, 3)) & LOWER(LEFT(FirstName, 1))
```
Example: `"Smith, John"` → `"smij"`, `"Smithson, Jane"` → `"smij"`.
**Note**: `SOUNDEX()` is NOT a native Salesforce formula function. This simplified prefix approach is deterministic, indexable, and 100% compatible with the Salesforce formula engine. Decided 2026-06-04.

### Composite Key Assignment
Each record is assigned **up to three blocking keys** (one per layer). The batch queries each block separately and only cross-compares records within the same block.

```
block_keys = [email_block, phone_block, name_block]
```

A record appears in 1–3 blocks. Comparison count drops from O(n²) to approximately O(n × avg_block_size), which for typical distributions is O(n × 5–20) — tractable in batch.

### Similarity Scoring (within-block)
Once records are in the same block, compute a weighted score:

| Field | Weight | Algorithm |
|---|---|---|
| Email (exact lowercase) | 40 | 1.0 if match, 0 otherwise |
| Phone (normalized digits) | 30 | Jaro-Winkler on 10-digit string |
| FirstName + LastName | 20 | Jaro-Winkler on concatenated |
| Company/Account | 10 | Exact match |

Score ≥ 70 → candidate pair. Score ≥ 85 → high-confidence cluster.

### SOQL Impact
Each batch chunk queries one object type for one block: `SELECT Id, Email, Phone, FirstName, LastName FROM Contact WHERE Email_Block__c = :key LIMIT 200`. No cross-object SOQL in the same query. Total SOQL per batch execute: well under 100.

> **Formula fields for blocking keys**: Store `Email_Block__c`, `Phone_Block__c`, `Name_Block__c` as **Formula fields** on Contact and Lead, indexed via custom index request if needed. This eliminates in-memory derivation during batch and allows SOQL `WHERE Email_Block__c = :key`.

---

## Q3 — LWC Component Hierarchy

### Design Philosophy
Container–Presentational pattern. Smart containers own data-fetching via `@wire` and imperativeApex calls; dumb presentational components render only what they receive via `@api`.

```
duplicateManagementConsole (page-level container)
├── duplicateFilterBar (smart — owns filter state)
│   └── [picklist filters: ObjectType, Status, Score threshold]
├── duplicateClusterList (smart — wire ClusterListController)
│   └── duplicateClusterListItem (presentational × N)
│       └── [cluster summary: ObjectType badge, record count, score]
└── duplicateClusterDetail (smart — wire ClusterDetailController)
    ├── duplicateFieldComparisonTable (presentational)
    │   └── duplicateFieldRow (presentational × M fields)
    │       └── [radio/checkbox for "winning" value per field]
    ├── duplicateMergeActions (smart — owns merge orchestration)
    │   └── [Merge button, Ignore button, loading spinner]
    └── duplicateMergeProgress (presentational)
        └── [step indicator: Detecting → Converting → Merging → Done]
```

### Key Component Responsibilities

| Component | Type | Responsibility |
|---|---|---|
| `duplicateManagementConsole` | Smart container | Holds selectedClusterId state; wires cluster list; routes detail |
| `duplicateFilterBar` | Smart | Filter picklists; fires `filterchange` event upstream |
| `duplicateClusterList` | Smart | `@wire` `getClusterList`; infinite scroll; selection event |
| `duplicateClusterListItem` | Presentational | Renders one cluster row; emits `clusterselect` |
| `duplicateClusterDetail` | Smart | `@wire` `getClusterDetail(clusterId)`; owns field override map |
| `duplicateFieldComparisonTable` | Presentational | Renders field grid; emits `fieldoverride` events |
| `duplicateFieldRow` | Presentational | One field row; radio group for value selection |
| `duplicateMergeActions` | Smart | Calls `merge`, `ignore`, handles spinner; emits `mergedone` |
| `duplicateMergeProgress` | Presentational | Step progress indicator |

### Communication Pattern
- Parent → Child: `@api` properties
- Child → Parent: `CustomEvent` bubbling
- Sibling coordination: through shared parent (`duplicateManagementConsole`) via event + property update
- No shared service/store pattern needed at this scale

### Navigation
Deploy as a **Lightning App Page** (flexipage) — a single-page console layout with the list on the left (30%) and detail on the right (70%). No routing needed; `selectedClusterId` drives conditional rendering of the detail panel.

---

## Q4 — Cross-Object Merge Flow (Contact vs Lead)

### The Problem
`Database.convertLead()` is a DML operation. Salesforce prohibits mixing callouts and DML in the same transaction. More critically: the convert and the merge are two separate DML operations that MUST happen sequentially — they cannot be batched together safely because the converted Contact ID is unknown until after the convert completes.

### Constraint Analysis
- `Database.convertLead()` → returns `Database.LeadConvertResult` containing the new `contactId`
- `merge` DML on Contact → requires the post-convert Contact ID
- Both must happen in the **same synchronous Apex transaction** (no async needed between them) — they are sequential DML, not concurrent, which is legal
- No callouts involved — no DML+callout conflict
- The concern is governor limit accumulation: convert + merge = 2 DML statements (well within 150 limit)

### Recommended Flow: Single Queueable Chain

```
Step 1 (Synchronous — from LWC Apex controller):
  CrossObjectMergeService.initiate(leadId, contactId, fieldOverrides)
  → validates both records exist, same person
  → enqueues CrossObjectMergeQueueable

Step 2 (Queueable — CrossObjectMergeQueueable.execute()):
  a. Database.convertLead(leadConvert) → get convertedContactId
  b. Fetch both Contacts (original + converted) 
  c. Apply fieldOverrides to master record fields
  d. merge masterContact, List<Contact>{secondaryContact}
  e. Update DuplicateCluster__c Status__c = 'Merged'
  f. Log result to DuplicateMergeAudit__c
```

**Why Queueable over future method?**
- Queueable can be chained (if we ever need a third step)
- Queueable accepts object parameters (pass `fieldOverrides` Map directly)
- Queueable has its own governor limit envelope (100 SOQL, 150 DML fresh start)
- `@future` only accepts primitive types — passing field override maps requires JSON serialization hack

**Why not a Platform Event?**
Overkill for a synchronous user action. Platform Events add delivery latency (seconds) and complicate error surfacing to the UI. Queueable is sufficient and the error can be surfaced via `DuplicateMergeAudit__c` status polling.

### UI Feedback
The LWC calls `initiate()` → gets back a `jobId` (the `AsyncApexJob.Id`). The `duplicateMergeProgress` component polls `MergeStatusController.getJobStatus(jobId)` every 2 seconds (3 retries max) to surface completion or error. On success, it fires `mergedone` which refreshes the cluster list.

---

## Q5 — Batch Apex Chunking Strategy for 200K Records

### Volume Breakdown
- Contacts: 15K → 100K (target)
- Leads: 49K → 100K (target)
- Total: ~200K records across two objects

### Strategy: Two-Pass Blocking Batch

#### Pass 1 — Key Generation Batch (`DuplicateKeyGenerationBatch`)
- Scope: `Database.QueryLocator` on all active Contacts (not converted/deleted), then Leads
- Chunk size: **200 records** (default Batch chunk)
- Per chunk: compute/verify blocking keys on records that don't have them yet (formula fields handle this declaratively — pass 1 becomes optional if all key fields are formula-based)
- SOQL per execute: 1 (the QueryLocator already fetched the chunk)

#### Pass 2 — Comparison Batch (`DuplicateDetectionBatch`)
- Scope: `SELECT DISTINCT Email_Block__c FROM Contact WHERE Email_Block__c != null` → produces a set of distinct block keys
- Chunk: process blocks in sets of 50 per batch execute
- Per execute:
  - SOQL 1: `SELECT Id, ... FROM Contact WHERE Email_Block__c IN :blockKeys`
  - SOQL 2: `SELECT Id, ... FROM Lead WHERE Email_Block__c IN :blockKeys`
  - In-memory comparison of returned records (no additional SOQL in loop)
  - DML: `upsert DuplicateCluster__c[] by Name` + `insert DuplicateClusterMember__c[]`
  - DML count per execute: 2 (well within 150)
  - SOQL count per execute: ≤ 6 (2 per layer × 3 layers) or batched as single IN query

#### Scheduling
- `DuplicateDetectionBatch` scheduled nightly via `System.schedule()` at 02:00 AM
- Configurable via `DuplicateSettings__mdt` (Custom Metadata) — no hardcoded cron
- On demand: LWC "Re-scan" button calls `BatchLaunchController.launchDetection()`

#### Governor Limit Budget per Execute (200 block keys × batch chunk)
| Resource | Used | Limit | Headroom |
|---|---|---|---|
| SOQL queries | 6 | 100 | 94 |
| DML statements | 2 | 150 | 148 |
| Heap (200 Contact + 200 Lead records, ~20 fields) | ~3MB | 12MB | 9MB |
| CPU time | ~2s string ops | 60s | 58s |

### Re-Detection on Record Change
A **trigger on Contact and Lead** (`ContactDuplicateTrigger`, `LeadDuplicateTrigger`) marks affected clusters as `Status__c = 'Stale'` when a tracked field (Email, Phone, FirstName, LastName) changes — without re-running detection inline. The nightly batch then re-evaluates stale clusters.

---

## Affected Areas (Greenfield — all new)

| Path | Purpose |
|---|---|
| `force-app/main/default/classes/` | All Apex classes (batch, service, selector, controller, test) |
| `force-app/main/default/lwc/` | All LWC components (8 components listed above) |
| `force-app/main/default/objects/DuplicateCluster__c/` | Custom object + fields |
| `force-app/main/default/objects/DuplicateClusterMember__c/` | Custom object + fields |
| `force-app/main/default/objects/DuplicateIgnore__c/` | Custom object + fields |
| `force-app/main/default/objects/Contact/fields/` | Blocking key formula fields added to Contact |
| `force-app/main/default/objects/Lead/fields/` | Blocking key formula fields added to Lead |
| `force-app/main/default/customMetadata/` | `DuplicateSettings__mdt` config records |
| `force-app/main/default/permissionsets/` | `DuplicateAdmin.permissionset-meta.xml` |
| `force-app/main/default/flexipages/` | `DuplicateConsole.flexipage-meta.xml` |
| `force-app/main/default/scheduledJobs/` | Scheduled job config (or Custom Metadata) |

---

## Approaches

### Approach 1 — Pre-computed Clusters (Recommended)
Batch Apex runs nightly, stores clusters in custom objects. LWC queries pre-computed data only.

- **Pros**: LWC is fast (simple SOQL, no heavy computation); batch has generous governor limits (async); scales to 200K+ without UI timeout; supports re-scan on demand
- **Cons**: Data is up to 24h stale between batch runs; requires 3 custom objects; more metadata to deploy
- **Effort**: High (one-time build), Low (ongoing)

### Approach 2 — Real-Time Detection in LWC Apex Call
LWC triggers an Apex controller that does live SOQL comparison on-the-fly.

- **Pros**: Always fresh; simpler object model (no cluster storage)
- **Cons**: Hits 50K SOQL row limit immediately at 100K scale; synchronous timeout at >5s; violates governor limits; not viable at target scale
- **Effort**: Low to build, HIGH risk in production

### Approach 3 — Native Salesforce Duplicate Rules + Custom Reporting
Use platform Duplicate Rules (Matching Rules on Contact/Lead) + custom reporting.

- **Pros**: No code for detection; declarative; native `DuplicateRecordSet` / `DuplicateRecordItem` objects
- **Cons**: Rules trigger only on save (not retroactively for existing records); no cross-object Contact/Lead comparison; no field-level merge selection; no Cloudingo-style console — would require building LWC on top of `DuplicateRecordSet` anyway; merge still requires custom Apex
- **Effort**: Low detection, Medium UI, no cross-object merge

---

## Recommendation

**Approach 1 — Pre-computed Clusters** is the only approach that scales to 200K records, respects governor limits, and supports the full feature set (field-level selection, cross-object merge, ignore registry, Cloudingo-style UI).

Native Duplicate Rules (Approach 3) are worth enabling **in addition** as a complementary real-time guard for new records created via UI — but they cannot replace the batch-based retroactive detection for the existing 200K record dataset.

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `FieldSnapshotJSON__c` size exceeds 131072 chars for wide objects | Medium | **Decided**: serialize only `Email`, `Phone`, `Name` (FirstName + LastName concatenated), and `Company` (AccountName for Contact / Company for Lead). No other fields. Enforced at serialization time in batch logic — never serialize the full sObject. |
| Blocking key formula fields not selectively indexed → slow SOQL on 100K records | High | **REQUIRED before go-live**: open a Salesforce Support case requesting a custom index on `Email_Block__c` for both Contact and Lead objects. Formula fields are not indexed by default. At 100K records, an un-indexed WHERE clause on a formula field triggers a full-table scan, exceeding CPU time limits and causing batch failures. This must be in place before any production batch run. Cannot be done from Setup — Support only. |
| Cross-object merge: converted Contact is a duplicate of another Contact already in a cluster | Medium | Post-merge batch step re-evaluates affected clusters and marks them `Stale` |
| Queueable job failure silently swallows merge error without UI feedback | Medium | `DuplicateMergeAudit__c` record captures failure reason; LWC polling reads it and surfaces to user |
| LWC paginating large cluster lists (potentially 10K+ clusters) causes `@wire` timeout | Low–Medium | Server-side pagination via `offset`/`pageSize` parameters in Apex controller; default page = 50 clusters |
| `DuplicateIgnore__c` grows unbounded over months | Low | Add a scheduled cleanup job or archive records > 12 months old via `DuplicateSettings__mdt` config |
| merge DML on Contacts with active CampaignMembers during campaign execution | Low | Salesforce native: CampaignMember re-assignment is automatic on merge; no risk |
| Batch running during peak hours degrades org performance | Low | Schedule at off-peak (02:00 AM); expose schedule config in `DuplicateSettings__mdt` |

---

## Key Architectural Decisions

1. **Formula fields for blocking keys** (not computed in Apex): enables indexed SOQL WHERE clauses and eliminates per-record computation in the batch loop. **Custom index on `Email_Block__c` (Contact + Lead) MUST be requested from Salesforce Support before production deployment.**
2. **Master-Detail on ClusterMember**: enables cascade delete and roll-up counts; simpler than Lookup + manual cleanup
3. **Queueable (not @future) for cross-object merge**: supports rich parameter passing and chaining; cleaner error surfacing
4. **`DuplicateIgnore__c` as a separate object with ExternalId**: survives batch re-runs; O(1) lookup by PairKey; can be bulk-loaded via data tools
5. **`DuplicateMergeAudit__c`** (implied, for merge history): stores who merged what, when, with which master — required for compliance and rollback tracking
6. **`DuplicateSettings__mdt`** for all configuration: schedule cron, score threshold, enabled object types — zero-code admin configuration

---

## Ready for Proposal

**Yes.** The exploration is complete. The five key questions are answered with concrete decisions. The architecture is viable within all stated governor limits.

**Recommended next step**: `sdd-propose` — formalize the scope, rollback plan, and delivery boundaries before moving to spec/design.
