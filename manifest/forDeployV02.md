# disable
- All Duplicate Rules
- Contact Validation Rules
    Corresponding_Record_Type

# NEW metadata
## CustomField
    Contact.Email_Collection__c
    Lead.Email_Collection__c
    Lead.Portal_User_ID__c
    Lead.Sales_Informed_Agreement_Signed__c

## Flow
    Email_Collection_Contact
    Email_Collection_Lead

## ApexClass
    DuplicateComparisonFields





# UPDATE metadata

## ApexClass
    ContactSelector
    ContactSelectorTest
    LeadSelector
    LeadSelectorTest
    
    DuplicateDetectionBatch
    DuplicateDetectionBatchTest
    DuplicateMergeService
    DuplicateMergeServiceTest
    DuplicateScoringUtil
    DuplicateScoringUtilTest

    CrossObjectMergeQueueable
    CrossObjectMergeQueueableTest

## LightningComponentBundle
    duplicateClusterDetail
    duplicateFieldComparisonTable
