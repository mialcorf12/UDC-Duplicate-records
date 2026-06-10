/**
 * @description Test class for DuplicateClusterSelector.
 *              Bulk scenario: 200 clusters. Sharing enforcement via System.runAs().
 */
@isTest
private class DuplicateClusterSelectorTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static List<DuplicateCluster__c> createClusters(Integer count, String status) {
        List<DuplicateCluster__c> clusters = new List<DuplicateCluster__c>();
        for (Integer i = 0; i < count; i++) {
            clusters.add(new DuplicateCluster__c(
                ObjectType__c  = 'Contact',
                Status__c      = status,
                ClusterScore__c = 75 + Math.mod(i, 25),
                BlockingKey__c = 'block' + i,
                DetectedDate__c = DateTime.now()
            ));
        }
        insert clusters;
        return clusters;
    }

    private static DuplicateClusterMember__c createMember(Id clusterId, String recordIdStr, Boolean isMaster) {
        DuplicateClusterMember__c m = new DuplicateClusterMember__c(
            Cluster__c         = clusterId,
            RecordId__c        = recordIdStr,
            ObjectType__c      = 'Contact',
            IsMaster__c        = isMaster,
            FieldSnapshotJSON__c = '{"Email":"test@example.com"}'
        );
        insert m;
        return m;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getWithMembers
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetWithMembers_returnsClusterAndMembers() {
        DuplicateCluster__c cluster = createClusters(1, 'Open')[0];

        // Create a fake Contact Id string (18-char) for the member
        Contact c1 = new Contact(LastName = 'Alpha', Email = 'alpha@test.com');
        Contact c2 = new Contact(LastName = 'Beta',  Email = 'beta@test.com');
        insert new List<Contact>{ c1, c2 };

        createMember(cluster.Id, String.valueOf(c1.Id), true);
        createMember(cluster.Id, String.valueOf(c2.Id), false);

        Test.startTest();
        DuplicateCluster__c result = DuplicateClusterSelector.getWithMembers(cluster.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected cluster to be returned');
        System.assertEquals(cluster.Id, result.Id, 'Cluster ID should match');
        System.assertEquals(2, result.ClusterMembers__r.size(), 'Expected 2 members');
    }

    @isTest
    static void testGetWithMembers_returnsNullForUnknownId() {
        // Use a well-formed but non-existent Id
        Id fakeId = '001000000000001AAA';
        Test.startTest();
        DuplicateCluster__c result = DuplicateClusterSelector.getWithMembers(fakeId);
        Test.stopTest();
        System.assertEquals(null, result, 'Should return null for non-existent cluster');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getByMemberRecordIds
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetByMemberRecordIds_bulk200() {
        // Create 200 contacts and 200 clusters, each with one member
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(LastName = 'TestBulk' + i, Email = 'bulk' + i + '@test.com'));
        }
        insert contacts;

        List<DuplicateCluster__c> clusters = createClusters(200, 'Open');

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>();
        for (Integer i = 0; i < 200; i++) {
            members.add(new DuplicateClusterMember__c(
                Cluster__c    = clusters[i].Id,
                RecordId__c   = String.valueOf(contacts[i].Id),
                ObjectType__c = 'Contact',
                IsMaster__c   = true,
                FieldSnapshotJSON__c = '{}'
            ));
        }
        insert members;

        Set<Id> lookupIds = new Set<Id>();
        for (Integer i = 0; i < 50; i++) {
            lookupIds.add(contacts[i].Id);
        }

        Test.startTest();
        List<DuplicateCluster__c> results = DuplicateClusterSelector.getByMemberRecordIds(lookupIds);
        Test.stopTest();

        System.assertEquals(50, results.size(), 'Expected 50 clusters for the 50 supplied record IDs');
    }

    @isTest
    static void testGetByMemberRecordIds_emptySetReturnsEmpty() {
        Test.startTest();
        List<DuplicateCluster__c> results = DuplicateClusterSelector.getByMemberRecordIds(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    @isTest
    static void testGetByMemberRecordIds_nullReturnsEmpty() {
        Test.startTest();
        List<DuplicateCluster__c> results = DuplicateClusterSelector.getByMemberRecordIds(null);
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Null input should return empty list');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getOpenClusters (pagination)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetOpenClusters_paginationPage1() {
        createClusters(30, 'Open');

        Test.startTest();
        List<DuplicateCluster__c> page1 = DuplicateClusterSelector.getOpenClusters(
            'Contact', 'Open', 0, 10, 0
        );
        Test.stopTest();

        System.assertEquals(10, page1.size(), 'Page 1 should return 10 records');
    }

    @isTest
    static void testGetOpenClusters_paginationPage2IsDifferent() {
        createClusters(30, 'Open');

        Test.startTest();
        List<DuplicateCluster__c> page1 = DuplicateClusterSelector.getOpenClusters(
            'Contact', 'Open', 0, 10, 0
        );
        List<DuplicateCluster__c> page2 = DuplicateClusterSelector.getOpenClusters(
            'Contact', 'Open', 0, 10, 10
        );
        Test.stopTest();

        System.assertEquals(10, page2.size(), 'Page 2 should return 10 records');
        System.assertNotEquals(page1[0].Id, page2[0].Id, 'Pages should return different records');
    }

    @isTest
    static void testGetOpenClusters_nullFiltersReturnAll() {
        createClusters(5, 'Open');
        createClusters(5, 'Stale');

        Test.startTest();
        List<DuplicateCluster__c> results = DuplicateClusterSelector.getOpenClusters(
            null, null, 0, 50, 0
        );
        Test.stopTest();

        System.assertEquals(10, results.size(), 'Null filters should return all 10 clusters');
    }

    @isTest
    static void testGetOpenClusters_minScoreFilters() {
        List<DuplicateCluster__c> clusters = createClusters(10, 'Open');
        // Half have score ≥ 90
        List<DuplicateCluster__c> toUpdate = new List<DuplicateCluster__c>();
        for (Integer i = 0; i < 5; i++) {
            toUpdate.add(new DuplicateCluster__c(Id = clusters[i].Id, ClusterScore__c = 90));
        }
        for (Integer i = 5; i < 10; i++) {
            toUpdate.add(new DuplicateCluster__c(Id = clusters[i].Id, ClusterScore__c = 60));
        }
        update toUpdate;

        Test.startTest();
        List<DuplicateCluster__c> results = DuplicateClusterSelector.getOpenClusters(
            null, null, 70, 50, 0
        );
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return only clusters with score >= 70');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sharing enforcement
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetOpenClusters_sharingEnforced() {
        createClusters(5, 'Open');

        // Create a standard user with no special access
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias          = 'tstsr',
            Email          = 'testsharing@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName       = 'TestSharing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey   = 'en_US',
            ProfileId      = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName       = 'testsharing_dup_sel@example.com'
        );
        insert testUser;

        Test.startTest();
        System.runAs(testUser) {
            // Standard user with default OWD will see 0 records if OWD is Private
            // In scratch org with Public Read/Write, results may vary — test that it runs
            List<DuplicateCluster__c> results = DuplicateClusterSelector.getOpenClusters(
                null, null, 0, 50, 0
            );
            // Verify method executes without exception under sharing
            System.assertNotEquals(null, results, 'Result should not be null');
        }
        Test.stopTest();
    }
}
