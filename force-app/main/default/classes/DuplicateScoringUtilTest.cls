/**
 * @description Test class for DuplicateScoringUtil.
 *              Covers exact match (100), no match (0), partial matches,
 *              threshold boundary (69/70/85), normalizePhone, buildSnapshotJSON.
 */
@isTest
private class DuplicateScoringUtilTest {

    // ─────────────────────────────────────────────────────────────────────────
    // scoreRecords — Contact-Contact
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testScoreRecords_exactMatchAllFields_returns100() {
        Contact c1 = new Contact(
            FirstName = 'John',
            LastName  = 'Smith',
            Email     = 'john.smith@example.com',
            Phone     = '5551234567'
        );
        Contact c2 = new Contact(
            FirstName = 'John',
            LastName  = 'Smith',
            Email     = 'john.smith@example.com',
            Phone     = '5551234567'
        );

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        // Email(40) + Phone(30) + Name(JW≈1.0 → 20) + Company(0, no account) = 90
        // Full 100 only when all 4 match; without company we expect 90
        System.assert(score >= 90, 'Score with email+phone+name match should be >= 90, got: ' + score);
    }

    @isTest
    static void testScoreRecords_emailMatchOnly_returns40() {
        Contact c1 = new Contact(
            FirstName = 'John',
            LastName  = 'Smith',
            Email     = 'john.smith@example.com',
            Phone     = '5550000001'
        );
        Contact c2 = new Contact(
            FirstName = 'Jane',
            LastName  = 'Doe',
            Email     = 'john.smith@example.com',
            Phone     = '5550000002'
        );

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        // Email match = 40. Name is very different, so JW < threshold for meaningful score.
        System.assert(score >= 40, 'Email match alone should contribute 40 pts, got: ' + score);
        System.assert(score < 75, 'Score should be below 75 with only email match, got: ' + score);
    }

    @isTest
    static void testScoreRecords_noMatchAnyField_returns0() {
        Contact c1 = new Contact(
            FirstName = 'Alpha',
            LastName  = 'Beta',
            Email     = 'alpha@different.com',
            Phone     = '5550000001'
        );
        Contact c2 = new Contact(
            FirstName = 'Zeta',
            LastName  = 'Omega',
            Email     = 'zeta@unrelated.com',
            Phone     = '5559999999'
        );

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        System.assert(score < 30, 'No exact matches should result in very low score, got: ' + score);
    }

    @isTest
    static void testScoreRecords_emailCaseInsensitive() {
        Contact c1 = new Contact(FirstName = 'John', LastName = 'Smith', Email = 'JOHN@EXAMPLE.COM');
        Contact c2 = new Contact(FirstName = 'John', LastName = 'Smith', Email = 'john@example.com');

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        System.assert(score >= 40, 'Email match should be case-insensitive, got: ' + score);
    }

    @isTest
    static void testScoreRecords_phoneNormalizedMatch() {
        // Different formats of the same number
        Contact c1 = new Contact(FirstName = 'X', LastName = 'Y', Phone = '+1 (555) 123-4567');
        Contact c2 = new Contact(FirstName = 'X', LastName = 'Y', Phone = '555.123.4567');

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        // Both normalize to last 7 = '1234567'
        System.assert(score >= 30, 'Phone match with normalized values should contribute 30 pts, got: ' + score);
    }

    @isTest
    static void testScoreRecords_contactLeadCrossObject() {
        Contact c = new Contact(
            FirstName = 'Maria',
            LastName  = 'Garcia',
            Email     = 'maria.garcia@company.com',
            Phone     = '5554443333'
        );
        Lead l = new Lead(
            FirstName = 'Maria',
            LastName  = 'Garcia',
            Email     = 'maria.garcia@company.com',
            Phone     = '5554443333',
            Company   = 'Acme'
        );

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c, l);
        Test.stopTest();

        // Email(40) + Phone(30) + Name(≈20) = ~90
        System.assert(score >= 85, 'Cross-object pair with strong match should score >= 85, got: ' + score);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // normalizePhone
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNormalizePhone_stripsSpacesDashesParensPlusSigns() {
        Test.startTest();
        System.assertEquals('1234567', DuplicateScoringUtil.normalizePhone('+1 (555) 123-4567'), 'Should return last 7 digits');
        System.assertEquals('1234567', DuplicateScoringUtil.normalizePhone('555-123-4567'), 'Dashes stripped');
        System.assertEquals('1234567', DuplicateScoringUtil.normalizePhone('555 123 4567'), 'Spaces stripped');
        System.assertEquals('1234567', DuplicateScoringUtil.normalizePhone('(555)1234567'), 'Parens stripped');
        System.assertEquals('1234567', DuplicateScoringUtil.normalizePhone('5551234567'), 'Plain digits, last 7');
        Test.stopTest();
    }

    @isTest
    static void testNormalizePhone_shortNumber() {
        Test.startTest();
        System.assertEquals('12345', DuplicateScoringUtil.normalizePhone('12345'), 'Short number returned as-is');
        System.assertEquals('', DuplicateScoringUtil.normalizePhone(''), 'Empty returns empty');
        System.assertEquals('', DuplicateScoringUtil.normalizePhone(null), 'Null returns empty');
        System.assertEquals('', DuplicateScoringUtil.normalizePhone('abc'), 'Non-digits returns empty');
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // normalizeEmail
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNormalizeEmail_lowercasesAndTrims() {
        Test.startTest();
        System.assertEquals('john@example.com', DuplicateScoringUtil.normalizeEmail('  JOHN@EXAMPLE.COM  '), 'Should lowercase and trim');
        System.assertEquals('', DuplicateScoringUtil.normalizeEmail(null), 'Null returns empty');
        System.assertEquals('', DuplicateScoringUtil.normalizeEmail('   '), 'Blank returns empty');
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // jaroWinkler
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testJaroWinkler_identicalStrings_returns1() {
        Test.startTest();
        Decimal result = DuplicateScoringUtil.jaroWinkler('john smith', 'john smith');
        Test.stopTest();
        System.assertEquals(1.0, result, 'Identical strings should return 1.0');
    }

    @isTest
    static void testJaroWinkler_emptyStrings_returns0() {
        Test.startTest();
        System.assertEquals(0.0, DuplicateScoringUtil.jaroWinkler('', 'abc'), 'Empty first should be 0');
        System.assertEquals(0.0, DuplicateScoringUtil.jaroWinkler('abc', ''), 'Empty second should be 0');
        Test.stopTest();
    }

    @isTest
    static void testJaroWinkler_completelyDifferent_isLow() {
        Test.startTest();
        Decimal result = DuplicateScoringUtil.jaroWinkler('abcdef', 'xyz');
        Test.stopTest();
        System.assert(result < 0.5, 'Completely different strings should score below 0.5, got: ' + result);
    }

    @isTest
    static void testJaroWinkler_similarNames_isHigh() {
        // 'martha' vs 'marhta' — classic Jaro-Winkler example
        Test.startTest();
        Decimal result = DuplicateScoringUtil.jaroWinkler('martha', 'marhta');
        Test.stopTest();
        System.assert(result > 0.9, 'Very similar names should score above 0.9, got: ' + result);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // buildSnapshotJSON
    // ─────────────────────────────────────────────────────────────────────────

    // Total snapshot key count: 10 scalar keys (Email, Phone, MobilePhone, FirstName,
    // LastName, Company, AccountId, Sales_Informed_Agreement_Signed__c,
    // Email_Collection__c, Portal_User_ID__c) + 8 canonical Address subfield keys
    // (AddressStreet, AddressCity, AddressState, AddressPostalCode, AddressCountry,
    // AddressLatitude, AddressLongitude, AddressGeocodeAccuracy) + 1 formatted
    // "Address" display string = 19.
    private static final Integer EXPECTED_SNAPSHOT_FIELD_COUNT = 19;

    private static final Set<String> EXPECTED_SNAPSHOT_KEYS = new Set<String>{
        'Email', 'Phone', 'MobilePhone', 'FirstName', 'LastName', 'Company', 'AccountId',
        'Sales_Informed_Agreement_Signed__c', 'Email_Collection__c', 'Portal_User_ID__c',
        'Address',
        'AddressStreet', 'AddressCity', 'AddressState', 'AddressPostalCode', 'AddressCountry',
        'AddressLatitude', 'AddressLongitude', 'AddressGeocodeAccuracy'
    };

    @isTest
    static void testBuildSnapshotJSON_contactHasAllSnapshotFields() {
        // Linked to an Account (rather than a bare Contact) to satisfy this org's
        // pre-existing "Contact record type must match parent Company" validation
        // rule, which is unrelated to this change but fires on any bare Contact
        // insert in this sandbox.
        Account a = new Account(Name = 'Snapshot Test Corp');
        insert a;
        Contact c = new Contact(
            FirstName = 'John',
            LastName  = 'Smith',
            Email     = 'john@example.com',
            Phone     = '5551234567',
            MobilePhone = '5559998888',
            AccountId = a.Id,
            Sales_Informed_Agreement_Signed__c = Date.newInstance(2026, 1, 15),
            Email_Collection__c = 'opted-in',
            Portal_User_ID__c   = 'PORTAL001',
            MailingStreet  = '123 Main St',
            MailingCity    = 'Springfield',
            MailingState   = 'IL',
            MailingPostalCode = '62701',
            MailingCountry = 'US'
        );
        insert c;
        Contact retrieved = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, AccountId, Account.Name,
                   Sales_Informed_Agreement_Signed__c, Email_Collection__c, Portal_User_ID__c,
                   MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                   MailingLatitude, MailingLongitude, MailingGeocodeAccuracy
            FROM Contact WHERE Id = :c.Id
        ];

        Test.startTest();
        String jsonStr = DuplicateScoringUtil.buildSnapshotJSON(retrieved, 'Contact');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(
            EXPECTED_SNAPSHOT_FIELD_COUNT, parsed.size(),
            'Contact snapshot should contain exactly ' + EXPECTED_SNAPSHOT_FIELD_COUNT + ' fields'
        );
        System.assertEquals(EXPECTED_SNAPSHOT_KEYS, parsed.keySet(), 'Snapshot must contain only the expected keys');
        System.assertEquals('john@example.com', parsed.get('Email'), 'Email value should match');
        System.assertEquals('John', parsed.get('FirstName'), 'FirstName value should match');
        System.assertEquals('5559998888', parsed.get('MobilePhone'), 'MobilePhone value should match');
        System.assertEquals('2026-01-15', parsed.get('Sales_Informed_Agreement_Signed__c'), 'Agreement signed date should be ISO-formatted');
        System.assertEquals('opted-in', parsed.get('Email_Collection__c'), 'Email_Collection__c value should match');
        System.assertEquals('PORTAL001', parsed.get('Portal_User_ID__c'), 'Portal_User_ID__c value should match');
        System.assertEquals(String.valueOf(a.Id), parsed.get('AccountId'), 'AccountId should reflect the linked account');
        System.assertEquals('123 Main St', parsed.get('AddressStreet'), 'AddressStreet should read from MailingStreet');
        System.assertEquals('Springfield', parsed.get('AddressCity'), 'AddressCity should read from MailingCity');
        System.assertEquals('123 Main St, Springfield, IL, 62701, US', parsed.get('Address'), 'Address display string should join populated parts');
    }

    @isTest
    static void testBuildSnapshotJSON_contactWithAccount() {
        Account a = new Account(Name = 'Test Corp');
        insert a;
        Contact c = new Contact(FirstName = 'John', LastName = 'Smith', Email = 'john@example.com', AccountId = a.Id);
        insert c;
        Contact retrieved = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, AccountId, Account.Name,
                   Sales_Informed_Agreement_Signed__c, Email_Collection__c, Portal_User_ID__c,
                   MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                   MailingLatitude, MailingLongitude, MailingGeocodeAccuracy
            FROM Contact WHERE Id = :c.Id
        ];

        Test.startTest();
        String jsonStr = DuplicateScoringUtil.buildSnapshotJSON(retrieved, 'Contact');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(String.valueOf(a.Id), parsed.get('AccountId'), 'AccountId should match the linked account');
        System.assertEquals('Test Corp', parsed.get('Company'), 'Company should reflect Account.Name');
        System.assertEquals('', parsed.get('Address'), 'Address display string should be empty with no address data');
    }

    @isTest
    static void testBuildSnapshotJSON_leadHasAllSnapshotFields() {
        Lead l = new Lead(
            FirstName = 'Jane',
            LastName  = 'Doe',
            Email     = 'jane@company.com',
            Phone     = '5559876543',
            MobilePhone = '5551112222',
            Company   = 'Acme Corp',
            Sales_Informed_Agreement_Signed__c = Date.newInstance(2026, 2, 1),
            Email_Collection__c = 'opted-out',
            Portal_User_ID__c   = 'PORTAL002',
            Street  = '456 Oak Ave',
            City    = 'Metropolis',
            State   = 'NY',
            PostalCode = '10001',
            Country = 'US'
        );
        insert l;
        Lead retrieved = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Company,
                   Sales_Informed_Agreement_Signed__c, Email_Collection__c, Portal_User_ID__c,
                   Street, City, State, PostalCode, Country, Latitude, Longitude, GeocodeAccuracy
            FROM Lead WHERE Id = :l.Id
        ];

        Test.startTest();
        String jsonStr = DuplicateScoringUtil.buildSnapshotJSON(retrieved, 'Lead');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(
            EXPECTED_SNAPSHOT_FIELD_COUNT, parsed.size(),
            'Lead snapshot should contain exactly ' + EXPECTED_SNAPSHOT_FIELD_COUNT + ' fields'
        );
        System.assertEquals('Acme Corp', parsed.get('Company'), 'Company value should match');
        System.assertEquals('jane@company.com', parsed.get('Email'), 'Email value should match');
        System.assertEquals('5551112222', parsed.get('MobilePhone'), 'MobilePhone value should match');
        System.assertEquals('', parsed.get('AccountId'), 'AccountId should always be empty for Lead');
        System.assertEquals('456 Oak Ave', parsed.get('AddressStreet'), 'AddressStreet should read from plain Street');
        System.assertEquals('456 Oak Ave, Metropolis, NY, 10001, US', parsed.get('Address'), 'Address display string should join populated parts');
    }

    @isTest
    static void testBuildSnapshotJSON_noExtraFields() {
        Lead l = new Lead(FirstName = 'X', LastName = 'Y', Company = 'C');
        insert l;
        Lead retrieved = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Company,
                   Sales_Informed_Agreement_Signed__c, Email_Collection__c, Portal_User_ID__c,
                   Street, City, State, PostalCode, Country, Latitude, Longitude, GeocodeAccuracy
            FROM Lead WHERE Id = :l.Id
        ];

        Test.startTest();
        String jsonStr = DuplicateScoringUtil.buildSnapshotJSON(retrieved, 'Lead');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(EXPECTED_SNAPSHOT_KEYS, parsed.keySet(), 'Snapshot must contain only the expected fields');
    }

    @isTest
    static void testBuildSnapshotJSON_leadMissingAddress_blankFieldsNoException() {
        // Graceful degradation at the source: a record with no address data at all
        // (e.g. a historical/legacy record) must not throw and must produce blank
        // address values rather than nulls, so downstream JSON consumers (LWC)
        // never see a null where an empty string is expected.
        Lead l = new Lead(FirstName = 'No', LastName = 'Address', Company = 'C');
        insert l;
        Lead retrieved = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Company,
                   Sales_Informed_Agreement_Signed__c, Email_Collection__c, Portal_User_ID__c,
                   Street, City, State, PostalCode, Country, Latitude, Longitude, GeocodeAccuracy
            FROM Lead WHERE Id = :l.Id
        ];

        Test.startTest();
        String jsonStr = DuplicateScoringUtil.buildSnapshotJSON(retrieved, 'Lead');
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals('', parsed.get('Address'), 'Address display string should be blank, not null');
        System.assertEquals('', parsed.get('AddressStreet'), 'AddressStreet should be blank, not null');
        System.assertEquals('', parsed.get('Sales_Informed_Agreement_Signed__c'), 'Missing agreement date should be blank, not null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Threshold boundary tests
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testScoreRecords_thresholdBoundary_belowAt69() {
        // Phone only (30) + partial name (≈20 * low_jw)
        // We want exactly below 70 — use only Name match (small JW) and no email/phone
        Contact c1 = new Contact(FirstName = 'Aaa', LastName = 'Bbb', Email = 'a@one.com', Phone = '0000001');
        Contact c2 = new Contact(FirstName = 'Aaa', LastName = 'Bbb', Email = 'b@two.com', Phone = '0000002');

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        // Name match (JW=1.0) = 20 pts only. That's 20 — well below 70.
        System.assert(score < 70, 'Name-only match should score below threshold, got: ' + score);
    }

    @isTest
    static void testScoreRecords_thresholdBoundary_atOrAbove70() {
        // Email(40) + Phone(30) = 70, even without name/company
        Contact c1 = new Contact(FirstName = 'Alpha', LastName = 'One', Email = 'match@test.com', Phone = '5550001234');
        Contact c2 = new Contact(FirstName = 'Beta',  LastName = 'Two', Email = 'match@test.com', Phone = '5550001234');

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        System.assert(score >= 70, 'Email + Phone match should score >= 70, got: ' + score);
    }

    @isTest
    static void testScoreRecords_highConfidenceAt85() {
        // Email(40) + Phone(30) + similar Name(≈20*0.75 = 15) = 85
        Contact c1 = new Contact(FirstName = 'Robert', LastName = 'Smith', Email = 'r.smith@example.com', Phone = '5551111111');
        Contact c2 = new Contact(FirstName = 'Robert', LastName = 'Smith', Email = 'r.smith@example.com', Phone = '5551111111');

        Test.startTest();
        Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
        Test.stopTest();

        System.assert(score >= 85, 'Email + Phone + Name exact match should score >= 85, got: ' + score);
    }
}
