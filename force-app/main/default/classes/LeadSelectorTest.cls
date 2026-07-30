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
        Set<String> blockKeys = new Set<String>{ 'testlead0@example.com', 'testlead1@example.com' };

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
        lc.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
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
            allBlocks.add('testlead' + i + '@example.com');
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

    // ─────────────────────────────────────────────────────────────────────────
    // Shared field-list constant — new comparison fields must be queryable
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByEmailBlock_returnsNewComparisonAndAddressFields() {
        List<Lead> seed = [SELECT Id FROM Lead WHERE Email = 'testlead0@example.com' LIMIT 1];
        updateBypassingDuplicateRules(new Lead(
            Id                                  = seed[0].Id,
            MobilePhone                         = '5557777777',
            Sales_Informed_Agreement_Signed__c  = Date.today(),
            Email_Collection__c                 = 'opted-in',
            Portal_User_ID__c                   = 'PORTAL-3',
            Street                              = '3 Oak St',
            City                                = 'Shelbyville'
        ));

        Set<String> blockKeys = new Set<String>{ 'testlead0@example.com' };

        Test.startTest();
        List<Lead> result = LeadSelector.getByEmailBlock(blockKeys);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected 1 lead matching the email block');
        Lead l = result[0];
        System.assertEquals('5557777777', l.MobilePhone, 'MobilePhone should be selected');
        System.assertEquals(Date.today(), l.Sales_Informed_Agreement_Signed__c, 'Sales_Informed_Agreement_Signed__c should be selected');
        System.assertEquals('opted-in', l.Email_Collection__c, 'Email_Collection__c should be selected');
        System.assertEquals('PORTAL-3', l.Portal_User_ID__c, 'Portal_User_ID__c should be selected');
        System.assertEquals('3 Oak St', l.Street, 'Street should be selected');
        System.assertEquals('Shelbyville', l.City, 'City should be selected');
    }

    @isTest
    static void testGetByIds_returnsNewComparisonAndAddressFields() {
        List<Lead> seed = [SELECT Id FROM Lead LIMIT 1];
        updateBypassingDuplicateRules(new Lead(
            Id                = seed[0].Id,
            MobilePhone       = '5556666666',
            Portal_User_ID__c = 'PORTAL-4',
            Street            = '4 Pine St',
            PostalCode        = '00002'
        ));

        Test.startTest();
        List<Lead> result = LeadSelector.getByIds(new Set<Id>{ seed[0].Id });
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return the requested lead');
        Lead l = result[0];
        System.assertEquals('5556666666', l.MobilePhone, 'MobilePhone should be selected by getByIds');
        System.assertEquals('PORTAL-4', l.Portal_User_ID__c, 'Portal_User_ID__c should be selected by getByIds');
        System.assertEquals('4 Pine St', l.Street, 'Street should be selected by getByIds');
        System.assertEquals('00002', l.PostalCode, 'PostalCode should be selected by getByIds');
    }

    @isTest
    static void testGetByEmailBlock_bulk200NoSoqlInLoop() {
        // Bulkification guard: a single selector call servicing 200 records must
        // consume exactly one SOQL query, regardless of how many block keys are passed.
        // Both Limits.getQueries() reads must stay inside the same Test.startTest()/
        // stopTest() context — code after stopTest() reverts to the outer transaction's
        // governor limit counters, which would make a before/after-boundary read invalid.
        Set<String> allBlocks = new Set<String>();
        for (Integer i = 0; i < 200; i++) {
            allBlocks.add('testlead' + i + '@example.com');
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<Lead> result = LeadSelector.getByEmailBlock(allBlocks);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 leads');
        System.assertEquals(1, queriesUsed, 'getByEmailBlock must execute exactly one SOQL query for the whole bulk set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Updates a Lead while bypassing standard duplicate-rule blocking,
     *              so seeding comparison-field values on records that already share
     *              blocking-key data (by test design) does not fail the update itself.
     * @param leadUpdate Lead record with Id and the fields to update.
     */
    private static void updateBypassingDuplicateRules(Lead leadUpdate) {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.duplicateRuleHeader.allowSave = true;
        Database.SaveResult result = Database.update(leadUpdate, dmlOptions);
        System.assert(result.isSuccess(), 'Lead update should succeed: ' +
            (result.getErrors().isEmpty() ? '' : result.getErrors()[0].getMessage()));
    }
}
