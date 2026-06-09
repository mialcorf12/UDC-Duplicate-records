/**
 * @description Tests for BulkMergeBatch — bulk merge of Open clusters by score and object type.
 */
@isTest
private class BulkMergeBatchTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static DuplicateCluster__c insertCluster(String objectType, Decimal score, String status) {
        DuplicateCluster__c c = new DuplicateCluster__c(
            ObjectType__c   = objectType,
            Status__c       = status,
            ClusterScore__c = score,
            DetectedDate__c = DateTime.now()
        );
        insert c;
        return c;
    }

    private static void insertMember(Id clusterId, Id recordId, String objectType, Boolean isMaster) {
        insert new DuplicateClusterMember__c(
            Cluster__c    = clusterId,
            RecordId__c   = String.valueOf(recordId),
            ObjectType__c = objectType,
            IsMaster__c   = isMaster
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Clusters at score >= 100 get merged; score < 100 is skipped
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergesClusterAtOrAboveMinScoreOnly() {
        Contact c1 = new Contact(FirstName = 'Bulk', LastName = 'One');
        Contact c2 = new Contact(FirstName = 'Bulk', LastName = 'Two');
        Contact c3 = new Contact(FirstName = 'Bulk', LastName = 'Three');
        Contact c4 = new Contact(FirstName = 'Bulk', LastName = 'Four');
        insert new List<Contact>{ c1, c2, c3, c4 };

        DuplicateCluster__c highCluster = insertCluster('Contact', 100, 'Open');
        insertMember(highCluster.Id, c1.Id, 'Contact', true);
        insertMember(highCluster.Id, c2.Id, 'Contact', false);

        DuplicateCluster__c lowCluster = insertCluster('Contact', 80, 'Open');
        insertMember(lowCluster.Id, c3.Id, 'Contact', true);
        insertMember(lowCluster.Id, c4.Id, 'Contact', false);

        Test.startTest();
        Database.executeBatch(new BulkMergeBatch(100, null), 1);
        Test.stopTest();

        DuplicateCluster__c updatedHigh = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :highCluster.Id];
        DuplicateCluster__c updatedLow  = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :lowCluster.Id];

        System.assertEquals('Merged', updatedHigh.Status__c, 'Score-100 cluster should be merged');
        System.assertEquals('Open',   updatedLow.Status__c,  'Score-80 cluster should remain open');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: objectType filter — Contact-only run skips Lead clusters
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void objectTypeFilterSkipsNonMatchingClusters() {
        Contact c1 = new Contact(FirstName = 'Type', LastName = 'One');
        Contact c2 = new Contact(FirstName = 'Type', LastName = 'Two');
        insert new List<Contact>{ c1, c2 };

        Lead l1 = new Lead(FirstName = 'Type', LastName = 'Three', Company = 'Acme');
        Lead l2 = new Lead(FirstName = 'Type', LastName = 'Four',  Company = 'Acme');
        insert new List<Lead>{ l1, l2 };

        DuplicateCluster__c contactCluster = insertCluster('Contact', 100, 'Open');
        insertMember(contactCluster.Id, c1.Id, 'Contact', true);
        insertMember(contactCluster.Id, c2.Id, 'Contact', false);

        DuplicateCluster__c leadCluster = insertCluster('Lead', 100, 'Open');
        insertMember(leadCluster.Id, l1.Id, 'Lead', true);
        insertMember(leadCluster.Id, l2.Id, 'Lead', false);

        Test.startTest();
        Database.executeBatch(new BulkMergeBatch(100, 'Contact'), 1);
        Test.stopTest();

        DuplicateCluster__c updatedContact = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :contactCluster.Id];
        DuplicateCluster__c updatedLead    = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :leadCluster.Id];

        System.assertEquals('Merged', updatedContact.Status__c, 'Contact cluster should be merged');
        System.assertEquals('Open',   updatedLead.Status__c,    'Lead cluster should be untouched');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: No matching clusters — batch completes without errors
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void emptyResultSetCompletesCleanly() {
        Test.startTest();
        Id jobId = Database.executeBatch(new BulkMergeBatch(100, null), 1);
        Test.stopTest();

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals(0, job.NumberOfErrors, 'Batch should complete with no errors on empty result');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: launchBulkMerge controller method — returns a job ID string
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchBulkMergeReturnsJobId() {
        Test.startTest();
        String jobId = DuplicateMergeController.launchBulkMerge(100, 'Contact');
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'launchBulkMerge should return a job ID');
        System.assert(jobId.length() > 0, 'Job ID should not be empty');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 5: launchBulkMerge — null minScore throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchBulkMergeNullScoreThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            DuplicateMergeController.launchBulkMerge(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for null minScore');
    }
}
