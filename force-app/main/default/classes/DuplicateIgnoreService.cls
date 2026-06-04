/**
 * @description Stateless service for creating and removing duplicate ignore pairs.
 *              Uses PairKey__c (ExternalId) for idempotent upserts.
 *              PairKey = min(id1, id2) + '_' + max(id1, id2) — order-independent.
 */
public with sharing class DuplicateIgnoreService {

    /**
     * @description Creates or updates a DuplicateIgnore__c record for the specified pair.
     *              Idempotent: calling twice with the same IDs results in one record.
     *              PairKey is order-independent: ignorePair(A, B) == ignorePair(B, A).
     *
     * @param id1    First record ID (Contact or Lead).
     * @param id2    Second record ID (Contact or Lead).
     * @param userId The user triggering the ignore action.
     * @param reason Free-text reason for ignoring the pair.
     */
    public static void ignorePair(Id id1, Id id2, Id userId, String reason) {
        String pairKey = buildPairKey(id1, id2);

        DuplicateIgnore__c ignoreRecord = new DuplicateIgnore__c(
            PairKey__c     = pairKey,
            IgnoredBy__c   = userId,
            IgnoredDate__c = DateTime.now(),
            Reason__c      = reason
        );

        // Upsert by PairKey__c (ExternalId) — idempotent
        Database.upsert(ignoreRecord, DuplicateIgnore__c.PairKey__c, false);
    }

    /**
     * @description Removes the DuplicateIgnore__c record for the specified pair,
     *              allowing the next batch run to re-evaluate the pair.
     *              Order-independent: unignorePair(A, B) == unignorePair(B, A).
     *              No-op if the pair was not previously ignored.
     *
     * @param id1 First record ID.
     * @param id2 Second record ID.
     */
    public static void unignorePair(Id id1, Id id2) {
        String pairKey = buildPairKey(id1, id2);
        DuplicateIgnore__c existing = DuplicateIgnoreSelector.getByPairKey(pairKey);
        if (existing != null) {
            delete existing;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Builds a canonical, order-independent pair key.
     *              Result: min(id1, id2) + '_' + max(id1, id2)
     *              String comparison ensures consistency regardless of argument order.
     */
    private static String buildPairKey(Id id1, Id id2) {
        String s1 = String.valueOf(id1);
        String s2 = String.valueOf(id2);
        return (s1 < s2) ? s1 + '_' + s2 : s2 + '_' + s1;
    }
}
