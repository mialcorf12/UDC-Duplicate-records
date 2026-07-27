# Tasks: Duplicate Management Console

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 2,500–3,500 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (data model) → PR 2 (Apex backend) → PR 3 (triggers + controllers) → PR 4 (LWC) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending — confirm before apply |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Data model: 4 custom objects + formula fields + metadata | PR 1 | Standalone; reviewable without code |
| 2 | Apex backend: selectors + utility + services + batch + queueable | PR 2 | Depends on PR 1 (objects must exist) |
| 3 | Triggers + handlers + controllers | PR 3 | Depends on PR 2 (services must exist) |
| 4 | LWC components + flexipage | PR 4 | Depends on PR 3 (controllers must exist) |

---

## Phase 1: Data Model

- [x] 1.1 Create `objects/DuplicateCluster__c/DuplicateCluster__c.object-meta.xml` with auto-number Name `DC-{0000}`
- [x] 1.2 Create fields: `ObjectType__c` (picklist: Contact/Lead/Mixed), `Status__c` (picklist: Open/Ignored/Merged/Partial/Stale), `ClusterScore__c` (Number 5,2), `BlockingKey__c` (Text 255), `DetectedDate__c` (DateTime), `BatchJobId__c` (Text 18)
- [x] 1.3 Create `objects/DuplicateClusterMember__c/DuplicateClusterMember__c.object-meta.xml`
- [x] 1.4 Create fields: `Cluster__c` (Master-Detail → DuplicateCluster__c), `RecordId__c` (Text 18), `ObjectType__c` (picklist: Contact/Lead), `IsMaster__c` (Checkbox), `FieldSnapshotJSON__c` (LongTextArea 131072)
- [x] 1.5 Create roll-up summary `RecordCount__c` on DuplicateCluster__c (COUNT of DuplicateClusterMember__c)
- [x] 1.6 Create `objects/DuplicateIgnore__c/DuplicateIgnore__c.object-meta.xml` + fields: `PairKey__c` (Text 255, ExternalId, Unique), `IgnoredBy__c` (Lookup User), `IgnoredDate__c` (DateTime), `Reason__c` (Text 255)
- [x] 1.7 Create `objects/DuplicateMergeAudit__c/DuplicateMergeAudit__c.object-meta.xml` + fields: `ClusterId__c`, `MasterRecordId__c`, `MergedRecordIds__c`, `Status__c` (Success/Failed), `ErrorMessage__c`, `MergedBy__c`, `MergedDate__c`, `FieldOverridesJSON__c`, `MergeType__c` (SameObject/CrossObject)
- [x] 1.8 Create `objects/Contact/fields/Email_Block__c.field-meta.xml` — Formula: `IF(ISBLANK(Email), "", LOWER(LEFT(Email, FIND("@", Email & "@") - 1)))`
- [x] 1.9 Create `objects/Contact/fields/Phone_Block__c.field-meta.xml` — Formula: `IF(ISBLANK(Phone), "", RIGHT(SUBSTITUTE(...), 7))`
- [x] 1.10 Create `objects/Contact/fields/Name_Block__c.field-meta.xml` — Formula: `LOWER(LEFT(LastName, 3)) & LOWER(LEFT(FirstName, 1))`
- [x] 1.11 Create same three formula fields on `objects/Lead/fields/`
- [x] 1.12 Create `customMetadata/DuplicateSettings__mdt` type + default record (cron expr, score threshold=70, enabled objects)
- [x] 1.13 Create `permissionsets/DuplicateAdmin.permissionset-meta.xml` — CRUD/FLS for all 5 objects + flexipage access

---

## Phase 2: Apex Selectors + Scoring Utility

- [x] 2.1 Create `classes/DuplicateClusterSelector.cls` (with sharing) — `getWithMembers(clusterId)`, `getByMemberRecordIds(ids)`, `getOpenClusters(objectType, status, minScore, pageSize, offset)`
- [x] 2.2 Create `classes/DuplicateClusterSelectorTest.cls` — bulk 200 records, sharing enforcement
- [x] 2.3 Create `classes/DuplicateIgnoreSelector.cls` (with sharing) — `getByPairKeys(Set<String> pairKeys)`
- [x] 2.4 Create `classes/DuplicateIgnoreSelectorTest.cls`
- [x] 2.5 Create `classes/ContactSelector.cls` (with sharing) — `getByBlockKeys(Set<String> keys, String blockField)`, `getByIds(Set<Id> ids)`
- [x] 2.6 Create `classes/ContactSelectorTest.cls`
- [x] 2.7 Create `classes/LeadSelector.cls` (with sharing) — same interface as ContactSelector
- [x] 2.8 Create `classes/LeadSelectorTest.cls`
- [x] 2.9 Create `classes/DuplicateScoringUtil.cls` — `scoreRecords(SObject r1, SObject r2): Decimal` using Jaro-Winkler; weights Email(40)+Phone(30)+Name(20)+Company(10)
- [x] 2.10 Create `classes/DuplicateScoringUtilTest.cls` — test exact match (100), no match (0), partial match (threshold boundary 69/70/85)

---

## Phase 3: Apex Services + Batch + Queueable

- [x] 3.1 Create `classes/DuplicateDetectionBatch.cls` (Batchable, Stateful) — start: `Database.QueryLocator` on all Contacts (`WHERE IsDeleted = false`); execute: group received records by `Email_Block__c` in memory (Stateful accumulator), then query matching Leads per block key, score pairs ≥70, skip ignored pairs, upsert clusters+members; finish: log summary. Note: `SELECT DISTINCT` is NOT supported in QueryLocator — blocking key grouping happens in-memory per execute chunk.
- [x] 3.2 Create `classes/DuplicateDetectionBatchTest.cls` — bulk: 200 contacts + 200 leads; verify cluster creation; verify ignored pair skipped
- [x] 3.3 Create `classes/CrossObjectMergeQueueable.cls` — `execute()`: convertLead → fetch both contacts → apply fieldOverrides → merge → update cluster → insert audit
- [x] 3.4 Create `classes/CrossObjectMergeQueueableTest.cls` — Test.startTest/stopTest; verify converted contact merged; verify audit record Status=Success; verify error path Status=Failed
- [x] 3.5 Create `classes/DuplicateMergeService.cls` — `mergeSameObject(clusterId, masterId, fieldOverrides)` for Contact-Contact and Lead-Lead; `initiateCrossObjectMerge(leadId, contactId, fieldOverrides)` returns jobId
- [x] 3.6 Create `classes/DuplicateMergeServiceTest.cls` — bulk: 3-record cluster; positive merge; error on invalid masterId
- [x] 3.7 Create `classes/DuplicateIgnoreService.cls` — `ignorePair(id1, id2, userId, reason)` upserts DuplicateIgnore__c by PairKey__c; `unignorePair(id1, id2)` deletes it
- [x] 3.8 Create `classes/DuplicateIgnoreServiceTest.cls` — verify idempotent upsert; verify un-ignore

---

## Phase 4: Triggers + Handlers

- [x] 4.1 Create `triggers/ContactDuplicateTrigger.trigger` — after update, delegates to handler
- [x] 4.2 Create `classes/ContactDuplicateTriggerHandler.cls` — `handleAfterUpdate(Map<Id,Contact> oldMap, Map<Id,Contact> newMap)` marks clusters Stale when Email/Phone/FirstName/LastName changes
- [x] 4.3 Create `classes/ContactDuplicateTriggerHandlerTest.cls` — bulk 200 contacts; verify Stale status set; verify no-op when untracked field changes
- [x] 4.4 Create `triggers/LeadDuplicateTrigger.trigger` — after update, delegates to handler
- [x] 4.5 Create `classes/LeadDuplicateTriggerHandler.cls` — same logic as Contact handler for Lead
- [x] 4.6 Create `classes/LeadDuplicateTriggerHandlerTest.cls`

---

## Phase 5: Apex Controllers

- [x] 5.1 Create `classes/DuplicateClusterController.cls` (with sharing, @AuraEnabled) — `getClusterList(objectType, status, minScore, pageSize, pageNumber)` returns `{clusters, totalCount, pageNumber}`; `getClusterDetail(clusterId)` returns `{cluster, members}`
- [x] 5.2 Create `classes/DuplicateClusterControllerTest.cls` — pagination: verify page 1 vs page 2; filter by objectType; sharing enforcement via System.runAs
- [x] 5.3 Create `classes/DuplicateMergeController.cls` (with sharing, @AuraEnabled) — `mergeCluster(clusterId, masterId, fieldOverrides)` returns `{success, jobId, message}`; `ignoreCluster(clusterId, reason)`
- [x] 5.4 Create `classes/DuplicateMergeControllerTest.cls` — same-object merge; cross-object returns jobId; ignore updates cluster status
- [x] 5.5 Create `classes/BatchLaunchController.cls` (with sharing, @AuraEnabled) — `launchDetection()` enqueues batch, returns AsyncApexJob.Id
- [x] 5.6 Create `classes/BatchLaunchControllerTest.cls`
- [x] 5.7 Create `classes/MergeStatusController.cls` (with sharing, @AuraEnabled) — `getJobStatus(jobId)` queries AsyncApexJob + DuplicateMergeAudit__c; returns `{status, message}`
- [x] 5.8 Create `classes/MergeStatusControllerTest.cls`

---

## Phase 6: LWC Components + Flexipage

- [ ] 6.1 Create `lwc/duplicateFieldRow/` — presentational; `@api fieldName`, `@api values[]`; radio group for value selection; emits `fieldoverride` event
- [ ] 6.2 Create `lwc/duplicateClusterListItem/` — presentational; `@api cluster`; renders ObjectType badge, score, record count; emits `clusterselect`
- [ ] 6.3 Create `lwc/duplicateMergeProgress/` — presentational; `@api step` (Detecting/Converting/Merging/Done/Failed); step indicator UI
- [ ] 6.4 Create `lwc/duplicateFieldComparisonTable/` — presentational; `@api members[]`; renders grid of duplicateFieldRow for Email, Phone, Name, Company; emits `fieldoverride` aggregate
- [ ] 6.5 Create `lwc/duplicateFilterBar/` — smart; filter picklists (ObjectType, Status, Score threshold); fires `filterchange` event upstream
- [ ] 6.6 Create `lwc/duplicateClusterList/` — smart; `@wire getClusterList` with reactive filter params; infinite scroll (pageNumber increment); fires `clusterselect`
- [ ] 6.7 Create `lwc/duplicateClusterDetail/` — smart; `@wire getClusterDetail({clusterId: '$selectedClusterId'})`; owns `fieldOverrideMap`; passes members to duplicateFieldComparisonTable
- [ ] 6.8 Create `lwc/duplicateMergeActions/` — smart; calls `mergeCluster` / `ignoreCluster` imperatively; owns polling loop (2s interval, 3 retries max) via recursive `setTimeout` registered in `connectedCallback` and cleared in `disconnectedCallback` — do NOT use `window.setInterval` directly; fires `mergedone` on success
- [ ] 6.9 Create `lwc/duplicateManagementConsole/` — page container; owns `selectedClusterId`; wires duplicateFilterBar → duplicateClusterList → duplicateClusterDetail + duplicateMergeActions in 30/70 layout
- [ ] 6.10 Create `flexipages/DuplicateConsole.flexipage-meta.xml` — Lightning App Page; two-column layout 30/70; assign duplicateManagementConsole component

---

## Verification Checklist (post-apply)

- [ ] V.1 Apex test coverage ≥85% per class (`sf apex run test --code-coverage`)
- [ ] V.2 Batch processes 200 test records without governor limit errors
- [ ] V.3 Same-object Contact-Contact merge transfers activities and campaign members
- [ ] V.4 Cross-object Lead→Contact merge: lead converted, contacts merged, audit record Status=Success
- [ ] V.5 Ignored pair does not reappear after batch re-run
- [ ] V.6 LWC cluster list paginates correctly (page 1 ≠ page 2)
- [ ] V.7 Field override: winning value appears on master record post-merge
- [ ] V.8 Stale trigger: changing Contact.Email marks associated cluster as Stale
