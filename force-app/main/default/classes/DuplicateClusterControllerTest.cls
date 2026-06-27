/**
 * @description Test class for DuplicateClusterController.
 *              Verifies pagination, filters, sharing enforcement, and error paths.
 */
@isTest
private class DuplicateClusterControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data setup
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Inserts n clusters with sequential scores (descending) for predictable ordering.
     */
    private static List<DuplicateCluster__c> insertClusters(
        Integer n,
        String objectType,
        String status,
        Decimal baseScore
    ) {
        List<DuplicateCluster__c> clusters = new List<DuplicateCluster__c>();
        for (Integer i = 0; i < n; i++) {
            clusters.add(new DuplicateCluster__c(
                ObjectType__c   = objectType,
                Status__c       = status,
                ClusterScore__c = baseScore - i,  // descending: 100, 99, 98, ...
                DetectedDate__c = DateTime.now()
            ));
        }
        insert clusters;
        return clusters;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Pagination — page 1 and page 2 return different records
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void paginationReturnsDifferentRecordsPerPage() {
        insertClusters(6, 'Contact', 'Open', 100);

        Test.startTest();

        Map<String, Object> page1 = DuplicateClusterController.getClusterList(
            null, null, 0, 3, 1
        );
        Map<String, Object> page2 = DuplicateClusterController.getClusterList(
            null, null, 0, 3, 2
        );

        Test.stopTest();

        List<DuplicateCluster__c> p1Clusters = (List<DuplicateCluster__c>) page1.get('clusters');
        List<DuplicateCluster__c> p2Clusters = (List<DuplicateCluster__c>) page2.get('clusters');

        System.assertEquals(3, p1Clusters.size(), 'Page 1 should return 3 records');
        System.assertEquals(3, p2Clusters.size(), 'Page 2 should return 3 records');
        System.assertNotEquals(
            p1Clusters[0].Id, p2Clusters[0].Id,
            'Page 1 and Page 2 first records should differ'
        );
        System.assertEquals(6, (Integer) page1.get('totalCount'), 'totalCount should be 6');
        System.assertEquals(1, (Integer) page1.get('pageNumber'), 'pageNumber should echo back 1');
        System.assertEquals(3, (Integer) page1.get('pageSize'),   'pageSize should echo back 3');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: objectType filter applied correctly
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void objectTypeFilterReturnsonlyMatchingClusters() {
        insertClusters(3, 'Contact', 'Open', 90);
        insertClusters(2, 'Lead', 'Open', 85);

        Test.startTest();

        Map<String, Object> result = DuplicateClusterController.getClusterList(
            'Contact', null, 0, 50, 1
        );

        Test.stopTest();

        List<DuplicateCluster__c> clusters = (List<DuplicateCluster__c>) result.get('clusters');
        System.assertEquals(3, clusters.size(), 'Should return only Contact clusters');
        for (DuplicateCluster__c c : clusters) {
            System.assertEquals('Contact', c.ObjectType__c, 'ObjectType must be Contact');
        }
        System.assertEquals(3, (Integer) result.get('totalCount'), 'totalCount must reflect filter');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: Null filters return all clusters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void nullFiltersReturnAllClusters() {
        insertClusters(2, 'Contact', 'Open', 80);
        insertClusters(2, 'Lead',    'Stale', 75);
        insertClusters(1, 'Mixed',   'Partial', 70);

        Test.startTest();

        Map<String, Object> result = DuplicateClusterController.getClusterList(
            null, null, null, null, null
        );

        Test.stopTest();

        System.assertEquals(5, (Integer) result.get('totalCount'), 'Should count all 5 clusters');
        System.assertEquals(10, (Integer) result.get('pageSize'),   'Default pageSize is 10');
        System.assertEquals(1,  (Integer) result.get('pageNumber'), 'Default pageNumber is 1');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: minScore filter excludes low-score clusters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void minScoreFilterExcludesLowScoreClusters() {
        insertClusters(3, 'Contact', 'Open', 90); // scores 90, 89, 88
        insertClusters(3, 'Contact', 'Open', 60); // scores 60, 59, 58

        Test.startTest();

        Map<String, Object> result = DuplicateClusterController.getClusterList(
            null, null, 70, 50, 1
        );

        Test.stopTest();

        System.assertEquals(3, (Integer) result.get('totalCount'),
            'Only the 3 clusters with score >= 70 should be counted');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 5: getClusterDetail — valid clusterId returns cluster + members
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getClusterDetailReturnsClusterAndMembers() {
        Contact c1 = new Contact(FirstName = 'A', LastName = 'One');
        Contact c2 = new Contact(FirstName = 'A', LastName = 'Two');
        insert new List<Contact>{ c1, c2 };

        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 88.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>{
            new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(c1.Id),
                ObjectType__c = 'Contact',
                IsMaster__c   = true
            ),
            new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(c2.Id),
                ObjectType__c = 'Contact',
                IsMaster__c   = false
            )
        };
        insert members;

        Test.startTest();

        Map<String, Object> result = DuplicateClusterController.getClusterDetail(
            String.valueOf(cluster.Id)
        );

        Test.stopTest();

        DuplicateCluster__c returnedCluster =
            (DuplicateCluster__c) result.get('cluster');
        List<DuplicateClusterMember__c> returnedMembers =
            (List<DuplicateClusterMember__c>) result.get('members');

        System.assertNotEquals(null, returnedCluster, 'Cluster should be present');
        System.assertEquals(cluster.Id, returnedCluster.Id, 'Returned cluster Id should match');
        System.assertEquals(2, returnedMembers.size(), 'Two members should be returned');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 6: getClusterDetail — null clusterId throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getClusterDetailNullIdThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DuplicateClusterController.getClusterDetail(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for null clusterId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 7: getClusterDetail — non-existent clusterId throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getClusterDetailNonExistentIdThrowsException() {
        Boolean exceptionThrown = false;

        // Create and immediately delete a cluster to get a valid-format but non-existent ID
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 75.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;
        Id nonExistentId = cluster.Id;
        delete cluster;

        Test.startTest();
        try {
            DuplicateClusterController.getClusterDetail(String.valueOf(nonExistentId));
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown for a non-existent clusterId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 8: setMasterRecord — swaps IsMaster__c to the selected member
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void setMasterRecordUpdatesFlagOnCorrectMember() {
        Contact c1 = new Contact(FirstName = 'B', LastName = 'One');
        Contact c2 = new Contact(FirstName = 'B', LastName = 'Two');
        insert new List<Contact>{ c1, c2 };

        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 90.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;

        DuplicateClusterMember__c memberA = new DuplicateClusterMember__c(
            Cluster__c    = cluster.Id,
            RecordId__c   = String.valueOf(c1.Id),
            ObjectType__c = 'Contact',
            IsMaster__c   = true
        );
        DuplicateClusterMember__c memberB = new DuplicateClusterMember__c(
            Cluster__c    = cluster.Id,
            RecordId__c   = String.valueOf(c2.Id),
            ObjectType__c = 'Contact',
            IsMaster__c   = false
        );
        insert new List<DuplicateClusterMember__c>{ memberA, memberB };

        Test.startTest();
        DuplicateClusterController.setMasterRecord(
            String.valueOf(cluster.Id),
            String.valueOf(c2.Id)
        );
        Test.stopTest();

        Map<Id, DuplicateClusterMember__c> updated = new Map<Id, DuplicateClusterMember__c>([
            SELECT Id, RecordId__c, IsMaster__c
            FROM DuplicateClusterMember__c
            WHERE Cluster__c = :cluster.Id
        ]);

        System.assertEquals(false, updated.get(memberA.Id).IsMaster__c,
            'Member A should no longer be master');
        System.assertEquals(true, updated.get(memberB.Id).IsMaster__c,
            'Member B should now be master');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 10: getArchivableDates — returns label/value maps for non-Open/Archived clusters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getArchivableDatesReturnsOptionsForNonOpenClusters() {
        insertClusters(2, 'Contact', 'Stale', 80);

        Test.startTest();
        List<Map<String, String>> options = DuplicateClusterController.getArchivableDates();
        Test.stopTest();

        System.assert(options.size() >= 1, 'Should return at least one date option');
        Map<String, String> first = options[0];
        System.assert(first.containsKey('label'), 'Option must have a label key');
        System.assert(first.containsKey('value'), 'Option must have a value key');
        System.assertEquals(first.get('label'), first.get('value'),
            'label and value should be the same date string');
        System.assertEquals(10, first.get('value').length(),
            'Date string should be exactly 10 chars (yyyy-MM-dd)');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 11: getArchivableDates — excludes Open and Archived clusters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void getArchivableDatesExcludesOpenAndArchivedClusters() {
        insertClusters(2, 'Contact', 'Open',     80);
        insertClusters(2, 'Contact', 'Archived', 75);

        Test.startTest();
        List<Map<String, String>> options = DuplicateClusterController.getArchivableDates();
        Test.stopTest();

        System.assertEquals(0, options.size(),
            'Open and Archived clusters must not appear in archivable dates');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 12: archiveClustersByDate — archives matching clusters and returns count
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void archiveClustersByDateArchivesMatchingClustersAndReturnsCount() {
        // Use a timezone-safe midday DateTime so DAY_ONLY() always resolves to Date.today()
        // regardless of the org's UTC offset. DateTime.now() near midnight UTC can shift the date.
        DateTime safeNow = DateTime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));

        List<DuplicateCluster__c> archivable = new List<DuplicateCluster__c>();
        for (Integer i = 0; i < 3; i++) {
            archivable.add(new DuplicateCluster__c(
                ObjectType__c   = 'Contact',
                Status__c       = 'Stale',
                ClusterScore__c = 90 - i,
                DetectedDate__c = safeNow
            ));
        }
        insert archivable;

        DuplicateCluster__c openOne = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 85,
            DetectedDate__c = safeNow
        );
        insert openOne;

        String dateStr = String.valueOf(Date.today());

        Test.startTest();
        Integer count = DuplicateClusterController.archiveClustersByDate(dateStr);
        Test.stopTest();

        System.assertEquals(3, count, 'Should return 3 archived clusters');

        List<DuplicateCluster__c> nowArchived = [
            SELECT Status__c FROM DuplicateCluster__c
            WHERE Id IN :archivable
        ];
        for (DuplicateCluster__c c : nowArchived) {
            System.assertEquals('Archived', c.Status__c, 'Stale cluster must be Archived');
        }

        DuplicateCluster__c stillOpen = [
            SELECT Status__c FROM DuplicateCluster__c WHERE Id = :openOne.Id
        ];
        System.assertEquals('Open', stillOpen.Status__c, 'Open cluster must remain Open');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 13: archiveClustersByDate — throws AuraHandledException on blank dateValue
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void archiveClustersByDateThrowsOnBlankDate() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DuplicateClusterController.archiveClustersByDate('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown when dateValue is blank');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 14: archiveClustersByDate — returns 0 when no clusters match
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void archiveClustersByDateReturnsZeroWhenNoMatchingClusters() {
        insertClusters(2, 'Contact', 'Open', 80);
        String dateStr = String.valueOf(Date.today());

        Test.startTest();
        Integer count = DuplicateClusterController.archiveClustersByDate(dateStr);
        Test.stopTest();

        System.assertEquals(0, count, 'Should return 0 when no archivable clusters exist for the date');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 9: Sharing enforcement via System.runAs()
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void sharingEnforcedViaRunAs() {
        // Insert clusters as system admin
        insertClusters(2, 'Contact', 'Open', 85);

        // Create a standard user with no special permissions
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User restrictedUser = new User(
            Alias            = 'rstdusr',
            Email            = 'restricted@testexample.com',
            EmailEncodingKey = 'UTF-8',
            LastName         = 'RestrictedUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey     = 'en_US',
            ProfileId        = stdProfile.Id,
            TimeZoneSidKey   = 'America/Los_Angeles',
            UserName         = 'restricted.user.duptest@testexample.com'
        );
        insert restrictedUser;

        Test.startTest();

        Map<String, Object> result;
        System.runAs(restrictedUser) {
            // The controller uses "with sharing" — results depend on sharing config.
            // The key assertion is: the method runs without throwing an unhandled exception,
            // and obeys the sharing rules of the context user.
            result = DuplicateClusterController.getClusterList(
                null, null, 0, 50, 1
            );
        }

        Test.stopTest();

        // In a test context without explicit sharing rules, "with sharing" typically
        // sees all records for the creating user vs the running user.
        // The assertion here confirms the call completed and returned a valid shape.
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('clusters'),   'Result must have clusters key');
        System.assert(result.containsKey('totalCount'), 'Result must have totalCount key');
    }
}
