# USER STORY: Duplicate Management Console for Contacts & Leads

## Title
```
Implement Duplicate Management Console — Cross-Object Contact/Lead Clustering & Resolution
```

---

## Description

### Background
Data quality is critical for Sales and Service operations. Our Salesforce org has 45K Leads and 15K Contacts with significant duplicate overlap. Manual identification and resolution is time-consuming and error-prone. We need a centralized, scalable console to detect, compare, and intelligently merge duplicates across Contact and Lead objects while maintaining data integrity and audit trails.

### What We're Building
A Lightning Web Component (LWC)-based **Duplicate Management Console** that:
- **Detects** duplicate clusters automatically via batch processing (3-layer blocking keys: Email, Phone, Name)
- **Visualizes** clusters in a Cloudingo-style UI (list + detail comparison)
- **Merges** duplicates intelligently (same-object and cross-object Lead→Contact)
- **Ignores** pair combinations persistently (survives batch re-runs)
- **Archives** resolved clusters to keep the console focused

### Success Looks Like
- Data admins can review a cluster in 10 seconds
- A batch merge of 100+ duplicates completes in < 2 minutes
- No duplicate pairs reappear after being marked ignored
- Every merge is audited with before/after field values and user context
- Console is responsive at 60K+ total records

---

## Story Points: 13

---

## Acceptance Criteria (as Subtasks)

---

## Subtask 1: Batch Detects Contacts with Matching Email Blocking Key

**Title**
```
Batch detects duplicate Contacts grouped by Email_Block__c
```

**Description**
When the DuplicateDetectionBatch runs nightly, it should query all Contacts, group them by their Email_Block__c formula field, and create DuplicateCluster__c records for groups with 2+ members that score ≥70 points.

**Background**
Email is the strongest signal for duplicate detection. A blocking key (normalized email prefix) allows us to efficiently partition 15K Contacts into comparable-sized groups without O(N²) comparisons. This is Phase 1 of the three-layer detection strategy (Email → Phone → Name).

**Acceptance Criteria**
```gherkin
Scenario: Batch creates clusters for Contacts with matching email blocks
  Given 100 test Contacts exist with 10 unique Email_Block__c values
  And 8 Contacts share Email_Block__c = "john_d" (email domain = "example.com")
  When DuplicateDetectionBatch executes with these Contacts in scope
  Then a DuplicateCluster__c is created with:
    - ObjectType__c = 'Contact'
    - Status__c = 'Open'
    - BlockingKey__c = "john_d"
    - RecordCount__c = 8 (roll-up summary)
    - ClusterScore__c ≥ 70
  And DuplicateClusterMember__c records are inserted (one per Contact)
  And each member contains FieldSnapshotJSON__c with Email, Phone, FirstName, LastName, Company

Scenario: Clusters with score < 70 are not created
  Given 3 Contacts share same Email_Block__c but:
    - Contact A: Email matches, Phone different, Name different
    - Contact B: Email matches, Phone different, Name different
    - Contact C: Email matches, Phone different, Name different
  When DuplicateDetectionBatch scores the pairs
  Then total score < 70 (Email 40 + Phone 0 + Name 0 = 40)
  And NO cluster is created for this group

Scenario: Single-member groups are ignored
  Given 1 Contact with unique Email_Block__c = "unique_xyz"
  When DuplicateDetectionBatch processes Contacts
  Then no cluster is created (minimum 2 members required)
```

**Story Points: 2**

---

## Subtask 2: Batch Detects Cross-Object Duplicates (Contact vs Lead)

**Title**
```
Batch detects and clusters cross-object duplicates (Contact-Lead pairs)
```

**Description**
After grouping same-object Contacts and Leads separately, the batch should cross-reference blocking keys to find Contacts and Leads that share the same Email_Block__c. These mixed pairs should create clusters with ObjectType__c = 'Mixed'.

**Background**
A Contact and Lead with the same email represent a high-value duplicate (prospects converting to customers, or data entry error). Cross-object merges (Lead → Contact via convertLead) are more complex but critical for data consolidation. The batch must detect these intelligently to surface them to admins.

**Acceptance Criteria**
```gherkin
Scenario: Batch creates Mixed clusters for Contact-Lead pairs
  Given 50 Contacts and 50 Leads exist
  And Contact "Alice Smith" has Email="alice@example.com" (Email_Block__c = "alice")
  And Lead "Alice Smith" has Email="alice@example.com" (Email_Block__c = "alice")
  When DuplicateDetectionBatch executes
  Then a DuplicateCluster__c is created with:
    - ObjectType__c = 'Mixed'
    - Status__c = 'Open'
    - BlockingKey__c = "alice"
    - RecordCount__c = 2 (1 Contact + 1 Lead)
    - ClusterScore__c ≥ 70
  And members include one Contact and one Lead

Scenario: Multiple Contact-Lead pairs in same blocking key create one cluster
  Given Email_Block__c = "sales" contains:
    - Contact "Sales Admin 1"
    - Contact "Sales Admin 2"
    - Lead "Sales Manager"
  When DuplicateDetectionBatch executes
  Then one cluster is created with ObjectType__c = 'Mixed'
  And all 3 records are members
  And RecordCount__c = 3

Scenario: Same-object pairs are separate from cross-object pairs
  Given Email_Block__c = "john" contains:
    - Contact "John Doe"
    - Contact "John Smith" (duplicate Contact)
    - Lead "John Manager" (duplicate Lead)
  When DuplicateDetectionBatch executes
  Then TWO clusters are created:
    - Cluster 1: ObjectType__c = 'Contact', members = [Contact Doe, Contact Smith]
    - Cluster 2: ObjectType__c = 'Mixed', members = [Contact Doe, Contact Smith, Lead Manager] OR [Contact Doe OR Smith, Lead Manager]
  (Note: exact logic depends on current implementation; verify with actual batch behavior)
```

**Story Points: 2**

---

## Subtask 3: Ignored Pairs Never Reappear in Batch Runs

**Title**
```
Batch skips pair combinations marked in DuplicateIgnore__c
```

**Description**
Before creating a cluster, the batch should check the DuplicateIgnore__c object for any existing pair keys. If a pair (Contact_A, Lead_B) is marked ignored, that specific combination should not be re-clustered in subsequent batch runs.

**Background**
Data admins may review a pair and decide it's NOT a true duplicate (false positive from scoring algorithm). The ignore mechanism must be permanent and survive nightly batch re-runs — otherwise admins are forced to ignore the same pair repeatedly, causing frustration and data churn.

**Acceptance Criteria**
```gherkin
Scenario: Batch skips ignored pair
  Given DuplicateIgnore__c contains a record:
    - PairKey__c = "001xx_00Lxx" (Contact_Id + "_" + Lead_Id, order-independent)
    - IgnoredDate__c = [today]
    - IgnoredBy__c = [Data Admin]
    - Reason__c = "False positive: different companies"
  When DuplicateDetectionBatch executes
  Then that Contact-Lead pair is NOT included in any cluster
  And no DuplicateCluster__c is created for this pair

Scenario: Pair key is order-independent
  Given a pair (Contact "A", Lead "B") was ignored with PairKey = "min(A,B)_max(A,B)"
  When the batch evaluates (Lead "B", Contact "A") in reverse order
  Then the same PairKey matches
  And the pair is skipped

Scenario: Un-ignore restores pair detection
  Given a pair was ignored with DuplicateIgnore__c record
  When an admin deletes the DuplicateIgnore__c record
  And the next batch runs
  Then that pair is re-detected and re-clustered (if score ≥ 70)
```

**Story Points: 1**

---

## Subtask 4: Cluster List Filters by ObjectType, Status, and Score

**Title**
```
Console list view filters clusters by ObjectType, Status, and minimum score
```

**Description**
The duplicateClusterList LWC should accept filter parameters (ObjectType, Status, minScore) and display only matching clusters in a paginated list (50 per page). Changing filters should reset pagination.

**Background**
With 60K records generating thousands of clusters, admins need to focus on high-confidence duplicates first. Filtering by Contact-only, Lead-only, or Mixed clusters; by Open, Ignored, or Merged status; and by score threshold (e.g., ≥90) allows prioritization and faster decision-making.

**Acceptance Criteria**
```gherkin
Scenario: Admin filters clusters by ObjectType
  Given 1000 clusters exist (600 Contact, 300 Lead, 100 Mixed)
  When admin selects ObjectType='Contact'
  Then list shows only 600 Contact-only clusters
  And pagination resets to page 1

Scenario: Admin filters clusters by Status
  Given 1000 clusters (700 Open, 200 Ignored, 100 Merged)
  When admin selects Status='Open'
  Then list shows only 700 Open clusters
  And pagination resets to page 1

Scenario: Admin filters clusters by minimum score
  Given 1000 clusters with scores ranging 70–100
  When admin sets minScore=85
  Then list shows only clusters with ClusterScore__c ≥ 85
  And pagination resets to page 1

Scenario: Combined filters
  Given 1000 clusters
  When admin applies ObjectType='Contact' + Status='Open' + minScore=90
  Then list shows only Contact-only, Open clusters with score ≥ 90
  And count reflects intersection

Scenario: Pagination resets on filter change
  Given admin is on page 5 of filtered results
  When admin changes any filter
  Then pagination resets to page 1
  And new filter is applied
```

**Story Points: 2**

---

## Subtask 5: Cluster Detail Pane Shows Side-by-Side Field Comparison

**Title**
```
Detail pane displays selected cluster members with side-by-side field comparison
```

**Description**
When an admin selects a cluster from the list, the detail pane should render all members with their key fields (Email, Phone, FirstName+LastName, Company) in a side-by-side table. Admin can see field differences at a glance and select winning values for merge.

**Background**
Comparing duplicates is the core decision-making task. A Cloudingo-style layout (Email side-by-side, Phone side-by-side, etc.) reduces cognitive load and speeds up decisions. Admins should spot mismatches (e.g., "Contact A has email, Contact B doesn't") and pick the correct value before merge.

**Acceptance Criteria**
```gherkin
Scenario: Detail pane renders cluster members
  Given a cluster with 3 members (2 Contacts, 1 Lead)
  When admin clicks the cluster in the list
  Then detail pane shows:
    - Cluster name/ID
    - ObjectType, Status, Score, CreatedDate
    - Member table with columns: [Record ID, Record Name, Email, Phone, Name, Company]
    - One row per member

Scenario: Admin can view and select field values for merge
  Given the detail pane is open for a 3-member cluster
  When admin examines the Email column
  Then admin can see:
    - Contact A: alice@example.com
    - Contact B: alice.smith@example.com
    - Lead C: (blank)
  And admin can select which email to use on the merged record (radio button per field)

Scenario: Field snapshot data is readable
  Given FieldSnapshotJSON__c contains serialized data (Email, Phone, FirstName, LastName, Company)
  When detail pane renders
  Then JSON is deserialized and displayed in human-readable format
  And no raw JSON is shown to user

Scenario: Field override map is assembled
  Given admin selects winning values (e.g., Email from Contact A, Phone from Contact B)
  When admin clicks "Merge"
  Then fieldOverrideMap = { Email: 'alice@example.com', Phone: '555-1234', ... }
  And map is passed to merge controller
```

**Story Points: 2**

---

## Subtask 6: Merge Same-Object Duplicates (Contact-Contact or Lead-Lead)

**Title**
```
Admin can merge duplicate Contacts or Leads with field override selection
```

**Description**
When a cluster contains same-object duplicates (e.g., two Contacts), admin should be able to select a master record and apply field overrides. The merge should execute using Salesforce native Database.merge, update the cluster status, and insert an audit record.

**Background**
Same-object merges are simpler than cross-object (no convertLead needed). They allow Salesforce to handle the merge operation natively, transferring child records (Activities, Tasks, Events) automatically. Audit trail captures the merge decision for compliance and debugging.

**Acceptance Criteria**
```gherkin
Scenario: Admin merges two Contacts with field overrides
  Given a cluster with 2 Contacts selected as master/secondary
  And admin selects Email from Contact A, Phone from Contact B
  When admin clicks "Merge"
  Then DuplicateMergeService.mergeSameObject() executes:
    1. Update Contact A (master) with overrides: Email = contact_a_email, Phone = contact_b_phone
    2. Database.merge(Contact A, Contact B)  ← Salesforce native merge
    3. Update DuplicateCluster__c status = 'Merged'
    4. Insert DuplicateMergeAudit__c with Status='Success'
  And child records (Activities, Tasks, Opportunities) transfer to Contact A
  And Contact B is deleted (merged)

Scenario: Merge fails and is audited
  Given a merge attempt fails (e.g., validation rule on Contact A)
  When DuplicateMergeService catches exception
  Then DuplicateMergeAudit__c is inserted with:
    - Status__c = 'Failed'
    - ErrorMessage__c = [validation rule message]
    - Both Contact A and B remain unchanged
  And UI shows error toast

Scenario: Audit record contains complete merge metadata
  Given a successful same-object merge
  When DuplicateMergeAudit__c is inserted
  Then record includes:
    - ClusterId (lookup)
    - MasterRecordId (Contact A Id)
    - MergedRecordIds (Contact B Id, serialized)
    - Status = 'Success'
    - MergedBy (current user)
    - MergedDate (now)
    - FieldOverridesJSON (Email, Phone, etc. mapping)
    - MergeType = 'SameObject'
```

**Story Points: 3**

---

## Subtask 7: Merge Cross-Object Duplicates (Lead → Contact)

**Title**
```
Admin can convert and merge a Lead into a Contact asynchronously
```

**Description**
When a cluster contains a Lead and Contact (Mixed cluster), admin should select the Contact as master. The system should enqueue a Queueable job that: (1) converts the Lead to Contact, (2) merges the converted Contact into the master, (3) updates cluster status, and (4) inserts audit record. The LWC should poll for job completion.

**Background**
Lead-to-Contact conversion is more complex than same-object merge because Salesforce's convertLead() function creates a new Contact, changes Lead status, and optionally creates an Account. This must happen before merge. Async (Queueable) execution isolates the operation and allows polling without blocking the UI.

**Acceptance Criteria**
```gherkin
Scenario: Admin initiates cross-object merge (Lead → Contact)
  Given a Mixed cluster with 1 Lead and 1 Contact
  And admin selects Contact as master
  When admin clicks "Merge"
  Then DuplicateMergeService.initiateCrossObjectMerge() executes:
    1. Validate both Contact and Lead exist
    2. Enqueue CrossObjectMergeQueueable with both IDs
    3. Return AsyncApexJob.Id to LWC
  And LWC begins polling getJobStatus(jobId) every 2s

Scenario: Queueable converts and merges sequentially
  Given CrossObjectMergeQueueable is enqueued
  When execute() runs
  Then steps execute in order:
    1. Database.convertLead(leadConvert) → new Contact created
    2. Fetch master Contact + converted Contact
    3. Update master with field overrides
    4. Database.merge(masterContact, convertedContact)
    5. Update DuplicateCluster__c status = 'Merged'
    6. Insert DuplicateMergeAudit__c with Status = 'Success'
  And Lead status changes to 'Converted'
  And converted Contact is merged into master

Scenario: Polling detects job completion
  Given LWC is polling every 2s with max 3 retries
  When getJobStatus() returns status = 'Completed'
  Then polling stops
  And UI shows success toast
  And cluster list refreshes
  And "mergedone" event is fired

Scenario: Merge failure is captured
  Given merge step fails (e.g., both records have required field, conflict)
  When CrossObjectMergeQueueable catches exception
  Then DuplicateMergeAudit__c is inserted with Status='Failed'
  And ErrorMessage contains error details
  And Lead remains unconverted (implicit rollback)
  And UI shows error toast after polling timeout

Scenario: Audit record links job ID for traceability
  Given a successful cross-object merge
  When DuplicateMergeAudit__c is inserted
  Then record includes:
    - JobId__c = [AsyncApexJob.Id from queueable context]
    - MergeType = 'CrossObject'
    - All other fields same as same-object merge
```

**Story Points: 3**

---

## Subtask 8: Admin Can Permanently Ignore Pair Combinations

**Title**
```
Admin marks duplicate pairs as ignored (false positives)
```

**Description**
If a pair is a false positive (e.g., two unrelated people with same name), admin should be able to click "Ignore" on that pair. This creates a DuplicateIgnore__c record with an order-independent pair key. The pair will never be re-clustered in future batch runs.

**Background**
Scoring algorithms have false positive rates. Admins need a fast way to exclude incorrect pairs without deleting the cluster or merging. Ignore pairs must be persistent and survive batch re-runs — otherwise the UI becomes cluttered with the same false positives repeatedly.

**Acceptance Criteria**
```gherkin
Scenario: Admin ignores a pair via cluster detail pane
  Given a cluster with pairs (Contact A, Contact B) and (Contact A, Contact C)
  When admin clicks "Ignore" on pair (A, B)
  Then DuplicateIgnore__c is upserted with:
    - PairKey__c = "min(A_id, B_id)_max(A_id, B_id)" (order-independent)
    - IgnoredBy__c = [current user]
    - IgnoredDate__c = [now]
    - Reason__c = [optional text from admin]
  And DuplicateCluster__c status updates to 'Ignored'
  And UI shows success toast

Scenario: Pair key is order-independent (idempotent)
  Given Contact IDs "001xx" and "001yy"
  When admin ignores pair (001xx, 001yy)
  Then PairKey__c = "001xx_001yy"
  When admin later ignores pair (001yy, 001xx) by mistake
  Then upsert by PairKey finds existing record (no duplicate)

Scenario: Ignored pair doesn't reappear in batch
  Given DuplicateIgnore__c contains pair (Contact A, Contact B)
  When DuplicateDetectionBatch runs next cycle
  Then DuplicateIgnoreSelector.getByPairKeys() filters that pair
  And no cluster is created for (A, B)
  And cluster remains 'Ignored'

Scenario: Admin can un-ignore a pair
  Given a DuplicateIgnore__c record exists
  When admin clicks "Un-ignore" or deletes the record
  Then next batch run will re-detect and re-cluster the pair (if score ≥ 70)
```

**Story Points: 2**

---

## Subtask 9: Bulk Merge Action (Multiple Clusters at Score Threshold)

**Title**
```
Admin can bulk-merge clusters above a score threshold
```

**Description**
Data admins should be able to set a minScore threshold (e.g., 90) and object type (e.g., Contact-only), then click "Bulk Merge" to enqueue BulkMergeBatch. The batch will process clusters asynchronously, creating audit records for each merge.

**Background**
Manual merge of hundreds of high-confidence duplicates is tedious and error-prone. Bulk merge allows automation of confident decisions, freeing admins to focus on edge cases and validation. Each merge must still be audited for compliance.

**Acceptance Criteria**
```gherkin
Scenario: Admin initiates bulk merge
  Given console displays 1000 clusters
  And 200 of them are Contact-only with score ≥ 90
  When admin sets minScore=90, objectType='Contact'
  And clicks "Bulk Merge"
  Then BulkMergeBatch is enqueued with parameters { minScore: 90, objectType: 'Contact' }
  And console shows job ID
  And spinner appears during processing

Scenario: Batch processes clusters without merging mixed or ignored
  Given 200 qualifying clusters enqueued
  When BulkMergeBatch.execute(scope) runs
  Then only Contact-only clusters with score ≥ 90 are processed
  And Mixed clusters are skipped
  And Ignored clusters are skipped
  And batch scope = 200 clusters per chunk

Scenario: Each merge creates an audit record
  Given 50 clusters in batch scope
  When batch merges them
  Then 50 DuplicateMergeAudit__c records are inserted
  And each has Status='Success' or 'Failed'
  And each is linked to original cluster

Scenario: Admin sees completion message
  When batch finishes
  Then console shows toast: "[count] clusters merged successfully"
  And cluster list refreshes (merged clusters disappear)
```

**Story Points: 2**

---

## Subtask 10: Archive Resolved Clusters

**Title**
```
Admin can archive clusters marked as Merged or Ignored
```

**Description**
Once a cluster is resolved (merged or ignored), it clogs the console. Admin should be able to select an archive date and click "Archive" to move resolved clusters to an Archived status, removing them from the Open view.

**Background**
The console's primary purpose is to surface unresolved duplicates. After 100+ merges/ignores, the list becomes long and unfocused. Archival keeps the console lightweight and action-focused without deleting audit history.

**Acceptance Criteria**
```gherkin
Scenario: Admin selects archive date and archives clusters
  Given 1000 clusters total (700 Open, 200 Merged, 100 Ignored)
  And admin wants to archive Merged/Ignored clusters created before 2026-06-01
  When admin selects archiveDate='2026-06-01'
  And clicks "Archive"
  Then archiveClustersByDate() updates all clusters with CreatedDate__c < archiveDate AND Status in (Merged, Ignored)
  And their Status__c becomes 'Archived'
  And count = [number archived]

Scenario: Archived clusters disappear from list view
  Given 200 clusters were archived
  When console list refreshes (Status='Open' filter applied)
  Then only 700 Open clusters are shown
  And archived clusters no longer appear

Scenario: Archive date options are populated
  Given console loads
  When getArchivableDates() is called
  Then dropdown shows dates of oldest Merged/Ignored clusters
  And default is most recent date

Scenario: Archive can be undone (reverting status)
  Given clusters were archived
  When admin manually updates DuplicateCluster__c Status='Open'
  Then cluster reappears in list on next refresh
```

**Story Points: 1**

---

## Subtask 11: Stale Detection — Mark Clusters When Members Change

**Title**
```
Trigger marks clusters as Stale when member Contact/Lead fields change
```

**Description**
If a Contact or Lead in a cluster has its Email, Phone, or Name updated, the cluster should be marked as Stale. This signals to admins that the cluster's comparison data is outdated and should be re-evaluated in the next batch run.

**Background**
Duplicate scores and blocking keys are computed at batch time. If a Contact's email changes after clustering, the score may no longer be valid. Stale detection ensures admins don't merge based on outdated field data.

**Acceptance Criteria**
```gherkin
Scenario: Contact field update marks cluster Stale
  Given a cluster with Contact A as member (status='Open')
  When Contact A's Email is updated (after insert)
  Then ContactDuplicateTriggerHandler fires
  And DuplicateClusterSelector finds all clusters containing Contact A
  And cluster status is updated from 'Open' or 'Partial' to 'Stale'

Scenario: Lead field update marks cluster Stale
  Given a cluster with Lead B as member (status='Open')
  When Lead B's Phone is updated
  Then LeadDuplicateTriggerHandler fires
  And cluster status updates to 'Stale'

Scenario: Stale clusters are re-evaluated in next batch
  Given cluster status='Stale' from previous trigger
  When DuplicateDetectionBatch runs
  Then batch queries clusters with status='Stale'
  And re-scores them with current field values
  And either keeps or updates cluster score

Scenario: Merged/Ignored clusters are not affected by trigger
  Given cluster status='Merged' or 'Ignored'
  When a member field is updated
  Then trigger does NOT change status
  (Rationale: merged/ignored clusters are no longer actionable)
```

**Story Points: 1**

---

## Subtask 12: Batch Processing Scales to 60K Records Without Governor Limits

**Title**
```
Batch processes 45K Leads + 15K Contacts without exceeding governor limits
```

**Description**
DuplicateDetectionBatch should process the full dataset (60K records) in 200-record chunks without hitting SOQL, DML, CPU, or heap size limits. No queries should be inside loops; all data must be pre-fetched.

**Background**
Governor limits are Salesforce's way of preventing resource monopolization. At 60K records, batch must be optimized: batch scope ≤ 200, SOQL pre-fetched in bulk, DML batched. Failure to respect limits results in batch failures and data gaps.

**Acceptance Criteria**
```gherkin
Scenario: Batch processes 200-record chunks without timeout
  Given 60K records total (45K Leads, 15K Contacts)
  When DuplicateDetectionBatch executes with scope=200
  Then batch completes in ~300 chunks (60K / 200)
  And each chunk completes in < 10 seconds
  And no "time limit exceeded" errors occur

Scenario: No SOQL inside loops
  Given batch execute() method with 200 records
  When batch runs
  Then all SOQL queries are executed BEFORE iteration:
    - LeadSelector.getByEmailBlock(blockKeySet) ← pre-fetched
    - DuplicateIgnoreSelector.getByPairKeys(pairKeySet) ← pre-fetched
  And scoring happens in-memory with no additional queries
  And SOQL count per chunk = 2–3 (safe)

Scenario: DML is batched
  Given batch inserts cluster + members for 200 records
  When batch completes
  Then total DML statements ≤ 5 per chunk
  And no DML inside loops

Scenario: CPU time stays within limits
  Given batch computes Jaro-Winkler scores for pair combinations
  When chunk processes 200 records (up to 200^2 = 40K pairs)
  Then CPU time stays < 10,000ms (safe margin from 15s limit)

Scenario: Heap memory stays within limits
  Given batch accumulates cluster data in-memory
  When chunk completes
  Then heap usage stays < 10MB (safe margin from 12MB limit)
```

**Story Points: 2**

---

## Subtask 13: Cross-Object Merge Queueable Scales to 1000+ Leads Without Timeout

**Title**
```
Queueable chain completes Lead→Contact merges in < 10 minutes at scale
```

**Description**
CrossObjectMergeQueueable must handle 1000+ sequential Lead→Contact conversions and merges without hitting the 10-minute execution timeout. If a single queueable takes > 10 minutes, Salesforce terminates it.

**Background**
convertLead() is a heavy operation. Chaining multiple queueables or using a loop would risk timeout. The current design expects sequential execution per user request, but at scale (bulk merge of 1000+ Leads), timeout is a real risk. This subtask validates we don't exceed limits or identifies where we need optimizations (e.g., batch window, chunking).

**Acceptance Criteria**
```gherkin
Scenario: Single cross-object merge completes in seconds
  Given 1 Lead and 1 Contact to merge
  When CrossObjectMergeQueueable executes
  Then convertLead + merge completes in < 5 seconds
  And no timeout occurs

Scenario: Queueable respects governor limits
  Given queueable must execute:
    1. convertLead() ← 1 DML
    2. SOQL for master + converted Contact ← 2 SOQL
    3. update master ← 1 DML
    4. merge ← 1 DML
    5. cluster update + audit insert ← 2 DML
  When queueable completes
  Then total = ~5 DML + 2 SOQL (safe)
  And no batch scope restrictions apply (queueable context is isolated)

Scenario: Bulk merge enqueues multiple queueables, not a loop
  Given admin initiates bulk merge of 100 Lead-Contact pairs
  When BulkMergeBatch processes them
  Then batch enqueues 100 SEPARATE queueable jobs (not a loop)
  And each queueable runs independently (parallel execution possible)
  And no single queueable timeout

Scenario: Known limitation: 1000+ sequential merges in tight loop risk timeout
  Given a hypothetical tight loop: for (1000 records) { convertLead + merge }
  When such a loop executes
  Then timeout occurs (expected and documented as known limitation)
  And mitigation: use batch or stagger merges
  And this subtask documents the limitation in design.md
```

**Story Points: 1**

---

## Subtask 14: All Merge Operations Are Audited with Complete Metadata

**Title**
```
Every merge (sync and async) inserts DuplicateMergeAudit__c with full metadata
```

**Description**
Whether a merge is same-object or cross-object, sync or async, a DuplicateMergeAudit__c record must be created with complete metadata: master ID, merged record IDs, status (Success/Failed), error message (if failed), field overrides, user, timestamp, and merge type.

**Background**
Audit trails are non-negotiable for compliance (data governance, regulatory requirements). Admins must be able to trace every merge decision, undo errors, and report on merge patterns. Incomplete audit records create liability.

**Acceptance Criteria**
```gherkin
Scenario: Successful same-object merge is audited
  Given a Contact merge completes without error
  When DuplicateMergeAudit__c is inserted
  Then record contains:
    - ClusterId__c (lookup to cluster)
    - MasterRecordId__c (Contact A Id)
    - MergedRecordIds__c (Contact B Id, serialized as JSON)
    - Status__c = 'Success'
    - ErrorMessage__c = null
    - FieldOverridesJSON__c = { Email: '...', Phone: '...', ... }
    - MergedBy__c (current user)
    - MergedDate__c (now)
    - MergeType__c = 'SameObject'

Scenario: Failed merge is audited with error details
  Given a merge fails (validation rule, DML error, etc.)
  When exception is caught
  Then DuplicateMergeAudit__c is inserted with:
    - Status__c = 'Failed'
    - ErrorMessage__c = [exception message]
    - All other fields populate as much as possible before error

Scenario: Cross-object merge audit includes JobId
  Given a queueable merge completes
  When DuplicateMergeAudit__c is inserted in CrossObjectMergeQueueable.execute()
  Then JobId__c = String.valueOf(ctx.getJobId())
  And record can be cross-referenced from AsyncApexJob lookup

Scenario: Audit record is queryable for reporting
  Given 100 merges have completed
  When admin queries: SELECT COUNT() FROM DuplicateMergeAudit__c WHERE CreatedDate >= [date]
  Then all 100 merges are visible
  And can be filtered by Status, MergeType, MergedBy, etc.
```

**Story Points: 1**

---

## Subtask 15: Console is Responsive and User-Friendly (UI/UX)

**Title**
```
Console UI is responsive, shows correct spinners/toasts, and loads in < 2 seconds
```

**Description**
The duplicateManagementConsole should load quickly, display spinners during async operations, show success/error toasts, and be responsive at desktop resolutions (30/70 list/detail split layout). All LWC components follow Cloudingo-style UX patterns.

**Background**
Poor UX frustrates admins and leads to errors. Fast load times, clear feedback (spinners during batch/merge, toasts for results), and intuitive layout reduce friction and increase adoption.

**Acceptance Criteria**
```gherkin
Scenario: Console loads quickly
  Given admin navigates to DuplicateManagementConsole
  When page loads
  Then getArchivableDates() is called
  And cluster list queries initial 50 clusters
  And total load time < 2 seconds

Scenario: List and detail panes have responsive layout
  Given desktop resolution (1920x1080)
  When console renders
  Then list pane is 30% width (left side)
  And detail pane is 70% width (right side)
  And both are sticky and scrollable independently

Scenario: Batch launch shows spinner and job ID
  Given admin clicks "Run Detection"
  When launchDetection() is called
  Then spinner appears
  And batch job ID is displayed
  And user can close console and job continues in background

Scenario: Merge shows progress and result
  Given admin clicks "Merge"
  When merge completes (sync or async)
  Then success toast appears: "Merge successful"
  Or error toast: "Merge failed: [message]"
  And spinner disappears
  And cluster list refreshes

Scenario: Toasts are clear and actionable
  Given a merge fails
  When toast appears
  Then message includes:
    - What failed ("Merge failed")
    - Why (validation rule, DML error, timeout, etc.)
    - What to do (retry, contact admin, check audit log, etc.)
```

**Story Points: 2**

---

## Subtask 16: Data Security — Sharing and FLS Enforced

**Title**
```
Console respects sharing rules and FLS; DuplicateAdmin permission set controls access
```

**Description**
All Apex controllers and selectors use `public with sharing class` to enforce row-level sharing (OWD, sharing rules, role hierarchy). All SOQL uses FLS checks or `WITH SECURITY_ENFORCED` where applicable. Only users with the DuplicateAdmin permission set can access the console and custom objects.

**Background**
Data is sensitive. Unauthorized access to duplicate clusters (which expose email, phone, company data) is a security risk. Salesforce sharing model must be respected; FLS enforces field-level access control.

**Acceptance Criteria**
```gherkin
Scenario: Console enforces sharing on selectors
  Given a user with limited sharing access (only their own records)
  When user opens console
  Then DuplicateClusterSelector queries respect OWD and sharing rules
  And user sees only clusters for records they have access to

Scenario: DuplicateAdmin permission set is required
  Given a user without DuplicateAdmin
  When user navigates to DuplicateManagementConsole
  Then page shows "Permission denied" or access is blocked
  And user cannot query/update cluster data

Scenario: FLS is enforced on field reads
  Given a field is restricted via FLS (e.g., Contact.Email not readable)
  When selector queries that field
  Then query result respects FLS
  And field value is not exposed to user without permission

Scenario: WITH SHARING on batch/queueable (security fix)
  Given W-02 and W-03 are addressed
  When DuplicateDetectionBatch and CrossObjectMergeQueueable run
  Then both are declared `public with sharing class`
  And respect user context sharing (or document as intentional system context)
```

**Story Points: 1**

---

## Definition of Done (DoD)

- [ ] All 16 subtasks are completed and tested
- [ ] Code passes compilation (`sf project deploy validate`)
- [ ] All tests pass locally and in CI/CD (`sf apex run test --code-coverage`)
- [ ] Coverage ≥85% per class
- [ ] Code review approved by one peer
- [ ] Acceptance criteria verified in UAT or scratch org
- [ ] Documentation updated (design.md, README)
- [ ] No regressions in existing LWC or Apex
- [ ] Custom index request submitted to Salesforce Support (blocking for Prod deployment)

---

## Dependencies & Blockers

- **Blocker**: Custom index on `Email_Block__c` (Contact + Lead) must be requested via Salesforce Support BEFORE production deployment
- **Dependency**: DX CLI v66.0+ for deployment
- **Timeline**: Must complete by Friday 12 June 2026

---

## Project Metadata

| Field | Value |
|-------|-------|
| **Project** | UDC Duplicate Records |
| **Change** | duplicate-management-console |
| **Status** | Open |
| **Created** | 2026-06-10 |
| **Deadline** | 2026-06-12 |
| **Team** | Data/Admin + Dev |
| **Edition** | Salesforce Enterprise |
| **Data Volume** | 45K Leads + 15K Contacts |
