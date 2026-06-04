/**
 * @description Test class for DuplicateMergeController.
 *              Verifies: same-object Contact merge, same-object Lead merge,
 *              Mixed (cross-object) path, ignoreCluster, and error paths.
 *
 *              Note: Cross-object merge is tested for correct jobId return only
 *              (the actual Queueable execution is covered in CrossObjectMergeQueueableTest).
 */
@isTest
private class DuplicateMergeControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static DuplicateCluster__c createContactCluster(
        List<Contact> contacts,
        String status
    ) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = status,
            ClusterScore__c = 88.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>();
        Boolean first = true;
        for (Contact c : contacts) {
            members.add(new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(c.Id),
                ObjectType__c = 'Contact',
                IsMaster__c   = first
            ));
            first = false;
        }
        insert members;
        return cluster;
    }

    private static DuplicateCluster__c createLeadCluster(
        List<Lead> leads,
        String status
    ) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Lead',
            Status__c       = status,
            ClusterScore__c = 82.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>();
        Boolean first = true;
        for (Lead l : leads) {
            members.add(new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(l.Id),
                ObjectType__c = 'Lead',
                IsMaster__c   = first
            ));
            first = false;
        }
        insert members;
        return cluster;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Same-object Contact-Contact merge completes, cluster = Merged
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeContactClusterMarksMerged() {
        Contact master    = new Contact(FirstName = 'Alice', LastName = 'Alpha', Email = 'alice@example.com');
        Contact duplicate = new Contact(FirstName = 'Alice', LastName = 'Alpha', Email = 'alice2@example.com');
        insert new List<Contact>{ master, duplicate };

        DuplicateCluster__c cluster = createContactCluster(
            new List<Contact>{ master, duplicate }, 'Open'
        );

        Test.startTest();

        Map<String, Object> result = DuplicateMergeController.mergeCluster(
            String.valueOf(cluster.Id),
            String.valueOf(master.Id),
            null
        );

        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'mergeCluster should return success=true for same-object Contact merge');

        DuplicateCluster__c updated = [
            SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id LIMIT 1
        ];
        System.assertEquals('Merged', updated.Status__c,
            'Cluster status should be Merged after same-object Contact merge');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: Same-object Lead-Lead merge completes
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeLeadClusterMarksMerged() {
        Lead master    = new Lead(FirstName = 'Bob', LastName = 'Beta', Company = 'Acme', Email = 'bob@example.com');
        Lead duplicate = new Lead(FirstName = 'Bob', LastName = 'Beta', Company = 'Acme', Email = 'bob2@example.com');
        insert new List<Lead>{ master, duplicate };

        DuplicateCluster__c cluster = createLeadCluster(
            new List<Lead>{ master, duplicate }, 'Open'
        );

        Test.startTest();

        Map<String, Object> result = DuplicateMergeController.mergeCluster(
            String.valueOf(cluster.Id),
            String.valueOf(master.Id),
            null
        );

        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'mergeCluster should return success=true for same-object Lead merge');

        DuplicateCluster__c updated = [
            SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id LIMIT 1
        ];
        System.assertEquals('Merged', updated.Status__c,
            'Cluster status should be Merged after same-object Lead merge');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: Mixed cluster returns jobId (async path)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mixedClusterReturnsJobId() {
        // A Mixed cluster needs a Lead member + a Contact member (the master)
        Lead   leadRecord    = new Lead(FirstName = 'Charlie', LastName = 'C', Company = 'Acme', Email = 'charlie@example.com');
        Contact contactMaster = new Contact(FirstName = 'Charlie', LastName = 'C', Email = 'charlie.c@example.com');
        insert leadRecord;
        insert contactMaster;

        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Mixed',
            Status__c       = 'Open',
            ClusterScore__c = 78.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;

        insert new List<DuplicateClusterMember__c>{
            new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(contactMaster.Id),
                ObjectType__c = 'Contact',
                IsMaster__c   = true
            ),
            new DuplicateClusterMember__c(
                Cluster__c    = cluster.Id,
                RecordId__c   = String.valueOf(leadRecord.Id),
                ObjectType__c = 'Lead',
                IsMaster__c   = false
            )
        };

        Test.startTest();

        Map<String, Object> result = DuplicateMergeController.mergeCluster(
            String.valueOf(cluster.Id),
            String.valueOf(contactMaster.Id),
            null
        );

        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Mixed cluster merge should initiate successfully');
        System.assertNotNull(result.get('jobId'),
            'Cross-object merge should return a non-null jobId');
        System.assert(String.isNotBlank((String) result.get('jobId')),
            'jobId should be a non-blank string');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: ignoreCluster creates DuplicateIgnore__c records + sets Ignored
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void ignoreClusterCreatesIgnoreRecordsAndUpdatesStatus() {
        Contact c1 = new Contact(FirstName = 'Dana', LastName = 'D1');
        Contact c2 = new Contact(FirstName = 'Dana', LastName = 'D2');
        Contact c3 = new Contact(FirstName = 'Dana', LastName = 'D3');
        insert new List<Contact>{ c1, c2, c3 };

        DuplicateCluster__c cluster = createContactCluster(
            new List<Contact>{ c1, c2, c3 }, 'Open'
        );

        Test.startTest();

        DuplicateMergeController.ignoreCluster(
            String.valueOf(cluster.Id),
            'Not actually duplicates'
        );

        Test.stopTest();

        // 3 contacts → C(3,2) = 3 ignore pairs
        Integer ignoreCount = [
            SELECT COUNT()
            FROM   DuplicateIgnore__c
        ];
        System.assertEquals(3, ignoreCount,
            'Three ignore pair records should be created for a 3-member cluster');

        DuplicateCluster__c updated = [
            SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id LIMIT 1
        ];
        System.assertEquals('Ignored', updated.Status__c,
            'Cluster status should be Ignored after ignoreCluster call');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 5: mergeCluster — blank clusterId throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeClusterBlankClusterIdThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DuplicateMergeController.mergeCluster(null, 'someId', null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown when clusterId is blank');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 6: mergeCluster — blank masterId throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeClusterBlankMasterIdThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DuplicateMergeController.mergeCluster('someClusterId', null, null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown when masterId is blank');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 7: mergeCluster — non-existent cluster throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeClusterNonExistentClusterThrowsException() {
        Boolean exceptionThrown = false;

        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 75.0,
            DetectedDate__c = DateTime.now()
        );
        insert cluster;
        Id deletedId = cluster.Id;
        delete cluster;

        Contact c = new Contact(FirstName = 'Test', LastName = 'Master');
        insert c;

        Test.startTest();
        try {
            DuplicateMergeController.mergeCluster(
                String.valueOf(deletedId),
                String.valueOf(c.Id),
                null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown for a non-existent cluster');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 8: ignoreCluster — blank clusterId throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void ignoreClusterBlankIdThrowsException() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            DuplicateMergeController.ignoreCluster(null, 'reason');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'AuraHandledException should be thrown when clusterId is blank');
    }
}
