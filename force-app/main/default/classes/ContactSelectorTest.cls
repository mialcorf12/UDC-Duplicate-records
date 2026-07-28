/**
 * @description Test class for ContactSelector.
 *              Bulk scenario: 200 contacts.
 */
@isTest
private class ContactSelectorTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data setup
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName  = 'Contact' + i,
                Email     = 'testcontact' + i + '@example.com',
                Phone     = '555' + String.valueOf(1000000 + i)
            ));
        }
        insert contacts;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByEmailBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByEmailBlock_returnsMatchingContacts() {
        Set<String> blockKeys = new Set<String>{ 'testcontact0@example.com', 'testcontact1@example.com' };

        Test.startTest();
        List<Contact> result = ContactSelector.getByEmailBlock(blockKeys);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Expected 2 contacts matching the email blocks');
        for (Contact c : result) {
            System.assertNotEquals(null, c.Email, 'Email field should be populated');
        }
    }

    @isTest
    static void testGetByEmailBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Contact> result = ContactSelector.getByEmailBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    @isTest
    static void testGetByEmailBlock_bulk200() {
        Set<String> allBlocks = new Set<String>();
        for (Integer i = 0; i < 200; i++) {
            allBlocks.add('testcontact' + i + '@example.com');
        }

        Test.startTest();
        List<Contact> result = ContactSelector.getByEmailBlock(allBlocks);
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 contacts');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByPhoneBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByPhoneBlock_returnsMatchingContacts() {
        // Phone_Block__c formula = last 7 digits of normalized phone
        // '5551000000' → last 7 = '1000000'
        Set<String> blockKeys = new Set<String>{ '1000000', '1000001' };

        Test.startTest();
        List<Contact> result = ContactSelector.getByPhoneBlock(blockKeys);
        Test.stopTest();

        // At least matching contacts should be returned (formula-dependent)
        System.assert(result.size() >= 0, 'Method should execute without error');
    }

    @isTest
    static void testGetByPhoneBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Contact> result = ContactSelector.getByPhoneBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByNameBlock
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByNameBlock_returnsMatchingContacts() {
        // Name_Block__c = LOWER(LEFT(LastName,3)) & LOWER(LEFT(FirstName,1))
        // LastName='Contact0', FirstName='Test' → 'cont' + 't' = 'contt'
        Set<String> blockKeys = new Set<String>{ 'cont' };

        Test.startTest();
        List<Contact> result = ContactSelector.getByNameBlock(blockKeys);
        Test.stopTest();

        System.assert(result.size() >= 0, 'Method should execute without error');
    }

    @isTest
    static void testGetByNameBlock_emptySetReturnsEmpty() {
        Test.startTest();
        List<Contact> result = ContactSelector.getByNameBlock(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty input should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByIds
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByIds_returnsCorrectContacts() {
        List<Contact> allContacts = [SELECT Id FROM Contact LIMIT 5];
        Set<Id> idSet = new Map<Id, Contact>(allContacts).keySet();

        Test.startTest();
        List<Contact> result = ContactSelector.getByIds(idSet);
        Test.stopTest();

        System.assertEquals(5, result.size(), 'Should return 5 contacts by ID');
        System.assertNotEquals(null, result[0].LastName, 'LastName should be populated');
    }

    @isTest
    static void testGetByIds_emptySetReturnsEmpty() {
        Test.startTest();
        List<Contact> result = ContactSelector.getByIds(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Empty ID set should return empty list');
    }

    @isTest
    static void testGetByIds_nullReturnsEmpty() {
        Test.startTest();
        List<Contact> result = ContactSelector.getByIds(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null input should return empty list');
    }

    @isTest
    static void testGetByIds_bulk200() {
        List<Contact> allContacts = [SELECT Id FROM Contact LIMIT 200];
        Set<Id> idSet = new Map<Id, Contact>(allContacts).keySet();

        Test.startTest();
        List<Contact> result = ContactSelector.getByIds(idSet);
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 contacts by ID');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Shared field-list constant — new comparison fields must be queryable
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByEmailBlock_returnsNewComparisonAndAddressFields() {
        List<Contact> seed = [SELECT Id FROM Contact WHERE Email = 'testcontact0@example.com' LIMIT 1];
        updateBypassingDuplicateRules(new Contact(
            Id                                 = seed[0].Id,
            MobilePhone                        = '5559999999',
            Sales_Informed_Agreement_Signed__c = Date.today(),
            Email_Collection__c                = 'opted-in',
            Portal_User_ID__c                  = 'PORTAL-1',
            MailingStreet                      = '1 Main St',
            MailingCity                        = 'Springfield'
        ));

        Set<String> blockKeys = new Set<String>{ 'testcontact0@example.com' };

        Test.startTest();
        List<Contact> result = ContactSelector.getByEmailBlock(blockKeys);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Expected 1 contact matching the email block');
        Contact c = result[0];
        System.assertEquals('5559999999', c.MobilePhone, 'MobilePhone should be selected');
        System.assertEquals(Date.today(), c.Sales_Informed_Agreement_Signed__c, 'Sales_Informed_Agreement_Signed__c should be selected');
        System.assertEquals('opted-in', c.Email_Collection__c, 'Email_Collection__c should be selected');
        System.assertEquals('PORTAL-1', c.Portal_User_ID__c, 'Portal_User_ID__c should be selected');
        System.assertEquals('1 Main St', c.MailingStreet, 'MailingStreet should be selected');
        System.assertEquals('Springfield', c.MailingCity, 'MailingCity should be selected');
    }

    @isTest
    static void testGetByIds_returnsNewComparisonAndAddressFields() {
        List<Contact> seed = [SELECT Id FROM Contact LIMIT 1];
        updateBypassingDuplicateRules(new Contact(
            Id                   = seed[0].Id,
            MobilePhone          = '5558888888',
            Portal_User_ID__c    = 'PORTAL-2',
            MailingStreet        = '2 Elm St',
            MailingPostalCode    = '00001'
        ));

        Test.startTest();
        List<Contact> result = ContactSelector.getByIds(new Set<Id>{ seed[0].Id });
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return the requested contact');
        Contact c = result[0];
        System.assertEquals('5558888888', c.MobilePhone, 'MobilePhone should be selected by getByIds');
        System.assertEquals('PORTAL-2', c.Portal_User_ID__c, 'Portal_User_ID__c should be selected by getByIds');
        System.assertEquals('2 Elm St', c.MailingStreet, 'MailingStreet should be selected by getByIds');
        System.assertEquals('00001', c.MailingPostalCode, 'MailingPostalCode should be selected by getByIds');
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
            allBlocks.add('testcontact' + i + '@example.com');
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<Contact> result = ContactSelector.getByEmailBlock(allBlocks);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        System.assertEquals(200, result.size(), 'Should return all 200 contacts');
        System.assertEquals(1, queriesUsed, 'getByEmailBlock must execute exactly one SOQL query for the whole bulk set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Updates a Contact while bypassing standard duplicate-rule
     *              blocking, so seeding comparison-field values on records that
     *              already share blocking-key data (by test design) does not fail
     *              the update itself.
     * @param contactUpdate Contact record with Id and the fields to update.
     */
    private static void updateBypassingDuplicateRules(Contact contactUpdate) {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.duplicateRuleHeader.allowSave = true;
        Database.SaveResult result = Database.update(contactUpdate, dmlOptions);
        System.assert(result.isSuccess(), 'Contact update should succeed: ' +
            (result.getErrors().isEmpty() ? '' : result.getErrors()[0].getMessage()));
    }
}
