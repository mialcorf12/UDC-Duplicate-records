/**
 * @description Test class for DuplicateMergeService.
 *              Covers: Contact-Contact merge, Lead-Lead merge,
 *              cross-object (returns jobId), error path (invalid masterId).
 */
@isTest
private class DuplicateMergeServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static DuplicateCluster__c createContactCluster(List<Contact> contacts) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Contact',
            Status__c       = 'Open',
            ClusterScore__c = 90,
            BlockingKey__c  = 'testblock_contact'
        );
        insert cluster;

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>();
        Boolean first = true;
        for (Contact c : contacts) {
            members.add(new DuplicateClusterMember__c(
                Cluster__c           = cluster.Id,
                RecordId__c          = String.valueOf(c.Id),
                ObjectType__c        = 'Contact',
                IsMaster__c          = first,
                FieldSnapshotJSON__c = '{}'
            ));
            first = false;
        }
        insert members;
        return cluster;
    }

    private static DuplicateCluster__c createLeadCluster(List<Lead> leads) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Lead',
            Status__c       = 'Open',
            ClusterScore__c = 88,
            BlockingKey__c  = 'testblock_lead'
        );
        insert cluster;

        List<DuplicateClusterMember__c> members = new List<DuplicateClusterMember__c>();
        Boolean first = true;
        for (Lead l : leads) {
            members.add(new DuplicateClusterMember__c(
                Cluster__c           = cluster.Id,
                RecordId__c          = String.valueOf(l.Id),
                ObjectType__c        = 'Lead',
                IsMaster__c          = first,
                FieldSnapshotJSON__c = '{}'
            ));
            first = false;
        }
        insert members;
        return cluster;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Contact-Contact merge
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_contactContactMerge_masterSurvives() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'John',  LastName = 'Smith', Email = 'jsmith@test.com'),
            new Contact(FirstName = 'Jon',   LastName = 'Smith', Email = 'jsmith@test.com'),
            new Contact(FirstName = 'Johnny',LastName = 'Smith', Email = 'jsmith@test.com')
        };
        insert contacts;
        Contact master = contacts[0];

        DuplicateCluster__c cluster = createContactCluster(contacts);

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, new Map<String, String>()
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Merge should succeed: ' + result.get('message'));

        // Secondaries should be deleted (merged into master)
        List<Contact> remaining = [SELECT Id FROM Contact WHERE Id IN :new List<Id>{ contacts[1].Id, contacts[2].Id }];
        System.assertEquals(0, remaining.size(), 'Secondary contacts should be deleted after merge');

        // Master should still exist
        List<Contact> masterCheck = [SELECT Id FROM Contact WHERE Id = :master.Id];
        System.assertEquals(1, masterCheck.size(), 'Master contact should still exist');
    }

    @isTest
    static void testMergeSameObject_fieldOverridesApplied() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'OldFirst', LastName = 'Smith', Email = 'override@test.com'),
            new Contact(FirstName = 'Jane',     LastName = 'Smith', Email = 'override@test.com')
        };
        insert contacts;

        DuplicateCluster__c cluster = createContactCluster(contacts);
        Map<String, String> overrides = new Map<String, String>{ 'FirstName' => 'NewFirst' };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, contacts[0].Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Merge with overrides should succeed: ' + result.get('message'));

        Contact masterAfter = [SELECT FirstName FROM Contact WHERE Id = :contacts[0].Id];
        System.assertEquals('NewFirst', masterAfter.FirstName, 'Field override should be applied to master');
    }

    @isTest
    static void testMergeSameObject_clusterStatusUpdatedToMerged() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'A', LastName = 'One', Email = 'a@merged.com'),
            new Contact(FirstName = 'B', LastName = 'One', Email = 'a@merged.com')
        };
        insert contacts;
        DuplicateCluster__c cluster = createContactCluster(contacts);

        Test.startTest();
        DuplicateMergeService.mergeSameObject(cluster.Id, contacts[0].Id, null);
        Test.stopTest();

        DuplicateCluster__c updated = [SELECT Status__c FROM DuplicateCluster__c WHERE Id = :cluster.Id];
        System.assertEquals('Merged', updated.Status__c, 'Cluster status should be Merged after successful merge');
    }

    @isTest
    static void testMergeSameObject_auditRecordInserted() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'Audit', LastName = 'Test', Email = 'audit@test.com'),
            new Contact(FirstName = 'Audit', LastName = 'Test', Email = 'audit@test.com')
        };
        insert contacts;
        DuplicateCluster__c cluster = createContactCluster(contacts);

        Test.startTest();
        DuplicateMergeService.mergeSameObject(cluster.Id, contacts[0].Id, null);
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, MergeType__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Should have 1 audit record');
        System.assertEquals('Success', audits[0].Status__c, 'Audit should be Success');
        System.assertEquals('SameObject', audits[0].MergeType__c, 'Merge type should be SameObject');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lead-Lead merge
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_leadLeadMerge_masterSurvives() {
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'Sales', LastName = 'Lead', Company = 'Acme', Email = 'slead@test.com'),
            new Lead(FirstName = 'Sales', LastName = 'Lead', Company = 'Acme', Email = 'slead@test.com')
        };
        insert leads;
        Lead master = leads[0];

        DuplicateCluster__c cluster = createLeadCluster(leads);

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, null
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Lead-Lead merge should succeed: ' + result.get('message'));

        // Secondary lead should be merged/deleted
        List<Lead> secondaryCheck = [SELECT Id, IsConverted FROM Lead WHERE Id = :leads[1].Id];
        // After merge, the secondary might be deleted or marked as merged
        System.assert(secondaryCheck.isEmpty() || secondaryCheck[0].IsConverted,
            'Secondary lead should be deleted after same-object merge');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cross-object (async)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testInitiateCrossObjectMerge_returnsJobId() {
        Lead lead         = new Lead(FirstName = 'Cross', LastName = 'Object', Company = 'Acme', Email = 'cross@test.com');
        Contact contact   = new Contact(FirstName = 'Cross', LastName = 'Object', Email = 'cross@test.com');
        insert lead;
        insert contact;

        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Mixed',
            Status__c       = 'Open',
            ClusterScore__c = 90,
            BlockingKey__c  = 'cross_block'
        );
        insert cluster;

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.initiateCrossObjectMerge(
            cluster.Id, new List<Id>{ lead.Id }, contact.Id, null
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'initiateCrossObjectMerge should return success=true');
        System.assertNotEquals(null, result.get('jobId'), 'jobId should not be null');
        System.assertNotEquals('', result.get('jobId'), 'jobId should not be empty');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Error path
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_invalidMasterId_auditStatusFailed() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'Error', LastName = 'Path', Email = 'error@test.com'),
            new Contact(FirstName = 'Error', LastName = 'Path', Email = 'error@test.com')
        };
        insert contacts;
        DuplicateCluster__c cluster = createContactCluster(contacts);

        // Use a non-existent master ID (well-formed but not in the cluster)
        Id fakeMasterId = '003000000000001AAA';

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, fakeMasterId, null
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return success=false for invalid master');
        System.assertNotEquals(null, result.get('message'), 'Error message should be set');

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit record should be created');
        System.assertEquals('Failed', audits[0].Status__c, 'Audit status should be Failed');
    }

    @isTest
    static void testMergeSameObject_invalidClusterId_auditStatusFailed() {
        Contact contact = new Contact(FirstName = 'Bad', LastName = 'Cluster', Email = 'bad@test.com');
        insert contact;

        Id fakeClusterId = 'a00000000000001AAA';

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            fakeClusterId, contact.Id, null
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should fail for invalid cluster');

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit record should exist');
        System.assertEquals('Failed', audits[0].Status__c, 'Audit should be Failed');
        System.assertNotEquals(null, audits[0].ErrorMessage__c, 'Error message should be populated');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bulk: 3-record cluster
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_threeContactCluster() {
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'Master', LastName = 'Three', Email = 'three@test.com'),
            new Contact(FirstName = 'Dup1',   LastName = 'Three', Email = 'three@test.com'),
            new Contact(FirstName = 'Dup2',   LastName = 'Three', Email = 'three@test.com')
        };
        insert contacts;

        DuplicateCluster__c cluster = createContactCluster(contacts);
        Contact master = contacts[0];

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, null
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), '3-contact merge should succeed: ' + result.get('message'));
    }
}
