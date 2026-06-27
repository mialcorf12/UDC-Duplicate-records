/**
 * @description Selector for Lead records.
 *              All Lead SOQL is centralized here. No SOQL outside this class.
 *              Only returns non-converted, non-deleted Leads.
 */
public with sharing class LeadSelector {

    // ─────────────────────────────────────────────────────────────────────────
    // Block-key queries (used by DuplicateDetectionBatch)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Returns non-converted, non-deleted Leads whose Email_Block__c
     *              matches any of the supplied block keys.
     * @param blockKeys Set of email block key values to filter on.
     * @return List of matching Lead records.
     */
    public static List<Lead> getByEmailBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   Company,
                   IsConverted,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Lead
            WHERE  Email_Block__c IN :blockKeys
            AND    IsConverted = false
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns non-converted, non-deleted Leads whose Phone_Block__c
     *              matches any of the supplied block keys.
     * @param blockKeys Set of phone block key values to filter on.
     * @return List of matching Lead records.
     */
    public static List<Lead> getByPhoneBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   Company,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Lead
            WHERE  Phone_Block__c IN :blockKeys
            AND    IsConverted = false
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns non-converted, non-deleted Leads whose Name_Block__c
     *              matches any of the supplied block keys.
     * @param blockKeys Set of name block key values to filter on.
     * @return List of matching Lead records.
     */
    public static List<Lead> getByNameBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   Company,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Lead
            WHERE  Name_Block__c IN :blockKeys
            AND    IsConverted = false
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns Lead records for the given set of IDs.
     *              Does not filter on IsConverted to support post-merge lookups.
     * @param ids Set of Lead Ids.
     * @return List of matching Lead records.
     */
    public static List<Lead> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   Company,
                   IsConverted
            FROM   Lead
            WHERE  Id IN :ids
        ];
    }
}
