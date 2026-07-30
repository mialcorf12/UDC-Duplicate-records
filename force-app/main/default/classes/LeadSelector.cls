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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Lead WHERE Email_Block__c IN :blockKeys AND IsConverted = false AND IsDeleted = false';
        return (List<Lead>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Lead WHERE Phone_Block__c IN :blockKeys AND IsConverted = false AND IsDeleted = false';
        return (List<Lead>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
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
        String query = 'SELECT ' + buildSelectClause() +
            ' FROM Lead WHERE Name_Block__c IN :blockKeys AND IsConverted = false AND IsDeleted = false';
        return (List<Lead>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'blockKeys' => blockKeys },
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Returns Lead records for the given set of IDs, including the
     *              Address subfields needed to resolve a winning address block
     *              during merge. Does not filter on IsConverted to support
     *              post-merge lookups.
     * @param ids Set of Lead Ids.
     * @return List of matching Lead records.
     */
    public static List<Lead> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Lead>();
        }
        String query = 'SELECT ' + buildSelectClause() + ' FROM Lead WHERE Id IN :ids';
        return (List<Lead>) Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'ids' => ids },
            AccessLevel.SYSTEM_MODE
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Builds the shared SELECT column list for every Lead query in
     *              this selector, sourced from the single field-list constant plus
     *              the Lead (plain) address subfields, so no method duplicates its
     *              own copy of the column list.
     * @return Comma-separated SOQL column list.
     */
    private static String buildSelectClause() {
        List<String> fields = new List<String>(DuplicateComparisonFields.LEAD_SNAPSHOT_FIELDS);
        fields.addAll(DuplicateComparisonFields.addressSubfields('Lead'));
        return String.join(fields, ', ');
    }
}
