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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Contact WHERE Email_Block__c IN :blockKeys AND IsDeleted = false';
        return (List<Contact>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Contact WHERE Phone_Block__c IN :blockKeys AND IsDeleted = false';
        return (List<Contact>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Contact WHERE Name_Block__c IN :blockKeys AND IsDeleted = false';
        return (List<Contact>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Returns Contact records for the given set of IDs, including the
     *              MailingAddress subfields needed to resolve a winning address
     *              block during merge.
     * @param ids Set of Contact Ids.
     * @return List of matching Contact records.
     */
    public static List<Contact> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Contact>();
        }
        String query = 'SELECT ' + buildSelectClause() + ' FROM Contact WHERE Id IN :ids';
        return (List<Contact>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'ids' => ids },
            AccessLevel.SYSTEM_MODE
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Builds the shared SELECT column list for every Contact query in
     *              this selector, sourced from the single field-list constant plus
     *              the Contact (Mailing*) address subfields, so no method duplicates
     *              its own copy of the column list.
     * @return Comma-separated SOQL column list.
     */
    private static String buildSelectClause() {
        List<String> fields = new List<String>(DuplicateComparisonFields.CONTACT_SNAPSHOT_FIELDS);
        fields.addAll(DuplicateComparisonFields.addressSubfields('Contact'));
        return String.join(fields, ', ');
    }
}
