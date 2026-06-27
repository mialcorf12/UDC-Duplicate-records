/**
 * @description Selector for DuplicateIgnore__c.
 *              All SOQL is centralized here.
 */
public with sharing class DuplicateIgnoreSelector {

    /**
     * @description Returns a map of DuplicateIgnore__c records keyed by PairKey__c
     *              for O(1) lookup in the detection batch.
     * @param pairKeys Set of pair key strings (min(id1,id2) + '_' + max(id1,id2)).
     * @return Map<String, DuplicateIgnore__c> keyed by PairKey__c.
     */
    /**
     * @description Returns a single DuplicateIgnore__c by PairKey__c for un-ignore operations.
     * @param pairKey The canonical pair key string.
     * @return The matching record, or null if not found.
     */
    public static DuplicateIgnore__c getByPairKey(String pairKey) {
        List<DuplicateIgnore__c> records = [
            SELECT Id, PairKey__c
            FROM   DuplicateIgnore__c
            WHERE  PairKey__c = :pairKey
            LIMIT  1
        ];
        SObject[] stripped = Security.stripInaccessible(AccessType.READABLE, records).getRecords();
        return stripped.isEmpty() ? null : (DuplicateIgnore__c) stripped[0];
    }

    public static Map<String, DuplicateIgnore__c> getByPairKeys(Set<String> pairKeys) {
        Map<String, DuplicateIgnore__c> result = new Map<String, DuplicateIgnore__c>();

        if (pairKeys == null || pairKeys.isEmpty()) {
            return result;
        }

        List<DuplicateIgnore__c> records = [
            SELECT Id,
                   PairKey__c,
                   IgnoredBy__c,
                   IgnoredDate__c,
                   Reason__c
            FROM   DuplicateIgnore__c
            WHERE  PairKey__c IN :pairKeys
        ];

        SObject[] stripped = Security.stripInaccessible(AccessType.READABLE, records).getRecords();
        for (SObject rec : stripped) {
            DuplicateIgnore__c ignore = (DuplicateIgnore__c) rec;
            result.put(ignore.PairKey__c, ignore);
        }

        return result;
    }
}
