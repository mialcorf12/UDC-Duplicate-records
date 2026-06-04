# duplicate-data-model Specification

## Purpose

Defines the custom objects and formula fields required to store duplicate clusters, members, ignore pairs, and merge audit logs, along with blocking key formulas on Contact and Lead.

## Requirements

### Requirement: Cluster Storage

The system MUST store duplicate groupings in `DuplicateCluster__c` and individual records in a master-detail `DuplicateClusterMember__c` object, serializing only Email, Phone, Name, and Company for comparison.

#### Scenario: Creating a cluster
- GIVEN a set of duplicate records is identified
- WHEN the batch process saves the results
- THEN a `DuplicateCluster__c` record is created
- AND a `DuplicateClusterMember__c` is created for each record linked via Master-Detail
- AND `FieldSnapshotJSON__c` contains only Email, Phone, FirstName/LastName, and Company

### Requirement: Blocking Key Formulas

The system MUST implement `Email_Block__c`, `Phone_Block__c`, and `Name_Block__c` formula fields on Contact and Lead to support indexed batch querying.

#### Scenario: Email block computation
- GIVEN a Contact with Email "john.smith@example.com"
- WHEN the record is saved
- THEN `Email_Block__c` calculates as "john.smith"

#### Scenario: Required custom index
- GIVEN the org contains 100K+ Contacts and Leads
- WHEN querying by `Email_Block__c`
- THEN a custom index MUST be in place via Salesforce Support to avoid full table scans

### Requirement: Audit and Ignore Storage

The system MUST store ignored pairs in `DuplicateIgnore__c` with a unique `PairKey__c` and track all merge outcomes in `DuplicateMergeAudit__c`.

#### Scenario: Storing an ignored pair
- GIVEN two records are marked as not duplicates
- WHEN the ignore action is saved
- THEN a `DuplicateIgnore__c` is created with a sorted `PairKey__c`
- AND the ExternalId constraint prevents duplicate ignore entries