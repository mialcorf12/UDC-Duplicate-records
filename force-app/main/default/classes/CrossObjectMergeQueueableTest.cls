/**
 * @description Test class for CrossObjectMergeQueueable.
 *              Verifies: Lead converted, contacts merged, audit Status=Success.
 *              N-lead chaining: multiple leads processed serially, single audit record.
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
    // Single-lead happy path (existing scenarios, updated constructor)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testExecute_successPath_auditStatusSuccess() {
        Lead lead         = createLead('John', 'Smith', 'john.smith@test.com');
        Contact contact   = createContact('John', 'Smith', 'john.smith@test.com');
        DuplicateCluster__c cluster = createCluster();

        insert new List<DuplicateClusterMember__c>{
            new DuplicateClusterMember__c(Cluster__c = cluster.Id, RecordId__c = String.valueOf(contact.Id), ObjectType__c = 'Contact', IsMaster__c = true,  FieldSnapshotJSON__c = '{}'),
            new DuplicateClusterMember__c(Cluster__c = cluster.Id, RecordId__c = String.valueOf(lead.Id),    ObjectType__c = 'Lead',    IsMaster__c = false, FieldSnapshotJSON__c = '{}')
        };

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, new Map<String, String>(), null
        ));
        Test.stopTest();

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
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, null, null
        ));
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
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, null, null
        ));
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
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, overrides, null
        ));
        Test.stopTest();

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

        Id fakeLead = '00Q000000000001AAA';

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ fakeLead }, contact.Id, cluster.Id, null, null
        ));
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

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, null, null, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created even with null clusterId');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // N-leads scenarios
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testExecute_twoLeads_singleAuditAccumulatesBothIds() {
        // Test.stopTest() processes only the FIRST enqueued job synchronously.
        // The self-chained second job runs in the same startTest/stopTest transaction
        // because Salesforce executes chained Queueables within Test.stopTest().
        Lead lead1    = createLead('Alpha', 'One', 'alpha1@test.com');
        Lead lead2    = createLead('Alpha', 'Two', 'alpha2@test.com');
        Contact contact = createContact('Alpha', 'Master', 'alpha.master@test.com');
        DuplicateCluster__c cluster = createCluster();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead1.Id, lead2.Id }, contact.Id, cluster.Id, null, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [
            SELECT Id, Status__c, MergedRecordIds__c
            FROM   DuplicateMergeAudit__c
        ];
        System.assertEquals(1, audits.size(), 'N-lead merge must use a single shared audit record');
        System.assertEquals('Success', audits[0].Status__c, 'Audit status should be Success after all leads processed');
        System.assert(
            audits[0].MergedRecordIds__c.contains(String.valueOf(lead1.Id)),
            'MergedRecordIds__c must contain first lead ID'
        );
        System.assert(
            audits[0].MergedRecordIds__c.contains(String.valueOf(lead2.Id)),
            'MergedRecordIds__c must contain second lead ID'
        );
    }

    @isTest
    static void testExecute_twoLeads_clusterMergedAfterAllLeads() {
        Lead lead1    = createLead('Beta', 'One', 'beta1@test.com');
        Lead lead2    = createLead('Beta', 'Two', 'beta2@test.com');
        Contact contact = createContact('Beta', 'Master', 'beta.master@test.com');
        DuplicateCluster__c cluster = createCluster();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead1.Id, lead2.Id }, contact.Id, cluster.Id, null, null
        ));
        Test.stopTest();

        DuplicateCluster__c updated = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id];
        System.assertEquals('Merged', updated.Status__c, 'Cluster must be Merged only after the last lead is processed');
    }

    @isTest
    static void testExecute_firstLeadFails_chainStops() {
        Contact contact = createContact('Gamma', 'Master', 'gamma.master@test.com');
        DuplicateCluster__c cluster = createCluster();

        Id fakeLead  = '00Q000000000001AAA';
        Lead realLead = createLead('Gamma', 'Real', 'gamma.real@test.com');

        // Put the bad lead first — chain should stop and never process the real one
        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ fakeLead, realLead.Id }, contact.Id, cluster.Id, null, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Should have exactly 1 audit record');
        System.assertEquals('Failed', audits[0].Status__c, 'Audit must be Failed when first lead fails');

        Lead rl = [SELECT IsConverted FROM Lead WHERE Id = :realLead.Id];
        System.assertEquals(false, rl.IsConverted, 'Second lead must NOT be converted when chain stopped on failure');
    }

    @isTest
    static void testExecute_emptyLeadList_doesNotCreateAudit() {
        Contact contact = createContact('Delta', 'Master', 'delta.master@test.com');
        DuplicateCluster__c cluster = createCluster();

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>(), contact.Id, cluster.Id, null, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Id FROM DuplicateMergeAudit__c];
        System.assertEquals(0, audits.size(), 'Empty lead list should produce no audit record');
    }
}
