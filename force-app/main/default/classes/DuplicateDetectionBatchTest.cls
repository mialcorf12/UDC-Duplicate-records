/**
 * @description Test class for DuplicateDetectionBatch.
 *              Bulk scenario: 5 Contact pairs + 2 matching Leads.
 *              Verifies cluster creation, member creation, and ignored pair skipping.
 */
@isTest
private class DuplicateDetectionBatchTest {

    @TestSetup
    static void makeData() {
        // Create 10 contacts in 5 duplicate pairs sharing the same email block
        List<Contact> contacts = new List<Contact>();

        // Pair 1 — same email
        contacts.add(new Contact(FirstName = 'John',   LastName = 'Smith',   Email = 'john.smith@acme.com',   Phone = '5551000001'));
        contacts.add(new Contact(FirstName = 'Jon',    LastName = 'Smith',   Email = 'john.smith@acme.com',   Phone = '5551000001'));

        // Pair 2 — same email
        contacts.add(new Contact(FirstName = 'Maria',  LastName = 'Garcia',  Email = 'maria.garcia@corp.com', Phone = '5552000001'));
        contacts.add(new Contact(FirstName = 'Marie',  LastName = 'Garcia',  Email = 'maria.garcia@corp.com', Phone = '5552000001'));

        // Pair 3 — same email
        contacts.add(new Contact(FirstName = 'Robert', LastName = 'Johnson', Email = 'rjohnson@biz.com',      Phone = '5553000001'));
        contacts.add(new Contact(FirstName = 'Rob',    LastName = 'Johnson', Email = 'rjohnson@biz.com',      Phone = '5553000001'));

        // Pair 4 — same email
        contacts.add(new Contact(FirstName = 'Emily',  LastName = 'Davis',   Email = 'emily.davis@net.com',   Phone = '5554000001'));
        contacts.add(new Contact(FirstName = 'Em',     LastName = 'Davis',   Email = 'emily.davis@net.com',   Phone = '5554000001'));

        // Pair 5 — same email (this pair will be pre-ignored)
        contacts.add(new Contact(FirstName = 'Carlos', LastName = 'Lopez',   Email = 'clopez@example.com',    Phone = '5555000001'));
        contacts.add(new Contact(FirstName = 'Carl',   LastName = 'Lopez',   Email = 'clopez@example.com',    Phone = '5555000001'));

        insert contacts;

        // Create 2 Leads matching the first two email blocks
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'John',  LastName = 'Smith',  Email = 'john.smith@acme.com',   Phone = '5551000001', Company = 'Acme'),
            new Lead(FirstName = 'Maria', LastName = 'Garcia', Email = 'maria.garcia@corp.com', Phone = '5552000001', Company = 'Corp')
        };
        insert leads;

        // Pre-insert an ignore for pair 5 (clopez@example.com pair)
        // We need the actual IDs to build the pair key, so query them back
        List<Contact> lopezContacts = [
            SELECT Id FROM Contact WHERE Email = 'clopez@example.com' ORDER BY FirstName ASC
        ];
        String id1 = String.valueOf(lopezContacts[0].Id);
        String id2 = String.valueOf(lopezContacts[1].Id);
        String pairKey = (id1 < id2) ? id1 + '_' + id2 : id2 + '_' + id1;

        insert new DuplicateIgnore__c(
            PairKey__c    = pairKey,
            Reason__c     = 'Pre-existing ignore for test',
            IgnoredDate__c = DateTime.now()
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main batch execution test
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testBatch_createsClustersForDuplicatePairs() {
        Test.startTest();
        DuplicateDetectionBatch batch = new DuplicateDetectionBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Should have at least 4 clusters (pairs 1–4; pair 5 is ignored)
        List<DuplicateCluster__c> clusters = [SELECT Id, Status__c, BlockingKey__c FROM DuplicateCluster__c];
        System.assert(clusters.size() >= 4, 'Expected at least 4 clusters created, got: ' + clusters.size());

        // All created clusters should be Open
        for (DuplicateCluster__c cluster : clusters) {
            System.assertEquals('Open', cluster.Status__c, 'New clusters should have Status = Open');
        }
    }

    @isTest
    static void testBatch_createsMembersWithFieldSnapshot() {
        Test.startTest();
        Database.executeBatch(new DuplicateDetectionBatch(), 200);
        Test.stopTest();

        List<DuplicateClusterMember__c> members = [
            SELECT Id, RecordId__c, ObjectType__c, IsMaster__c, FieldSnapshotJSON__c, Cluster__c
            FROM   DuplicateClusterMember__c
        ];

        System.assert(members.size() > 0, 'Expected cluster members to be created');

        // Verify each member has a valid JSON snapshot
        for (DuplicateClusterMember__c m : members) {
            System.assertNotEquals(null, m.FieldSnapshotJSON__c, 'FieldSnapshotJSON__c should not be null');
            System.assertNotEquals('', m.FieldSnapshotJSON__c, 'FieldSnapshotJSON__c should not be empty');

            Map<String, Object> snapshot = (Map<String, Object>) JSON.deserializeUntyped(m.FieldSnapshotJSON__c);
            System.assertEquals(5, snapshot.size(), 'Snapshot must have exactly 5 fields');
            System.assert(snapshot.containsKey('Email'),     'Snapshot must contain Email');
            System.assert(snapshot.containsKey('Phone'),     'Snapshot must contain Phone');
            System.assert(snapshot.containsKey('FirstName'), 'Snapshot must contain FirstName');
            System.assert(snapshot.containsKey('LastName'),  'Snapshot must contain LastName');
            System.assert(snapshot.containsKey('Company'),   'Snapshot must contain Company');
        }
    }

    @isTest
    static void testBatch_ignoredPairNotIncluded() {
        // Record the Lopez contacts' IDs before running batch
        List<Contact> lopezContacts = [
            SELECT Id FROM Contact WHERE Email = 'clopez@example.com'
        ];
        Set<String> lopezIds = new Set<String>();
        for (Contact c : lopezContacts) {
            lopezIds.add(String.valueOf(c.Id));
        }

        Test.startTest();
        Database.executeBatch(new DuplicateDetectionBatch(), 200);
        Test.stopTest();

        // No cluster members should reference the ignored Lopez contacts
        List<DuplicateClusterMember__c> lopezMembers = [
            SELECT Id FROM DuplicateClusterMember__c WHERE RecordId__c IN :lopezIds
        ];
        System.assertEquals(
            0, lopezMembers.size(),
            'Ignored pair should not appear as cluster members'
        );
    }

    @isTest
    static void testBatch_contactLeadPairsCreated() {
        Test.startTest();
        Database.executeBatch(new DuplicateDetectionBatch(), 200);
        Test.stopTest();

        // Clusters with ObjectType = 'Mixed' indicate Contact-Lead pairs
        List<DuplicateCluster__c> mixedClusters = [
            SELECT Id FROM DuplicateCluster__c WHERE ObjectType__c = 'Mixed'
        ];
        System.assert(mixedClusters.size() > 0, 'Expected mixed Contact-Lead clusters to be created');
    }

    @isTest
    static void testBatch_bulkScenario200Contacts() {
        // Create 200 additional contacts with matching email pairs (100 pairs)
        List<Contact> bulkContacts = new List<Contact>();
        for (Integer i = 0; i < 100; i++) {
            String email = 'bulktest' + i + '@example.com';
            bulkContacts.add(new Contact(FirstName = 'Bulk' + i, LastName = 'One', Email = email, Phone = '5556000' + String.valueOf(i).leftPad(3, '0')));
            bulkContacts.add(new Contact(FirstName = 'Bulk' + i, LastName = 'One', Email = email, Phone = '5556000' + String.valueOf(i).leftPad(3, '0')));
        }
        insert bulkContacts;

        Test.startTest();
        Database.executeBatch(new DuplicateDetectionBatch(), 200);
        Test.stopTest();

        // Should not throw governor limit exceptions
        List<DuplicateCluster__c> clusters = [SELECT Id FROM DuplicateCluster__c];
        System.assert(clusters.size() > 0, 'Bulk run should create clusters without governor limit errors');
    }
}
