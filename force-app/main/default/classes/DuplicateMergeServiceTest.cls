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

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, MergeType__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Should have 1 audit record');
        System.assertEquals('Success', audits[0].Status__c, 'Audit should be Success. Error: ' + audits[0].ErrorMessage__c);
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

    // ─────────────────────────────────────────────────────────────────────────
    // Block-level Address merge (Contact-Contact)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_addressOverride_contactContactMerge_appliesWinningMailingAddress() {
        Account acc = new Account(Name = 'Addr Merge Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Addr', LastName = 'Master', Email = 'addr.master@test.com',
            AccountId = acc.Id,
            MailingStreet = '1 Old St', MailingCity = 'OldCity', MailingState = 'OS',
            MailingPostalCode = '00000', MailingCountry = 'US'
        );
        Contact winner = new Contact(
            FirstName = 'Addr', LastName = 'Winner', Email = 'addr.master@test.com',
            AccountId = acc.Id,
            MailingStreet = '2 New Ave', MailingCity = 'NewCity', MailingState = 'NS',
            MailingPostalCode = '11111', MailingCountry = 'US'
        );
        insert new List<Contact>{ master, winner };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, winner });
        Map<String, String> overrides = new Map<String, String>{
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(winner.Id)
        };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Address merge should succeed: ' + result.get('message'));

        Contact masterAfter = [
            SELECT MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
            FROM   Contact
            WHERE  Id = :master.Id
        ];
        System.assertEquals('2 New Ave', masterAfter.MailingStreet, 'Master should adopt winning MailingStreet');
        System.assertEquals('NewCity', masterAfter.MailingCity, 'Master should adopt winning MailingCity');
        System.assertEquals('NS', masterAfter.MailingState, 'Master should adopt winning MailingState');
        System.assertEquals('11111', masterAfter.MailingPostalCode, 'Master should adopt winning MailingPostalCode');
        System.assertEquals('US', masterAfter.MailingCountry, 'Master should adopt winning MailingCountry');
    }

    @isTest
    static void testMergeSameObject_addressNotOverridden_masterAddressUnchanged() {
        Account acc = new Account(Name = 'Addr Keep Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Keep', LastName = 'Master', Email = 'keep.master@test.com',
            AccountId = acc.Id,
            MailingStreet = 'Original St', MailingCity = 'OriginalCity',
            MailingState = 'OS', MailingCountry = 'US'
        );
        Contact secondary = new Contact(
            FirstName = 'Keep', LastName = 'Secondary', Email = 'keep.master@test.com',
            AccountId = acc.Id,
            MailingStreet = 'Other St', MailingCity = 'OtherCity',
            MailingState = 'OS', MailingCountry = 'US'
        );
        insert new List<Contact>{ master, secondary };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, secondary });
        // No 'Address' key present — only a scalar override for FirstName.
        Map<String, String> overrides = new Map<String, String>{ 'FirstName' => 'KeptFirst' };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Merge should succeed: ' + result.get('message'));

        Contact masterAfter = [SELECT MailingStreet, MailingCity, FirstName FROM Contact WHERE Id = :master.Id];
        System.assertEquals('Original St', masterAfter.MailingStreet,
            'Master MailingStreet must remain untouched when Address is not overridden');
        System.assertEquals('OriginalCity', masterAfter.MailingCity,
            'Master MailingCity must remain untouched when Address is not overridden');
        System.assertEquals('KeptFirst', masterAfter.FirstName, 'Non-address override should still apply');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Block-level Address merge (Lead-Lead) — symmetry with the Contact-Contact
    // coverage above, exercising applyLeadOverrides' Address branch directly.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_addressOverride_leadLeadMerge_appliesWinningAddress() {
        Lead master = new Lead(
            FirstName = 'LAddr', LastName = 'Master', Company = 'Acme', Email = 'laddr.master@test.com',
            Street = '1 Old Rd', City = 'OldTown', State = 'OS', PostalCode = '00000', Country = 'US'
        );
        Lead winner = new Lead(
            FirstName = 'LAddr', LastName = 'Winner', Company = 'Acme', Email = 'laddr.master@test.com',
            Street = '2 New Blvd', City = 'NewTown', State = 'NS', PostalCode = '22222', Country = 'US'
        );
        insert new List<Lead>{ master, winner };

        DuplicateCluster__c cluster = createLeadCluster(new List<Lead>{ master, winner });
        Map<String, String> overrides = new Map<String, String>{
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(winner.Id)
        };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Lead-Lead address merge should succeed: ' + result.get('message'));

        Lead masterAfter = [SELECT Street, City, State, PostalCode, Country FROM Lead WHERE Id = :master.Id];
        System.assertEquals('2 New Blvd', masterAfter.Street, 'Master should adopt winning Street');
        System.assertEquals('NewTown', masterAfter.City, 'Master should adopt winning City');
        System.assertEquals('NS', masterAfter.State, 'Master should adopt winning State');
        System.assertEquals('22222', masterAfter.PostalCode, 'Master should adopt winning PostalCode');
        System.assertEquals('US', masterAfter.Country, 'Master should adopt winning Country');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Full field-override map (as sent by the LWC's auto-select-to-master):
    // includes the canonical Address snapshot keys (AddressStreet, AddressCity,
    // etc.) alongside the Address key and scalar fields — these snapshot-only
    // keys must be filtered out before the generic put() loop, not passed
    // straight through to SObject.put() (which would throw for both objects).
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_fullOverrideMapWithAddressSnapshotKeys_contactContactMerge_succeeds() {
        Account acc = new Account(Name = 'Full Override Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Full', LastName = 'Master', Email = 'full.master@test.com',
            AccountId = acc.Id,
            MailingStreet = '1 Old St', MailingCity = 'OldCity', MailingState = 'OS',
            MailingPostalCode = '00000', MailingCountry = 'US'
        );
        Contact winner = new Contact(
            FirstName = 'Full', LastName = 'Winner', Email = 'full.master@test.com',
            AccountId = acc.Id,
            MailingStreet = '2 New Ave', MailingCity = 'NewCity', MailingState = 'NS',
            MailingPostalCode = '11111', MailingCountry = 'US'
        );
        insert new List<Contact>{ master, winner };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, winner });

        // Mirrors DuplicateClusterDetail.buildOverridesForMember: every snapshot
        // key (incl. the 8 canonical Address subfield keys) mapped to the master.
        Map<String, String> overrides = new Map<String, String>{
            'FirstName' => 'Full',
            'LastName'  => 'Master',
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(winner.Id)
        };
        for (String key : DuplicateComparisonFields.addressSnapshotKeys()) {
            overrides.put(key, String.valueOf(master.Id));
        }

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Merge must not fail when the override map includes Address snapshot keys: ' + result.get('message'));

        Contact masterAfter = [
            SELECT MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
            FROM   Contact
            WHERE  Id = :master.Id
        ];
        System.assertEquals('2 New Ave', masterAfter.MailingStreet,
            'Address override must still resolve via mergeAddressField, not the ignored snapshot keys');
        System.assertEquals('NewCity', masterAfter.MailingCity, 'Master should adopt winning MailingCity');
    }

    @isTest
    static void testMergeSameObject_fullOverrideMapWithAddressSnapshotKeys_leadLeadMerge_succeeds() {
        Lead master = new Lead(
            FirstName = 'Full', LastName = 'Master', Company = 'Acme', Email = 'full.laddr@test.com',
            Street = '1 Old Rd', City = 'OldTown', State = 'OS', PostalCode = '00000', Country = 'US'
        );
        Lead winner = new Lead(
            FirstName = 'Full', LastName = 'Winner', Company = 'Acme', Email = 'full.laddr@test.com',
            Street = '2 New Blvd', City = 'NewTown', State = 'NS', PostalCode = '22222', Country = 'US'
        );
        insert new List<Lead>{ master, winner };

        DuplicateCluster__c cluster = createLeadCluster(new List<Lead>{ master, winner });

        Map<String, String> overrides = new Map<String, String>{
            'FirstName' => 'Full',
            'LastName'  => 'Master',
            DuplicateComparisonFields.ADDRESS_KEY => String.valueOf(winner.Id)
        };
        for (String key : DuplicateComparisonFields.addressSnapshotKeys()) {
            overrides.put(key, String.valueOf(master.Id));
        }

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Lead merge must not fail when the override map includes Address snapshot keys: ' + result.get('message'));

        Lead masterAfter = [SELECT Street, City, State, PostalCode, Country FROM Lead WHERE Id = :master.Id];
        System.assertEquals('2 New Blvd', masterAfter.Street,
            'Address override must still resolve via mergeAddressField, not the ignored snapshot keys');
        System.assertEquals('NewTown', masterAfter.City, 'Master should adopt winning City');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sales_Informed_Agreement_Signed__c (Date field) override coercion —
    // put() does not coerce a snapshot string into a Date field, so the
    // override loop must special-case it via DuplicateMergeService.putOverrideValue.
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_dateOverride_contactContactMerge_appliesParsedDate() {
        Account acc = new Account(Name = 'Date Override Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Date', LastName = 'Master', Email = 'date.master@test.com', AccountId = acc.Id
        );
        Contact secondary = new Contact(
            FirstName = 'Date', LastName = 'Secondary', Email = 'date.master@test.com', AccountId = acc.Id,
            Sales_Informed_Agreement_Signed__c = Date.newInstance(2026, 1, 15)
        );
        insert new List<Contact>{ master, secondary };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, secondary });
        Map<String, String> overrides = new Map<String, String>{
            'Sales_Informed_Agreement_Signed__c' => '2026-01-15'
        };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Merge must not throw Illegal assignment from String to Date: ' + result.get('message'));

        Contact masterAfter = [SELECT Sales_Informed_Agreement_Signed__c FROM Contact WHERE Id = :master.Id];
        System.assertEquals(Date.newInstance(2026, 1, 15), masterAfter.Sales_Informed_Agreement_Signed__c,
            'Master should adopt the winning parsed Date value');
    }

    @isTest
    static void testMergeSameObject_dateOverride_blankValue_savesNullWithoutThrowing() {
        Account acc = new Account(Name = 'Date Blank Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Date', LastName = 'BlankMaster', Email = 'date.blank@test.com', AccountId = acc.Id,
            Sales_Informed_Agreement_Signed__c = Date.newInstance(2025, 6, 1)
        );
        Contact secondary = new Contact(
            FirstName = 'Date', LastName = 'BlankSecondary', Email = 'date.blank@test.com', AccountId = acc.Id
        );
        insert new List<Contact>{ master, secondary };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, secondary });
        // Winning record's snapshot had no date set — resolves to an empty string.
        Map<String, String> overrides = new Map<String, String>{
            'Sales_Informed_Agreement_Signed__c' => ''
        };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Merge must not throw on a blank date override: ' + result.get('message'));

        Contact masterAfter = [SELECT Sales_Informed_Agreement_Signed__c FROM Contact WHERE Id = :master.Id];
        System.assertEquals(null, masterAfter.Sales_Informed_Agreement_Signed__c,
            'Blank date override should clear the field, not throw');
    }

    @isTest
    static void testMergeSameObject_dateOverride_leadLeadMerge_appliesParsedDate() {
        Lead master = new Lead(
            FirstName = 'Date', LastName = 'Master', Company = 'Acme', Email = 'date.lead@test.com'
        );
        Lead winner = new Lead(
            FirstName = 'Date', LastName = 'Winner', Company = 'Acme', Email = 'date.lead@test.com',
            Sales_Informed_Agreement_Signed__c = Date.newInstance(2026, 3, 10)
        );
        insert new List<Lead>{ master, winner };

        DuplicateCluster__c cluster = createLeadCluster(new List<Lead>{ master, winner });
        Map<String, String> overrides = new Map<String, String>{
            'Sales_Informed_Agreement_Signed__c' => '2026-03-10'
        };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Lead merge must not throw Illegal assignment from String to Date: ' + result.get('message'));

        Lead masterAfter = [SELECT Sales_Informed_Agreement_Signed__c FROM Lead WHERE Id = :master.Id];
        System.assertEquals(Date.newInstance(2026, 3, 10), masterAfter.Sales_Informed_Agreement_Signed__c,
            'Master Lead should adopt the winning parsed Date value');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Contact.Portal_User_ID__c uniqueness safety (spec requirement)
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testMergeSameObject_portalUserIdOverride_nullValue_savesSuccessfully() {
        Account acc = new Account(Name = 'Portal Null Co');
        insert acc;

        Contact master = new Contact(
            FirstName = 'Portal', LastName = 'NullMaster', Email = 'portal.null@test.com',
            AccountId = acc.Id, Portal_User_ID__c = null
        );
        Contact secondary = new Contact(
            FirstName = 'Portal', LastName = 'NullSecondary', Email = 'portal.null@test.com',
            AccountId = acc.Id, Portal_User_ID__c = null
        );
        insert new List<Contact>{ master, secondary };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, secondary });
        // Explicit null override — Salesforce allows multiple nulls on a unique field.
        Map<String, String> overrides = new Map<String, String>{ 'Portal_User_ID__c' => null };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Null Portal_User_ID__c override should save without error: ' + result.get('message'));

        Contact masterAfter = [SELECT Portal_User_ID__c FROM Contact WHERE Id = :master.Id];
        System.assertEquals(null, masterAfter.Portal_User_ID__c, 'Master Portal_User_ID__c should remain null');
    }

    @isTest
    static void testMergeSameObject_portalUserIdOverride_conflictingNonNull_surfacesDmlError() {
        Account acc = new Account(Name = 'Portal Conflict Co');
        insert acc;

        // Unrelated existing Contact already holding the value the override will try to reuse.
        Contact holder = new Contact(
            FirstName = 'Portal', LastName = 'Holder', Email = 'portal.holder@test.com',
            AccountId = acc.Id, Portal_User_ID__c = 'CONFLICT01'
        );
        insert holder;

        Contact master = new Contact(
            FirstName = 'Portal', LastName = 'ConflictMaster', Email = 'portal.conflict@test.com',
            AccountId = acc.Id, Portal_User_ID__c = null
        );
        Contact secondary = new Contact(
            FirstName = 'Portal', LastName = 'ConflictSecondary', Email = 'portal.conflict@test.com',
            AccountId = acc.Id, Portal_User_ID__c = null
        );
        insert new List<Contact>{ master, secondary };

        DuplicateCluster__c cluster = createContactCluster(new List<Contact>{ master, secondary });
        Map<String, String> overrides = new Map<String, String>{ 'Portal_User_ID__c' => 'CONFLICT01' };

        Test.startTest();
        Map<String, Object> result = DuplicateMergeService.mergeSameObject(
            cluster.Id, master.Id, overrides
        );
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Merge must fail, not silently succeed, on a unique-field conflict');
        System.assertNotEquals(null, result.get('message'), 'Error message should be populated');

        List<DuplicateMergeAudit__c> audits = [SELECT Status__c, ErrorMessage__c FROM DuplicateMergeAudit__c];
        System.assertEquals(1, audits.size(), 'Audit record should be created');
        System.assertEquals('Failed', audits[0].Status__c, 'Audit status should be Failed on a DML conflict, not swallowed');
        System.assertNotEquals(null, audits[0].ErrorMessage__c, 'Audit ErrorMessage__c must capture the DML failure');

        // Master must not have been left in a merged/deleted state by a failed transaction.
        Contact masterAfter = [SELECT Id, Portal_User_ID__c FROM Contact WHERE Id = :master.Id];
        System.assertNotEquals('CONFLICT01', masterAfter.Portal_User_ID__c, 'Master must not carry the conflicting value after a failed merge');
    }
}
