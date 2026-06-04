# duplicate-detection Specification

## Purpose

Defines the Batch Apex pre-computation architecture that partitions records using blocking keys, scores similarities, and creates duplicate clusters asynchronously.

## Requirements

### Requirement: Batch Execution and Chunking

The system MUST execute duplicate detection via a stateful Batch Apex job (`DuplicateDetectionBatch`), processing distinct blocking keys in chunks of 50 to respect governor limits.

#### Scenario: Normal batch execution
- GIVEN the nightly scheduled time arrives
- WHEN `DuplicateDetectionBatch` runs
- THEN it processes up to 50 block keys per execute
- AND performs max 6 SOQL and 2 DML operations per execute
- AND limits heap size to ~3MB

### Requirement: Scoring Thresholds

The system MUST calculate similarity scores using a weighted system (Email 40, Phone 30, Name 20, Company 10) and only group records scoring ≥ 70.

#### Scenario: High confidence match
- GIVEN two records match exactly on Email (40), Phone (30), and Name (20)
- WHEN the batch evaluates the pair
- THEN the score is 90
- AND they are added to a cluster as a candidate pair

#### Scenario: Below threshold pair
- GIVEN two records match only on Name (20) and Company (10)
- WHEN the batch evaluates the pair
- THEN the score is 30
- AND they are NOT added to a cluster

### Requirement: Ignore List Verification

The system MUST NOT flag pairs that exist in `DuplicateIgnore__c`.

#### Scenario: Skipping ignored pairs
- GIVEN two records score ≥ 70
- AND their sorted IDs exist as `PairKey__c` in `DuplicateIgnore__c`
- WHEN the batch evaluates the pair
- THEN the pair is skipped and not added to the cluster

### Requirement: Stale Cluster Trigger

The system MUST mark existing clusters as Stale when a member's key fields change.

#### Scenario: Field update on a cluster member
- GIVEN a Contact is part of an Open `DuplicateCluster__c`
- WHEN the Contact's Email is updated
- THEN the trigger marks the `DuplicateCluster__c` Status as 'Stale'