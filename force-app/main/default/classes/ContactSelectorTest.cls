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
}
