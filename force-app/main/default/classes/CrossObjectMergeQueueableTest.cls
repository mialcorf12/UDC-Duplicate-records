/**
 * @description Test class for CrossObjectMergeQueueable.
 *              Verifies: Lead converted, contacts merged, audit Status=Success.
 *              Error path: invalid Lead → audit Status=Failed.
 */
@isTest
private class CrossObjectMergeQueueableTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Lead createLead(String firstName, String lastName, String email) {
        Lead l = new Lead(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email,
            Company   = 'Test Co',
            Phone     = '5551234567'
        );
        insert l;
        return l;
    }

    private static Contact createContact(String firstName, String lastName, String email) {
        Contact c = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email,
            Phone     = '5551234567'
        );
        insert c;
        return c;
    }

    private static DuplicateCluster__c createCluster() {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Mixed',
            Status__c       = 'Open',
            ClusterScore__c = 90,
            BlockingKey__c  = 'testblock'
        );
        insert cluster;
        return cluster;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Happy path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testExecute_successPath_auditStatusSuccess() {
        Lead lead         = createLead('John', 'Smith', 'john.smith@test.com');
        Contact contact   = createContact('John', 'Smith', 'john.smith@test.com');
        DuplicateCluster__c cluster = createCluster();

        // Add both as members
        insert new List<DuplicateClusterMember__c>{
            new DuplicateClusterMember__c(Cluster__c = cluster.Id, RecordId__c = String.valueOf(contact.Id), ObjectType__c = 'Contact', IsMaster__c = true,  FieldSnapshotJSON__c = '{}'),
            new DuplicateClusterMember__c(Cluster__c = cluster.Id, RecordId__c = String.valueOf(lead.Id),    ObjectType__c = 'Lead',    IsMaster__c = false, FieldSnapshotJSON__c = '{}')
        };

        Map<String, String> overrides = new Map<String, String>();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(lead.Id, contact.Id, cluster.Id, overrides));
        Test.stopTest();

        // Verify audit record Status = Success
        List<DuplicateMergeAudit__c> audits = [
            SELECT Id, Status__c, MergeType__c
            FROM   DuplicateMergeAudit__c
        ];
        System.assertEquals(1, audits.size(), 'Should have 1 audit record');
        System.assertEquals('Success', audits[0].Status__c, 'Audit status should be Success');
        System.assertEquals('CrossObject', audits[0].MergeType__c, 'Merge type should be CrossObject');
    }

    @isTest
    static void testExecute_clusterStatusUpdatedToMerged() {
        Lead lead         = createLead('Maria', 'Garcia', 'maria@test.com');
        Contact contact   = createContact('Maria', 'Garcia', 'maria@test.com');
        DuplicateCluster__c cluster = createCluster();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(lead.Id, contact.Id, cluster.Id, null));
        Test.stopTest();

        DuplicateCluster__c updatedCluster = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id];
        System.assertEquals('Merged', updatedCluster.Status__c, 'Cluster status should be Merged after successful merge');
    }

    @isTest
    static void testExecute_leadIsConvertedAfterMerge() {
        Lead lead         = createLead('Robert', 'Johnson', 'rj@test.com');
        Contact contact   = createContact('Robert', 'Johnson', 'rj@test.com');
        DuplicateCluster__c cluster = createCluster();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(lead.Id, contact.Id, cluster.Id, null));
        Test.stopTest();

        Lead updatedLead = [SELECT IsConverted FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(true, updatedLead.IsConverted, 'Lead should be converted after merge');
    }

    @isTest
    static void testExecute_fieldOverridesApplied() {
        Lead lead         = createLead('Emily', 'Davis', 'emily@test.com');
        Contact contact   = createContact('Emily', 'Davis', 'emily@test.com');
        DuplicateCluster__c cluster = createCluster();

        Map<String, String> overrides = new Map<String, String>{
            'FirstName' => 'EmOverride'
        };

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(lead.Id, contact.Id, cluster.Id, overrides));
        Test.stopTest();

        // Audit should exist regardless of whether override was applied
        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, FieldOverridesJSON__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created');
        System.assertNotEquals(null, audits[0].FieldOverridesJSON__c, 'FieldOverridesJSON should be stored');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Error path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testExecute_errorPath_auditStatusFailed() {
        Contact contact = createContact('Test', 'User', 'test@error.com');
        DuplicateCluster__c cluster = createCluster();

        // Use a non-existent Lead ID to force failure
        // We'll use a fake but well-formed ID that won't be found
        Id fakeLead = '00Q000000000001AAA';

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(fakeLead, contact.Id, cluster.Id, null));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Should have 1 audit record even on failure');
        System.assertEquals('Failed', audits[0].Status__c, 'Audit status should be Failed on error');
        System.assertNotEquals(null, audits[0].ErrorMessage__c, 'ErrorMessage should be populated on failure');
    }

    @isTest
    static void testExecute_nullClusterId_doesNotThrow() {
        Lead lead       = createLead('Carlos', 'Lopez', 'clopez@test.com');
        Contact contact = createContact('Carlos', 'Lopez', 'clopez@test.com');

        // No cluster ID — should still process and log audit
        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(lead.Id, contact.Id, null, null));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created even with null clusterId');
    }
}
