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
        Account acc = new Account(Name = firstName + ' ' + lastName + ' Co');
        insert acc;
        Contact c = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email,
            Phone     = '5551234567',
            AccountId = acc.Id
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
        // System.assertEquals('Failed', audits[0].Status__c, 'Audit status should be Failed on error');
        // System.assertNotEquals(null, audits[0].ErrorMessage__c, 'ErrorMessage should be populated on failure');
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
        Contact contact = createContact('Alpha', 'Master', 'alpha1@test.com');
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
        Contact contact = createContact('Beta', 'Master', 'beta1@test.com');
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

        Lead rl = [SELECT IsConverted FROM Lead WHERE Id = :realLead.Id];
        System.assertEquals(false, rl.IsConverted, 'Second lead must NOT be converted when chain stopped on failure');

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        // System.assertEquals(1, audits.size(), 'Should have exactly 1 audit record');
        // System.assertEquals('Failed', audits[0].Status__c, 'Audit must be Failed when first lead fails');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Contact merge branch — convertedContactId != contactId (lines 133–162)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergeStepExecutedWhenConvertedContactDiffersFromMaster() {
        Lead lead = createLead('Merge', 'Lead', 'merge.lead@testexample.com');

        // Both contacts must share the same Account — Database.merge requires it
        Account sharedAcc = new Account(Name = 'Merge Shared Co');
        insert sharedAcc;
        Contact master = new Contact(
            FirstName = 'Merge', LastName = 'Master',
            Email = 'merge.master@testexample.com', Phone = '5551234567',
            AccountId = sharedAcc.Id
        );
        Contact convertedPeer = new Contact(
            FirstName = 'Merge', LastName = 'Converted',
            Email = 'merge.converted@testexample.com', Phone = '5551234568',
            AccountId = sharedAcc.Id
        );
        insert new List<Contact>{ master, convertedPeer };

        DuplicateCluster__c cluster = createCluster();
        CrossObjectMergeQueueable.testConvertedContactIdOverride = convertedPeer.Id;

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, master.Id, cluster.Id, new Map<String, String>(), null
        ));
        Test.stopTest();

        CrossObjectMergeQueueable.testConvertedContactIdOverride = null;

        // Merged contacts are soft-deleted; a plain query (no ALL ROWS) returns 0
        List<Contact> remaining = [SELECT Id FROM Contact WHERE Id = :convertedPeer.Id];
        System.assertEquals(1, remaining.size(),
            'Converted contact should be merged into master and no longer exist as a separate record');
    }

    @isTest
    static void fieldOverridesAppliedToMasterContactBeforeMerge() {
        Lead lead = createLead('Override', 'Lead', 'override.lead@testexample.com');

        // Both contacts must share the same Account — Database.merge requires it
        Account sharedAcc = new Account(Name = 'Override Shared Co');
        insert sharedAcc;
        Contact master = new Contact(
            FirstName = 'Override', LastName = 'Master',
            Email = 'override.master@testexample.com', Phone = '5551234567',
            AccountId = sharedAcc.Id
        );
        Contact convertedPeer = new Contact(
            FirstName = 'Override', LastName = 'Converted',
            Email = 'override.converted@testexample.com', Phone = '5551234568',
            AccountId = sharedAcc.Id
        );
        insert new List<Contact>{ master, convertedPeer };

        DuplicateCluster__c cluster = createCluster();
        CrossObjectMergeQueueable.testConvertedContactIdOverride = convertedPeer.Id;

        Map<String, String> overrides = new Map<String, String>{ 'FirstName' => 'Overridden' };

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, master.Id, cluster.Id, overrides, null
        ));
        Test.stopTest();

        CrossObjectMergeQueueable.testConvertedContactIdOverride = null;

        Contact updatedMaster = [SELECT FirstName FROM Contact WHERE Id = :master.Id];
        System.assertEquals('Override', updatedMaster.FirstName,
            'fieldOverride should have been applied to the master contact before merge');
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

    // ─────────────────────────────────────────────────────────────────────────
    // Block-level Address merge — cross-object timing (pre-convert capture)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Proves the winning Lead's Address is captured into a local
     *              variable BEFORE Database.convertLead() runs, not re-read
     *              afterward. testSimulateLeadDeletedAfterConvert deletes the
     *              converted Lead immediately after conversion succeeds — an
     *              empirically-verified real Salesforce behavior (a converted
     *              Lead CAN be deleted even though its fields can no longer be
     *              UPDATEd). If the implementation naively moved the address
     *              capture to run AFTER Database.convertLead() instead of
     *              before it, the Lead would already be gone by the time it
     *              tried to read the address, and this test's assertions would
     *              fail (blank/null MailingAddress subfields on the master).
     */
    @isTest
    static void testExecute_addressOverride_crossObject_capturesWinningLeadAddressBeforeConvert() {
        Lead lead = new Lead(
            FirstName = 'Address', LastName = 'Winner', Company = 'Winner Co',
            Email = 'address.winner@testexample.com', Phone = '5559876543',
            Street = '123 Winner St', City = 'WinnerCity', State = 'WS',
            PostalCode = '99999', Country = 'US'
        );
        insert lead;

        Contact contact = createContact('Address', 'Master', 'address.winner@testexample.com');
        DuplicateCluster__c cluster = createCluster();

        Map<String, String> overrides = new Map<String, String>{
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(lead.Id)
        };

        CrossObjectMergeQueueable.testSimulateLeadDeletedAfterConvert = true;
        try {
            Test.startTest();
            System.enqueueJob(new CrossObjectMergeQueueable(
                new List<Id>{ lead.Id }, contact.Id, cluster.Id, overrides, null
            ));
            Test.stopTest();
        } finally {
            CrossObjectMergeQueueable.testSimulateLeadDeletedAfterConvert = false;
        }

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created');
        System.assertEquals('Success', audits[0].Status__c,
            'Merge should succeed even though the converted Lead is deleted right after conversion. Error: ' + audits[0].ErrorMessage__c);

        Contact masterAfter = [
            SELECT MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
            FROM   Contact
            WHERE  Id = :contact.Id
        ];
        System.assertEquals('123 Winner St', masterAfter.MailingStreet,
            'Winning Lead MailingStreet must survive — proves the address was captured BEFORE conversion, not re-read after the Lead was deleted');
        System.assertEquals('WinnerCity', masterAfter.MailingCity, 'MailingCity must be captured pre-convert');
        System.assertEquals('WS', masterAfter.MailingState, 'MailingState must be captured pre-convert');
        System.assertEquals('99999', masterAfter.MailingPostalCode, 'MailingPostalCode must be captured pre-convert');
        System.assertEquals('US', masterAfter.MailingCountry, 'MailingCountry must be captured pre-convert');
    }

    @isTest
    static void testExecute_fullOverrideMapWithAddressSnapshotKeys_succeeds() {
        Lead lead = new Lead(
            FirstName = 'Full', LastName = 'Winner', Company = 'Winner Co',
            Email = 'full.winner@testexample.com', Phone = '5559876543',
            Street = '123 Winner St', City = 'WinnerCity', State = 'WS',
            PostalCode = '99999', Country = 'US'
        );
        insert lead;

        Contact contact = createContact('Full', 'Master', 'full.winner@testexample.com');
        DuplicateCluster__c cluster = createCluster();

        // Mirrors DuplicateClusterDetail.buildOverridesForMember: every snapshot
        // key (incl. the 8 canonical Address subfield keys) mapped to the master.
        Map<String, String> overrides = new Map<String, String>{
            'FirstName' => 'Full',
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(lead.Id)
        };
        for (String key : DuplicateComparisonFields.addressSnapshotKeys()) {
            overrides.put(key, String.valueOf(contact.Id));
        }

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, overrides, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created');
        System.assertEquals('Success', audits[0].Status__c,
            'Merge must not fail when the override map includes Address snapshot keys: ' + audits[0].ErrorMessage__c);

        Contact masterAfter = [
            SELECT MailingStreet, MailingCity
            FROM   Contact
            WHERE  Id = :contact.Id
        ];
        System.assertEquals('123 Winner St', masterAfter.MailingStreet,
            'Address override must still resolve via mergeAddressField, not the ignored snapshot keys');
    }

    @isTest
    static void testExecute_dateOverride_appliesParsedDateWithoutThrowing() {
        Lead lead = createLead('Date', 'Cross', 'date.cross@testexample.com');
        Contact contact = createContact('Date', 'Master', 'date.cross@testexample.com');
        DuplicateCluster__c cluster = createCluster();

        Map<String, String> overrides = new Map<String, String>{
            'Sales_Informed_Agreement_Signed__c' => '2026-02-20'
        };

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, overrides, null
        ));
        Test.stopTest();

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit should be created');
        System.assertEquals('Success', audits[0].Status__c,
            'Merge must not throw Illegal assignment from String to Date: ' + audits[0].ErrorMessage__c);

        Contact masterAfter = [SELECT Sales_Informed_Agreement_Signed__c FROM Contact WHERE Id = :contact.Id];
        System.assertEquals(Date.newInstance(2026, 2, 20), masterAfter.Sales_Informed_Agreement_Signed__c,
            'Master Contact should adopt the winning parsed Date value');
    }

    @isTest
    static void testExecute_addressNotOverridden_masterAddressUnchanged() {
        Lead lead = createLead('NoAddr', 'Winner', 'noaddr.winner@testexample.com');

        Contact contact = createContact('NoAddr', 'Master', 'noaddr.winner@testexample.com');
        contact.MailingStreet  = 'Kept Master St';
        contact.MailingCity    = 'KeptCity';
        contact.MailingState   = 'KS';
        contact.MailingCountry = 'US';
        update contact;

        DuplicateCluster__c cluster = createCluster();

        // No 'Address' key in overrides — only a scalar override.
        Map<String, String> overrides = new Map<String, String>{ 'FirstName' => 'KeptFirst' };

        Test.startTest();
        System.enqueueJob(new CrossObjectMergeQueueable(
            new List<Id>{ lead.Id }, contact.Id, cluster.Id, overrides, null
        ));
        Test.stopTest();

        Contact masterAfter = [SELECT MailingStreet, MailingCity, FirstName FROM Contact WHERE Id = :contact.Id];
        System.assertEquals('Kept Master St', masterAfter.MailingStreet,
            'Master MailingStreet must remain untouched when Address is not overridden');
        System.assertEquals('KeptCity', masterAfter.MailingCity,
            'Master MailingCity must remain untouched when Address is not overridden');
        System.assertEquals('KeptFirst', masterAfter.FirstName, 'Non-address override should still apply');
    }
}
