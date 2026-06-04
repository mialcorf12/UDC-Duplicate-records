# Proposal: duplicate-management-console

## Intent

Address technical debt and data quality issues by providing a scalable duplicate detection and resolution system for 200K+ Contact and Lead records, overcoming Salesforce limits via batch processing and an intuitive LWC console.

## Scope

### In Scope
- Create custom objects for storing duplicate clusters and ignored pairs.
- Add blocking key formula fields on Contact and Lead for efficient batch detection.
- Develop batch Apex for async duplicate detection across records.
- Build an LWC console (Cloudingo style) for cluster comparison and actions.
- Implement queueable cross-object (Contact vs Lead) and same-object merge service.
- Permanent ignore pair mechanism to prevent re-flagging.

### Out of Scope
- Real-time duplicate prevention on single-record UI saves (use native Duplicate Rules for this).
- Merging across standard objects other than Contact and Lead.

## Capabilities

### New Capabilities
- `duplicate-data-model`: Custom objects DuplicateCluster__c, DuplicateClusterMember__c, DuplicateIgnore__c + formula fields on Contact/Lead
- `duplicate-detection`: Batch Apex pre-computation of clusters using blocking keys
- `duplicate-cluster-ui`: LWC console for viewing, comparing, and acting on clusters
- `duplicate-merge`: Apex service layer for same-object and cross-object merges
- `duplicate-ignore`: Permanent ignore pairs mechanism

### Modified Capabilities
- None

## Approach

Implement a pre-computed batch architecture using three-layer blocking keys (Email, Phone, Name) to partition the dataset. Batch Apex runs nightly to populate `DuplicateCluster__c` and `DuplicateClusterMember__c`. A smart-container LWC console will provide UI to review clusters. Cross-object merges will be orchestrated via a Queueable Apex chain to handle `convertLead()` and `merge` sequentially within governor limits.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `force-app/main/default/objects/DuplicateCluster__c/` | New | Cluster header object |
| `force-app/main/default/objects/DuplicateClusterMember__c/` | New | Member detail object |
| `force-app/main/default/objects/DuplicateIgnore__c/` | New | Ignored pairs registry |
| `force-app/main/default/objects/Contact/fields/` | Modified | Add blocking key formula fields |
| `force-app/main/default/objects/Lead/fields/` | Modified | Add blocking key formula fields |
| `force-app/main/default/classes/` | New | Batch detection, Merge service, Queueable, Controllers |
| `force-app/main/default/lwc/` | New | Duplicate Management Console UI components |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Un-indexed blocking formula fields causing slow SOQL at 100K+ records | High | **REQUIRED before go-live**: open a Salesforce Support case requesting a custom index on `Email_Block__c` for both Contact and Lead. Without this, SOQL on formula fields is a full-scan — at 100K records this will exceed CPU time limits and cause batch failures in production. This cannot be done from Setup; it requires Support intervention. |
| `FieldSnapshotJSON__c` exceeding LongTextArea limit (131,072 chars) | Medium | **Decided**: serialize only the four comparison fields — `Email`, `Phone`, `Name` (FirstName + LastName), `Company` (AccountName for Contact / Company for Lead). No other fields. Enforced at serialization time in `DuplicateClusterMember__c` build logic inside the batch. |
| Merge failure swallowed by async Queueable | Medium | Store merge outcome in `DuplicateMergeAudit__c`; LWC polls `getJobStatus()` every 2s and surfaces result to user. |

## Rollback Plan

- Delete LWC components and Apex classes via destructive changes.
- Delete custom objects (DuplicateCluster__c, etc.) and custom fields on Contact/Lead.
- Merges are irreversible out-of-the-box; any incorrect merges would require restoring from a weekly data export backup. A dry-run testing phase will be completed before Prod deployment.

## Dependencies

- Salesforce DX API v66.0 (Summer '25).
- Custom index requests may require Salesforce Support intervention.

## Success Criteria

- [ ] Batch Apex processes 200K records without hitting governor limits.
- [ ] LWC console successfully displays clusters and side-by-side comparison.
- [ ] Users can successfully merge a Lead into a Contact via the UI.
- [ ] Ignored pairs do not reappear in subsequent batch detection runs.
