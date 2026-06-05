/**
 * @description Selector for Contact records.
 *              All Contact SOQL is centralized here. No SOQL outside this class.
 */
public with sharing class ContactSelector {

    // ─────────────────────────────────────────────────────────────────────────
    // Block-key queries (used by DuplicateDetectionBatch)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Returns non-deleted Contacts whose Email_Block__c matches any
     *              of the supplied block keys.
     * @param blockKeys Set of email block key values to filter on.
     * @return List of matching Contact records.
     */
    public static List<Contact> getByEmailBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   AccountId,
                   Account.Name,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Contact
            WHERE  Email_Block__c IN :blockKeys
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns non-deleted Contacts whose Phone_Block__c matches any
     *              of the supplied block keys.
     * @param blockKeys Set of phone block key values to filter on.
     * @return List of matching Contact records.
     */
    public static List<Contact> getByPhoneBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   AccountId,
                   Account.Name,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Contact
            WHERE  Phone_Block__c IN :blockKeys
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns non-deleted Contacts whose Name_Block__c matches any
     *              of the supplied block keys.
     * @param blockKeys Set of name block key values to filter on.
     * @return List of matching Contact records.
     */
    public static List<Contact> getByNameBlock(Set<String> blockKeys) {
        if (blockKeys == null || blockKeys.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   AccountId,
                   Account.Name,
                   Email_Block__c,
                   Phone_Block__c,
                   Name_Block__c
            FROM   Contact
            WHERE  Name_Block__c IN :blockKeys
            AND    IsDeleted = false
        ];
    }

    /**
     * @description Returns Contact records for the given set of IDs.
     * @param ids Set of Contact Ids.
     * @return List of matching Contact records.
     */
    public static List<Contact> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id,
                   Email,
                   Phone,
                   FirstName,
                   LastName,
                   AccountId,
                   Account.Name
            FROM   Contact
            WHERE  Id IN :ids
        ];
    }
}
