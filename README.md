# UDC Duplicate Records

Salesforce DX project — Duplicate Management Console for Contacts and Leads.

## Overview

A batch-based duplicate detection and resolution system for 200K+ Contact and Lead records. Built as a Lightning Web Component console with cluster visualization, side-by-side field comparison, and merge/ignore actions.

## Architecture

- **Detection**: Batch Apex with three-layer blocking keys (Email, Phone, Name) running nightly
- **Storage**: Custom objects `DuplicateCluster__c` and `DuplicateClusterMember__c`
- **UI**: LWC console (Cloudingo-style) with 30/70 list/detail layout
- **Merge**: Same-object DML merge + cross-object Queueable (convertLead → merge Contact)
- **Ignore**: `DuplicateIgnore__c` with ExternalId `PairKey__c` — survives batch re-runs

## SDD Planning Artifacts

All specs, design, and tasks are under `openspec/changes/duplicate-management-console/`.

## Stack

- Salesforce DX, API v66.0 (Summer '25)
- Apex, LWC, SOQL

## ⚠️ Before Production

Request a custom index on `Email_Block__c` (Contact + Lead) via Salesforce Support before running the batch in production. Formula fields are not indexed by default.
