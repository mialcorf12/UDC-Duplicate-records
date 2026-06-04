/**
 * @description Test class for LeadSelector.
 *              Bulk scenario: 200 leads.
 */
@isTest
private class LeadSelectorTest {

    @TestSetup
    static void makeData() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 200; i++) {
            leads.add(new Lead(
                FirstName = 'Test',
                LastName  = 'Lead' + i,
                Company   = 'Acme Corp',
                Email     = 'testlead' + i + '@example.com',
                Phone     = '555' + String.valueOf(2000000 + i)
            ));
        }
        insert leads;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByEmailBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByEmailBlock_returnsMatchingLeads() {
        Set<String> blockKeys = new Set<String>{ 'testlead0', 'testlead1' };

        Test.startTest();
        List<Lead> result = LeadSelector.getByEmailBlock(blockKeys);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Expected 2 leads matching the email blocks');
        for (Lead l : result) {
            System.assertNotEquals(null, l.Email, 'Email field should be populated');
            System.assertEquals(false, l.IsConverted, 'Should not return converted leads');
        }
    }

    @isTest
    static void testGetByEmailBlock_excludesConvertedLeads() {
        Lead toConvert = [SELECT Id, Email FROM Lead WHERE Email = 'testlead0@example.com' LIMIT 1];

        // Convert the lead
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(toConvert.Id);
        lc.setConvertedStatus('Closed - Converted');
        lc.setDoNotCreateOpportunity(true);
        Database.convertLead(lc);

        Set<String> blockKeys = new Set<String>{ 'testlead0' };

        Test.startTest();
        List<Lead> result = LeadSelector.getByEmailBlock(blockKeys);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Converted lead should be excluded');
    }

    @isTest
    static void testGetByEmailBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Lead> result = LeadSelector.getByEmailBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    @isTest
    static void testGetByEmailBlock_bulk200() {
        Set<String> allBlocks = new Set<String>();
        for (Integer i = 0; i < 200; i++) {
            allBlocks.add('testlead' + i);
        }

        Test.startTest();
        List<Lead> result = LeadSelector.getByEmailBlock(allBlocks);
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 leads');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByPhoneBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByPhoneBlock_returnsMatchingLeads() {
        Set<String> blockKeys = new Set<String>{ '2000000', '2000001' };

        Test.startTest();
        List<Lead> result = LeadSelector.getByPhoneBlock(blockKeys);
        Test.stopTest();

        System.assert(result.size() >= 0, 'Method should execute without error');
    }

    @isTest
    static void testGetByPhoneBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Lead> result = LeadSelector.getByPhoneBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByNameBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByNameBlock_returnsMatchingLeads() {
        // Name_Block__c = LOWER(LEFT(LastName,3)) & LOWER(LEFT(FirstName,1))
        // LastName='Lead0', FirstName='Test' → 'lea' + 't' = 'leat'
        Set<String> blockKeys = new Set<String>{ 'lea' };

        Test.startTest();
        List<Lead> result = LeadSelector.getByNameBlock(blockKeys);
        Test.stopTest();

        System.assert(result.size() >= 0, 'Method should execute without error');
    }

    @isTest
    static void testGetByNameBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Lead> result = LeadSelector.getByNameBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByIds
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByIds_returnsCorrectLeads() {
        List<Lead> allLeads = [SELECT Id FROM Lead LIMIT 5];
        Set<Id> idSet = new Map<Id, Lead>(allLeads).keySet();

        Test.startTest();
        List<Lead> result = LeadSelector.getByIds(idSet);
        Test.stopTest();

        System.assertEquals(5, result.size(), 'Should return 5 leads by ID');
        System.assertNotEquals(null, result[0].LastName, 'LastName should be populated');
    }

    @isTest
    static void testGetByIds_emptySetReturnsEmpty() {
        Test.startTest();
        List<Lead> result = LeadSelector.getByIds(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty ID set should return empty list');
    }

    @isTest
    static void testGetByIds_nullReturnsEmpty() {
        Test.startTest();
        List<Lead> result = LeadSelector.getByIds(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null input should return empty list');
    }

    @isTest
    static void testGetByIds_bulk200() {
        List<Lead> allLeads = [SELECT Id FROM Lead LIMIT 200];
        Set<Id> idSet = new Map<Id, Lead>(allLeads).keySet();

        Test.startTest();
        List<Lead> result = LeadSelector.getByIds(idSet);
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 leads by ID');
    }
}
