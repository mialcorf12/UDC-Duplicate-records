/**
 * @description Test class for DuplicateIgnoreSelector.
 */
@isTest
private class DuplicateIgnoreSelectorTest {

    @isTest
    static void testGetByPairKeys_returnsMatchingRecords() {
        List<DuplicateIgnore__c> ignores = new List<DuplicateIgnore__c>{
            new DuplicateIgnore__c(PairKey__c = 'key_001', Reason__c = 'Not a dup'),
            new DuplicateIgnore__c(PairKey__c = 'key_002', Reason__c = 'Different companies'),
            new DuplicateIgnore__c(PairKey__c = 'key_003', Reason__c = 'Test data')
        };
        insert ignores;

        Set<String> lookupKeys = new Set<String>{ 'key_001', 'key_003' };

        Test.startTest();
        Map<String, DuplicateIgnore__c> result = DuplicateIgnoreSelector.getByPairKeys(lookupKeys);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Expected 2 matching records');
        System.assert(result.containsKey('key_001'), 'Map should contain key_001');
        System.assert(result.containsKey('key_003'), 'Map should contain key_003');
        System.assert(!result.containsKey('key_002'), 'Map should NOT contain key_002');
    }

    @isTest
    static void testGetByPairKeys_emptySetReturnsEmpty() {
        Test.startTest();
        Map<String, DuplicateIgnore__c> result = DuplicateIgnoreSelector.getByPairKeys(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty map');
    }

    @isTest
    static void testGetByPairKeys_nullReturnsEmpty() {
        Test.startTest();
        Map<String, DuplicateIgnore__c> result = DuplicateIgnoreSelector.getByPairKeys(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null input should return empty map');
    }

    @isTest
    static void testGetByPairKeys_noMatchReturnsEmpty() {
        insert new DuplicateIgnore__c(PairKey__c = 'key_exists');

        Test.startTest();
        Map<String, DuplicateIgnore__c> result = DuplicateIgnoreSelector.getByPairKeys(
            new Set<String>{ 'key_does_not_exist' }
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Non-matching key should return empty map');
    }

    @isTest
    static void testGetByPairKeys_bulk200() {
        List<DuplicateIgnore__c> bulkIgnores = new List<DuplicateIgnore__c>();
        Set<String> bulkKeys = new Set<String>();
        for (Integer i = 0; i < 200; i++) {
            String k = 'bulkkey_' + i;
            bulkIgnores.add(new DuplicateIgnore__c(PairKey__c = k));
            bulkKeys.add(k);
        }
        insert bulkIgnores;

        Test.startTest();
        Map<String, DuplicateIgnore__c> result = DuplicateIgnoreSelector.getByPairKeys(bulkKeys);
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 matching records');
    }
}
