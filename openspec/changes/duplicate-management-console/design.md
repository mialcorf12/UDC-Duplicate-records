# Design: Duplicate Management Console

## Technical Approach

Pre-computed batch architecture with three-layer blocking keys (Email, Phone, Name) partitioning 200K+ Contact/Lead records into comparably-sized blocks. Batch Apex runs nightly to populate cluster custom objects. An LWC console (container-presentational) queries pre-computed data. Cross-object merges run in Queueable for governor isolation. All Apex follows strict separation of concerns: Trigger → Handler → Service → Selector.

## Architecture Decisions

| # | Decision | Choice | Alternatives Rejected | Rationale |
|---|----------|--------|-----------------------|-----------|
| 1 | Cross-object merge execution | Queueable | `@future` (primitive-only params), Platform Events (latency, error surfacing) | Rich object params, chainable, fresh governor envelope, direct `AsyncApexJob.Id` for polling |
| 2 | Blocking key storage | Formula fields on Contact/Lead | Apex-computed in batch | Indexable via Support custom index, zero batch CPU cost, always current |
| 3 | ClusterMember relationship | Master-Detail → DuplicateCluster__c | Lookup | Cascade delete (no orphans), native roll-up summary for RecordCount__c |
| 4 | Ignore mechanism | Separate `DuplicateIgnore__c` object with ExternalId `PairKey__c` | Status flag on cluster | Survives batch re-runs, O(1) upsert/lookup, bulk-loadable |
| 5 | Sharing enforcement | `WITH SHARING` on all controllers and selectors | Without sharing | FLS/CRUD enforcement; admin-only console mitigates restrictiveness |
| 6 | Snapshot fields | Email, Phone, FirstName+LastName, Company only | Full sObject serialization | Stays well under 131KB LongTextArea limit; 4 fields ≈ 200 bytes |
| 7 | Custom index on `Email_Block__c` | Required via Salesforce Support before production | No index | Formula fields are not indexed by default; 100K+ records = full-scan timeout |

## Data Flow

### 1. Batch Detection Flow

```
System.schedule (02:00 AM)
    │
    ▼
DuplicateDetectionBatch.start()
    │  QueryLocator: SELECT Id, Email_Block__c, Phone_Block__c, Name_Block__c,
    │                       Email, Phone, FirstName, LastName, AccountName
    │                FROM Contact WHERE IsDeleted = false
    │  Note: SELECT DISTINCT not supported in QueryLocator — group by block key in-memory
    ▼
DuplicateDetectionBatch.execute(chunk[])  ← 200 Contact records/chunk
    │  In-memory: group by Email_Block__c → Map<String, List<Contact>>
    │  SOQL: ContactSelector.getByBlockKey(keys)
    │  SOQL: LeadSelector.getByBlockKey(keys)
    │  In-memory: score pairs (Email 40, Phone 30, Name 20, Company 10)
    │  Filter: score ≥ 70 AND NOT in DuplicateIgnoreSelector.getByPairKeys()
    │  DML: upsert DuplicateCluster__c + insert DuplicateClusterMember__c
    ▼
DuplicateDetectionBatch.finish()
    └── Log batch summary
```

### 2. Same-Object Merge Flow

```
LWC duplicateMergeActions
    │  imperative: DuplicateMergeController.mergeCluster(clusterId, masterId, fieldOverrides)
    ▼
DuplicateMergeService.mergeSameObject(clusterId, masterId, fieldOverrides)
    │  SOQL: DuplicateClusterSelector.getWithMembers(clusterId)
    │  SOQL: ContactSelector.getByIds(memberIds) or LeadSelector
    │  DML: update master (apply overrides)
    │  DML: merge master, secondaries
    │  DML: insert DuplicateMergeAudit__c (Status='Success')
    │  DML: update DuplicateCluster__c Status='Merged'
    ▼
LWC receives response → refreshes cluster list
```

### 3. Cross-Object Merge Flow

```
LWC duplicateMergeActions
    │  imperative: DuplicateMergeController.mergeCluster(clusterId, masterId, fieldOverrides)
    ▼
DuplicateMergeService.initiateCrossObjectMerge(leadId, contactId, fieldOverrides)
    │  Validates both records exist
    │  DML: System.enqueueJob(CrossObjectMergeQueueable)
    │  Returns: AsyncApexJob.Id → LWC
    ▼
CrossObjectMergeQueueable.execute()
    │  a. Database.convertLead(leadConvert) → convertedContactId
    │  b. SOQL: fetch master + converted Contacts
    │  c. DML: update master (apply fieldOverrides)
    │  d. DML: merge masterContact, convertedContact
    │  e. DML: update DuplicateCluster__c Status='Merged'
    │  f. DML: insert DuplicateMergeAudit__c
    ▼
LWC duplicateMergeProgress polls MergeStatusController.getJobStatus(jobId) every 2s × 3 retries
    └── On success: fire mergedone → refresh cluster list
```

### 4. Stale Detection Flow

```
Contact/Lead field change (Email, Phone, FirstName, LastName)
    │
    ▼
ContactDuplicateTrigger / LeadDuplicateTrigger (after update)
    │  Delegates to handler
    ▼
ContactDuplicateTriggerHandler / LeadDuplicateTriggerHandler
    │  SOQL: DuplicateClusterSelector.getClustersByMemberRecordIds(changedIds)
    │  DML: update cluster Status__c = 'Stale'
    ▼
Nightly batch re-evaluates Stale clusters
```

## File Changes

All files are **Create** (greenfield). Base path: `force-app/main/default/`

### Custom Objects & Fields

| File | Description |
|------|-------------|
| `objects/DuplicateCluster__c/DuplicateCluster__c.object-meta.xml` | Cluster header object |
| `objects/DuplicateCluster__c/fields/ObjectType__c.field-meta.xml` | Picklist: Contact, Lead, Mixed |
| `objects/DuplicateCluster__c/fields/Status__c.field-meta.xml` | Picklist: Open, Ignored, Merged, Partial, Stale |
| `objects/DuplicateCluster__c/fields/ClusterScore__c.field-meta.xml` | Number(5,2) |
| `objects/DuplicateCluster__c/fields/BlockingKey__c.field-meta.xml` | Text(255) |
| `objects/DuplicateCluster__c/fields/RecordCount__c.field-meta.xml` | Roll-up summary COUNT from members |
| `objects/DuplicateCluster__c/fields/DetectedDate__c.field-meta.xml` | DateTime |
| `objects/DuplicateCluster__c/fields/BatchJobId__c.field-meta.xml` | Text(18) |
| `objects/DuplicateClusterMember__c/DuplicateClusterMember__c.object-meta.xml` | Member detail object |
| `objects/DuplicateClusterMember__c/fields/Cluster__c.field-meta.xml` | Master-Detail → DuplicateCluster__c |
| `objects/DuplicateClusterMember__c/fields/RecordId__c.field-meta.xml` | Text(18) polymorphic |
| `objects/DuplicateClusterMember__c/fields/ObjectType__c.field-meta.xml` | Picklist: Contact, Lead |
| `objects/DuplicateClusterMember__c/fields/IsMaster__c.field-meta.xml` | Checkbox |
| `objects/DuplicateClusterMember__c/fields/FieldSnapshotJSON__c.field-meta.xml` | LongTextArea(131072) |
| `objects/DuplicateIgnore__c/DuplicateIgnore__c.object-meta.xml` | Ignore registry |
| `objects/DuplicateIgnore__c/fields/PairKey__c.field-meta.xml` | Text(255) ExternalId Unique |
| `objects/DuplicateIgnore__c/fields/IgnoredBy__c.field-meta.xml` | Lookup → User |
| `objects/DuplicateIgnore__c/fields/IgnoredDate__c.field-meta.xml` | DateTime |
| `objects/DuplicateIgnore__c/fields/Reason__c.field-meta.xml` | Text(255) |
| `objects/DuplicateMergeAudit__c/DuplicateMergeAudit__c.object-meta.xml` | Merge audit log |
| `objects/DuplicateMergeAudit__c/fields/ClusterId__c.field-meta.xml` | Lookup → DuplicateCluster__c |
| `objects/DuplicateMergeAudit__c/fields/MasterRecordId__c.field-meta.xml` | Text(18) |
| `objects/DuplicateMergeAudit__c/fields/MergedRecordIds__c.field-meta.xml` | LongTextArea |
| `objects/DuplicateMergeAudit__c/fields/Status__c.field-meta.xml` | Picklist: Success, Failed |
| `objects/DuplicateMergeAudit__c/fields/ErrorMessage__c.field-meta.xml` | LongTextArea |
| `objects/DuplicateMergeAudit__c/fields/MergedBy__c.field-meta.xml` | Lookup → User |
| `objects/DuplicateMergeAudit__c/fields/MergedDate__c.field-meta.xml` | DateTime |
| `objects/DuplicateMergeAudit__c/fields/FieldOverridesJSON__c.field-meta.xml` | LongTextArea |
| `objects/DuplicateMergeAudit__c/fields/MergeType__c.field-meta.xml` | Picklist: SameObject, CrossObject |
| `objects/Contact/fields/Email_Block__c.field-meta.xml` | Formula: `LOWER(LEFT(Email, FIND("@", Email) - 1))` |
| `objects/Contact/fields/Phone_Block__c.field-meta.xml` | Formula: last 7 digits normalized |
| `objects/Contact/fields/Name_Block__c.field-meta.xml` | Formula: `LOWER(LEFT(LastName, 3)) & LOWER(LEFT(FirstName, 1))` — e.g. `"smij"` |
| `objects/Lead/fields/Email_Block__c.field-meta.xml` | Formula: same as Contact |
| `objects/Lead/fields/Phone_Block__c.field-meta.xml` | Formula: same as Contact |
| `objects/Lead/fields/Name_Block__c.field-meta.xml` | Formula: `LOWER(LEFT(LastName, 3)) & LOWER(LEFT(FirstName, 1))` — same as Contact |

### Apex Classes (Production + Test)

| File | Layer | Description |
|------|-------|-------------|
| `classes/DuplicateClusterSelector.cls` | Selector | All DuplicateCluster__c SOQL, with sharing |
| `classes/DuplicateClusterSelectorTest.cls` | Test | |
| `classes/DuplicateIgnoreSelector.cls` | Selector | All DuplicateIgnore__c SOQL, with sharing |
| `classes/DuplicateIgnoreSelectorTest.cls` | Test | |
| `classes/ContactSelector.cls` | Selector | Contact SOQL by block keys / IDs, with sharing |
| `classes/ContactSelectorTest.cls` | Test | |
| `classes/LeadSelector.cls` | Selector | Lead SOQL by block keys / IDs, with sharing |
| `classes/LeadSelectorTest.cls` | Test | |
| `classes/DuplicateMergeService.cls` | Service | Stateless merge orchestration (same + cross-object) |
| `classes/DuplicateMergeServiceTest.cls` | Test | Bulk: 200+ records, positive/negative/exception |
| `classes/DuplicateIgnoreService.cls` | Service | Create/delete ignore pairs, bulkified |
| `classes/DuplicateIgnoreServiceTest.cls` | Test | |
| `classes/DuplicateDetectionBatch.cls` | Batch | Batchable<SObject>, Stateful — detection logic |
| `classes/DuplicateDetectionBatchTest.cls` | Test | Bulk: 200 records, verify cluster creation |
| `classes/CrossObjectMergeQueueable.cls` | Queueable | convertLead + merge in async envelope |
| `classes/CrossObjectMergeQueueableTest.cls` | Test | |
| `classes/ContactDuplicateTriggerHandler.cls` | Handler | Marks clusters Stale on field change |
| `classes/ContactDuplicateTriggerHandlerTest.cls` | Test | |
| `classes/LeadDuplicateTriggerHandler.cls` | Handler | Marks clusters Stale on field change |
| `classes/LeadDuplicateTriggerHandlerTest.cls` | Test | |
| `classes/DuplicateClusterController.cls` | Controller | @AuraEnabled, with sharing — getClusterList, getClusterDetail |
| `classes/DuplicateClusterControllerTest.cls` | Test | |
| `classes/DuplicateMergeController.cls` | Controller | @AuraEnabled — mergeCluster, ignoreCluster |
| `classes/DuplicateMergeControllerTest.cls` | Test | |
| `classes/BatchLaunchController.cls` | Controller | @AuraEnabled — launchDetection |
| `classes/BatchLaunchControllerTest.cls` | Test | |
| `classes/MergeStatusController.cls` | Controller | @AuraEnabled — getJobStatus |
| `classes/MergeStatusControllerTest.cls` | Test | |
| `classes/DuplicateScoringUtil.cls` | Utility | Jaro-Winkler + weighted scoring logic |
| `classes/DuplicateScoringUtilTest.cls` | Test | |

### Triggers

| File | Description |
|------|-------------|
| `triggers/ContactDuplicateTrigger.trigger` | After update — delegates to ContactDuplicateTriggerHandler |
| `triggers/LeadDuplicateTrigger.trigger` | After update — delegates to LeadDuplicateTriggerHandler |

### LWC Components

| File (directory) | Type | Description |
|------------------|------|-------------|
| `lwc/duplicateManagementConsole/` | Smart container | Page-level; owns selectedClusterId, layout |
| `lwc/duplicateFilterBar/` | Smart | Filter picklists, fires filterchange event |
| `lwc/duplicateClusterList/` | Smart | @wire getClusterList, pagination, selection |
| `lwc/duplicateClusterListItem/` | Presentational | One cluster row, emits clusterselect |
| `lwc/duplicateClusterDetail/` | Smart | @wire getClusterDetail, owns fieldOverrideMap |
| `lwc/duplicateFieldComparisonTable/` | Presentational | Side-by-side grid layout |
| `lwc/duplicateFieldRow/` | Presentational | One field row with radio for value selection |
| `lwc/duplicateMergeActions/` | Smart | Merge/Ignore calls, spinner, polling |
| `lwc/duplicateMergeProgress/` | Presentational | Step progress: Detecting→Converting→Merging→Done |

### Metadata & Configuration

| File | Description |
|------|-------------|
| `customMetadata/DuplicateSettings__mdt.DuplicateSettings__mdt-meta.xml` | Custom metadata type definition |
| `customMetadata/DuplicateSettings__mdt.Default.md-meta.xml` | Default config record (cron, threshold, enabled objects) |
| `permissionsets/DuplicateAdmin.permissionset-meta.xml` | CRUD/FLS for all 5 custom objects + LWC page access |
| `flexipages/DuplicateConsole.flexipage-meta.xml` | Lightning App Page — list 30% / detail 70% layout |

**Total: 35 object/field metadata files, 32 Apex classes (16 prod + 16 test), 2 triggers, 9 LWC components, 4 config metadata files = 82 files**

## Interfaces / Contracts

```apex
// ── Controllers ──

public with sharing class DuplicateClusterController {
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getClusterList(
        String objectType,    // 'Contact' | 'Lead' | 'Mixed' | null (all)
        String status,        // 'Open' | 'Stale' | null (all)
        Decimal minScore,     // 0–100, default 0
        Integer pageSize,     // default 50
        Integer pageNumber    // 1-based
    );
    // Returns: { clusters: List<DuplicateCluster__c>, totalCount: Integer, pageNumber: Integer }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getClusterDetail(String clusterId);
    // Returns: { cluster: DuplicateCluster__c, members: List<DuplicateClusterMember__c> }
}

public with sharing class DuplicateMergeController {
    @AuraEnabled
    public static Map<String, Object> mergeCluster(
        String clusterId,
        String masterId,
        Map<String, String> fieldOverrides  // field API name → winning value
    );
    // Returns: { success: Boolean, jobId: String (for cross-object), message: String }

    @AuraEnabled
    public static void ignoreCluster(String clusterId, String reason);
}

public with sharing class BatchLaunchController {
    @AuraEnabled
    public static String launchDetection();
    // Returns: AsyncApexJob.Id
}

public with sharing class MergeStatusController {
    @AuraEnabled
    public static Map<String, Object> getJobStatus(String jobId);
    // Returns: { status: String ('Queued'|'Processing'|'Completed'|'Failed'), message: String }
}
```

```javascript
// ── LWC Wire Adapters ──

// duplicateClusterList.js
@wire(getClusterList, { objectType: '$objectType', status: '$status',
    minScore: '$minScore', pageSize: '$pageSize', pageNumber: '$pageNumber' })
wiredClusters;

// duplicateClusterDetail.js
@wire(getClusterDetail, { clusterId: '$selectedClusterId' })
wiredClusterDetail;
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit (Apex) | Selectors return correct records; Services bulkify; Scoring algorithm accuracy; Controller param validation | @isTest classes, `System.runAs()` for sharing, `Test.startTest()/stopTest()` for async, 200+ record bulk tests |
| Unit (LWC) | Presentational components render correctly; Event dispatch; Field override map assembly | Jest with `@salesforce/sfdx-lwc-jest`, wire mocks via `@wire` test utility |
| Integration (Apex) | Batch creates clusters from test data; Queueable convert+merge completes; Trigger marks stale | @isTest with `Test.startTest()/stopTest()`, verify DML results and cluster state |
| E2E | Not configured | Manual validation in scratch org (strict_tdd: false) |

**Coverage target**: ≥85% per class (Salesforce org-wide requirement).

## Migration / Rollout

No data migration required — greenfield deployment. Rollout plan:

1. **Deploy metadata**: objects → fields → Apex classes → triggers → LWC → flexipage → permission set
2. **Request custom index**: Salesforce Support case for `Email_Block__c` on Contact and Lead (BLOCKING — must complete before step 4)
3. **Assign permission set**: `DuplicateAdmin` to admin users
4. **Run initial batch**: `BatchLaunchController.launchDetection()` in UAT, validate clusters
5. **Schedule nightly**: Configure cron in `DuplicateSettings__mdt`
6. **Production**: repeat steps 1–5 after UAT sign-off

**Rollback**: destructive changes XML removing all custom objects, classes, triggers, LWC. Merges are irreversible — dry-run in UAT first.

## Open Questions

- [x] ~~Salesforce formula field limitation: `SOUNDEX()` is not a native formula function.~~ **DECIDED**: `Name_Block__c` uses `LOWER(LEFT(LastName, 3)) & LOWER(LEFT(FirstName, 1))`. Example: `"Smith, John"` → `"smij"`. Simple, deterministic, indexable, 100% compatible with Salesforce formula engine.
- [ ] Custom index on `Email_Block__c`: timeline depends on Salesforce Support SLA. Should be requested as soon as objects are deployed to production sandbox.
