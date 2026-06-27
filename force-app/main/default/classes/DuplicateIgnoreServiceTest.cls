/**
 * @description Test class for DuplicateIgnoreService.
 *              Verifies: idempotent upsert, un-ignore, order-independence of PairKey.
 */
@isTest
private class DuplicateIgnoreServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Contact createContact(String lastName) {
        Contact c = new Contact(FirstName = 'Test', LastName = lastName, Email = lastName.toLowerCase() + '@test.com');
        insert c;
        return c;
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ignorePair — idempotency
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testIgnorePair_idempotentUpsert_onlyOneRecordCreated() {
        Contact c1 = createContact('Alpha');
        Contact c2 = createContact('Beta');
        Id userId = getTestUser().Id;

        Test.startTest();
        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'First call');
        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'Second call');
        Test.stopTest();

        List<DuplicateIgnore__c> records = [SELECT Id, PairKey__c, Reason__c FROM DuplicateIgnore__c];
        System.assertEquals(1, records.size(), 'Idempotent upsert should result in only 1 DuplicateIgnore__c record');
        // The second call's reason should have overwritten the first (upsert behavior)
        System.assertEquals('Second call', records[0].Reason__c, 'Upsert should update existing record');
    }

    @isTest
    static void testIgnorePair_createsRecordWithCorrectFields() {
        Contact c1 = createContact('Gamma');
        Contact c2 = createContact('Delta');
        Id userId  = getTestUser().Id;

        Test.startTest();
        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'Test reason');
        Test.stopTest();

        DuplicateIgnore__c record = [
            SELECT PairKey__c, IgnoredBy__c, IgnoredDate__c, Reason__c
            FROM   DuplicateIgnore__c
            LIMIT  1
        ];

        // Build expected pair key
        String s1 = String.valueOf(c1.Id);
        String s2 = String.valueOf(c2.Id);
        String expectedKey = (s1 < s2) ? s1 + '_' + s2 : s2 + '_' + s1;

        System.assertEquals(expectedKey, record.PairKey__c, 'PairKey should match expected canonical form');
        System.assertEquals(userId, record.IgnoredBy__c, 'IgnoredBy should match the provided userId');
        System.assertEquals('Test reason', record.Reason__c, 'Reason should match');
        System.assertNotEquals(null, record.IgnoredDate__c, 'IgnoredDate should be set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ignorePair — order independence
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testIgnorePair_orderIndependent_sameKeyRegardlessOfArgumentOrder() {
        Contact c1 = createContact('Epsilon');
        Contact c2 = createContact('Zeta');
        Id userId  = getTestUser().Id;

        Test.startTest();
        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'Forward');
        DuplicateIgnoreService.ignorePair(c2.Id, c1.Id, userId, 'Reverse');
        Test.stopTest();

        List<DuplicateIgnore__c> records = [SELECT Id FROM DuplicateIgnore__c];
        System.assertEquals(
            1, records.size(),
            'ignorePair(A,B) and ignorePair(B,A) should produce the same record (order-independent)'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // unignorePair
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testUnignorePair_deletesExistingIgnoreRecord() {
        Contact c1 = createContact('Eta');
        Contact c2 = createContact('Theta');
        Id userId  = getTestUser().Id;

        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'Will be deleted');
        System.assertEquals(1, [SELECT COUNT() FROM DuplicateIgnore__c], 'Pre-condition: 1 ignore record');

        Test.startTest();
        DuplicateIgnoreService.unignorePair(c1.Id, c2.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM DuplicateIgnore__c], 'Ignore record should be deleted');
    }

    @isTest
    static void testUnignorePair_orderIndependent_deletesRegardlessOfArgumentOrder() {
        Contact c1 = createContact('Iota');
        Contact c2 = createContact('Kappa');
        Id userId  = getTestUser().Id;

        DuplicateIgnoreService.ignorePair(c1.Id, c2.Id, userId, 'Test');
        System.assertEquals(1, [SELECT COUNT() FROM DuplicateIgnore__c], 'Pre-condition: 1 record');

        Test.startTest();
        // Reverse order
        DuplicateIgnoreService.unignorePair(c2.Id, c1.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM DuplicateIgnore__c], 'unignorePair with reversed order should still delete');
    }

    @isTest
    static void testUnignorePair_noOp_whenPairNotIgnored() {
        Contact c1 = createContact('Lambda');
        Contact c2 = createContact('Mu');

        Test.startTest();
        // Should not throw — pair was never ignored
        DuplicateIgnoreService.unignorePair(c1.Id, c2.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM DuplicateIgnore__c], 'Should be no-op when pair was not ignored');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bulk scenario
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testIgnorePair_200Pairs_allCreated() {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 400; i++) {
            contacts.add(new Contact(FirstName = 'Bulk', LastName = 'Ignore' + i, Email = 'bulk' + i + '@test.com'));
        }
        insert contacts;
        Id userId = getTestUser().Id;

        List<DuplicateIgnoreService.IgnorePairRequest> requests = new List<DuplicateIgnoreService.IgnorePairRequest>();
        for (Integer i = 0; i < 400; i += 2) {
            requests.add(new DuplicateIgnoreService.IgnorePairRequest(contacts[i].Id, contacts[i + 1].Id, userId, 'Bulk test'));
        }

        Test.startTest();
        DuplicateIgnoreService.ignorePairs(requests);
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM DuplicateIgnore__c], 'Should have created 200 ignore records');
    }
}
