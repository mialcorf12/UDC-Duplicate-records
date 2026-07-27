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
            WITH   SECURITY_ENFORCED
        ];

        for (DuplicateIgnore__c rec : records) {
            result.put(rec.PairKey__c, rec);
        }

        return result;
    }
}
