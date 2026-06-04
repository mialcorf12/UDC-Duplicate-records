# duplicate-ignore Specification

## Purpose

Defines the mechanism allowing users to permanently ignore false-positive duplicate pairs, preventing them from being flagged in future batch runs.

## Requirements

### Requirement: Permanent Ignore Storage

The system MUST allow users to ignore a pair of records by creating a `DuplicateIgnore__c` record using a sorted composite key.

#### Scenario: Ignoring a pair
- GIVEN two records in a cluster that are not actually duplicates
- WHEN the user clicks "Ignore" in the UI
- THEN a `DuplicateIgnore__c` record is created
- AND `PairKey__c` is populated with `min(id1,id2) + '_' + max(id1,id2)`

### Requirement: Reversing an Ignore

The system MUST allow users to un-ignore a pair by deleting the corresponding `DuplicateIgnore__c` record.

#### Scenario: Un-ignoring a pair
- GIVEN a pair was previously ignored
- WHEN the user deletes the `DuplicateIgnore__c` record
- THEN the next batch run will re-evaluate the pair and potentially recreate a cluster