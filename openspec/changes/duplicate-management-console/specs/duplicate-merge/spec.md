# duplicate-merge Specification

## Purpose

Defines the Apex service layer orchestrating same-object and cross-object merges, ensuring field overrides are applied and governor limits are respected via Queueable Apex.

## Requirements

### Requirement: Same-Object Merging

The system MUST support merging up to 2 secondary Contact or Lead records into a master record using the native Apex `merge` statement.

#### Scenario: Merging same-object duplicates
- GIVEN a cluster of three Contacts
- WHEN the merge service is invoked for same-object
- THEN field overrides are applied to the master Contact
- AND the master is updated
- AND `merge masterContact List<Contact>{dup1, dup2}` is executed
- AND native related records (History, Activities) are transferred

### Requirement: Cross-Object Merging

The system MUST merge a Lead into a Contact by first converting the Lead and then merging the resulting Contact within the same Queueable transaction.

#### Scenario: Merging Lead into Contact
- GIVEN a cluster containing a Contact (master) and a Lead
- WHEN the merge service is invoked for cross-object
- THEN a Queueable job is enqueued
- AND `Database.convertLead()` runs
- AND field overrides are applied to the master Contact
- AND the master Contact is merged with the converted Contact
- AND no callouts occur in the same transaction

### Requirement: Merge Audit Logging

The system MUST record the outcome of all merge operations in `DuplicateMergeAudit__c` and update the cluster status.

#### Scenario: Successful merge
- GIVEN a Queueable merge job completes successfully
- WHEN the job finishes
- THEN a `DuplicateMergeAudit__c` record is inserted with Status 'Success'
- AND the `DuplicateCluster__c` Status is updated to 'Merged'