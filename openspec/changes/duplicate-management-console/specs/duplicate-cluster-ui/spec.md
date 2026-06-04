# duplicate-cluster-ui Specification

## Purpose

Defines the Lightning Web Component (LWC) console providing a Cloudingo-style interface to filter, view, compare, and take action on pre-computed duplicate clusters.

## Requirements

### Requirement: Cluster Listing and Pagination

The system MUST display duplicate clusters in a paginated list, supporting infinite scroll and filtering by ObjectType, Status, and Score.

#### Scenario: Viewing the cluster list
- GIVEN the user navigates to the Duplicate Management Console
- WHEN the list loads
- THEN it displays clusters grouped by status
- AND fetches records in pages of 50 via server-side pagination

### Requirement: Side-by-Side Comparison

The system MUST display selected cluster members in a side-by-side grid, showing only Email, Phone, Name, and Company, allowing users to select the winning value per field.

#### Scenario: Selecting field overrides
- GIVEN a cluster detail is open with two Lead members
- WHEN the user selects the Phone from record A and Email from record B
- THEN the component builds a field override map representing the selections

### Requirement: Action Orchestration

The system MUST provide UI actions to Merge, Ignore, and Re-scan clusters, with asynchronous polling for merge outcomes.

#### Scenario: Initiating a merge
- GIVEN a cluster detail is open with field overrides selected
- WHEN the user clicks Merge
- THEN the component calls the Apex merge service
- AND polls `getJobStatus()` every 2 seconds (up to 3 retries)
- AND displays a progress indicator (Detecting → Converting → Merging → Done)