/**
 * @description Test class for ContactDuplicateTriggerHandler.
 *              Verifies: bulk (200 contacts), no-op on untracked field,
 *              and that only Open/Partial clusters are marked Stale.
 */
@isTest
private class ContactDuplicateTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data factory
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Creates contacts, a cluster, and cluster-member records linking them.
     * Returns the cluster.
     */
    private static DuplicateCluster__c createClusterWithContacts(
        List<Contact> contacts,
        String clusterStatus
    ) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c  = 'Contact',
            Status__c      = clusterStatus,
            ClusterScore__c = 85.0,
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

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: Bulk — 200 contacts, Email change marks clusters Stale
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void bulkEmailChangeMarksClustersStale() {
        // Create 200 contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(
                FirstName = 'First' + i,
                LastName  = 'Last' + i,
                Email     = 'before' + i + '@example.com'
            ));
        }
        insert contacts;

        // Create one cluster per contact (to fully test bulk path)
        // For brevity, create a single cluster with all 200 contacts
        DuplicateCluster__c cluster = createClusterWithContacts(contacts, 'Open');

        Test.startTest();

        // Update Email on all 200 contacts
        for (Contact c : contacts) {
            c.Email = 'after' + c.Id + '@example.com';
        }
        update contacts;

        Test.stopTest();

        // Verify cluster is now Stale
        DuplicateCluster__c updated = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Stale', updated.Status__c,
            'Cluster should be marked Stale after tracked Email change on bulk contacts');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: No-op — updating untracked field (Description) leaves cluster unchanged
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void untrackedFieldChangeDoesNotMarkStale() {
        Contact c = new Contact(
            FirstName = 'Jane',
            LastName  = 'Doe',
            Email     = 'jane@example.com'
        );
        insert c;

        DuplicateCluster__c cluster = createClusterWithContacts(
            new List<Contact>{ c }, 'Open'
        );

        Test.startTest();

        // Update a field not in the tracked set
        c.Description = 'Updated description';
        update c;

        Test.stopTest();

        DuplicateCluster__c unchanged = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Open', unchanged.Status__c,
            'Cluster should remain Open when only an untracked field changes');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: Merged cluster stays Merged — trigger ignores terminal statuses
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergedClusterStaysMergedAfterTrackedFieldChange() {
        Contact c = new Contact(
            FirstName = 'John',
            LastName  = 'Smith',
            Email     = 'john@example.com'
        );
        insert c;

        DuplicateCluster__c cluster = createClusterWithContacts(
            new List<Contact>{ c }, 'Merged'
        );

        Test.startTest();

        c.Email = 'john.new@example.com';
        update c;

        Test.stopTest();

        DuplicateCluster__c unchanged = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Merged', unchanged.Status__c,
            'Merged cluster must not be changed to Stale by the trigger');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: Ignored cluster stays Ignored after tracked field change
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void ignoredClusterStaysIgnoredAfterTrackedFieldChange() {
        Contact c = new Contact(
            FirstName = 'Alice',
            LastName  = 'Brown',
            Phone     = '5551234567'
        );
        insert c;

        DuplicateCluster__c cluster = createClusterWithContacts(
            new List<Contact>{ c }, 'Ignored'
        );

        Test.startTest();

        c.Phone = '5559999999';
        update c;

        Test.stopTest();

        DuplicateCluster__c unchanged = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Ignored', unchanged.Status__c,
            'Ignored cluster must not be changed to Stale by the trigger');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 5: Partial cluster with tracked field change → Stale
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void partialClusterMarkedStaleOnLastNameChange() {
        Contact c = new Contact(
            FirstName = 'Bob',
            LastName  = 'Jones'
        );
        insert c;

        DuplicateCluster__c cluster = createClusterWithContacts(
            new List<Contact>{ c }, 'Partial'
        );

        Test.startTest();

        c.LastName = 'Johnson';
        update c;

        Test.stopTest();

        DuplicateCluster__c updated = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Stale', updated.Status__c,
            'Partial cluster should be marked Stale after LastName change');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 6: Contact not in any cluster — no error, no DML side effects
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void contactNotInClusterHandledGracefully() {
        Contact c = new Contact(
            FirstName = 'Lone',
            LastName  = 'Wolf',
            Email     = 'lone@example.com'
        );
        insert c;

        // No cluster created — contact has no membership

        Test.startTest();

        c.Email = 'newlone@example.com';
        update c;

        Test.stopTest();

        // Simply verify no exception was thrown and count of clusters is 0
        Integer clusterCount = [
            SELECT COUNT()
            FROM   DuplicateCluster__c
        ];
        System.assertEquals(0, clusterCount,
            'No clusters should exist; handler should handle missing memberships gracefully');
    }
}
