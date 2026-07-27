/**
 * @description Test class for LeadDuplicateTriggerHandler.
 *              Mirrors the Contact handler test patterns.
 *              Verifies: bulk (200 leads), no-op on untracked field,
 *              and that only Open/Partial clusters are marked Stale.
 */
@isTest
private class LeadDuplicateTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test data factory
    // ─────────────────────────────────────────────────────────────────────────

    private static DuplicateCluster__c createClusterWithLeads(
        List<Lead> leads,
        String clusterStatus
    ) {
        DuplicateCluster__c cluster = new DuplicateCluster__c(
            ObjectType__c   = 'Lead',
            Status__c       = clusterStatus,
            ClusterScore__c = 80.0,
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
    // Scenario 1: Bulk — 200 leads, Email change marks clusters Stale
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void bulkEmailChangeMarksClustersStale() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 200; i++) {
            leads.add(new Lead(
                FirstName = 'LFirst' + i,
                LastName  = 'LLast' + i,
                Company   = 'Acme' + i,
                Email     = 'leadbefore' + i + '@example.com'
            ));
        }
        insert leads;

        DuplicateCluster__c cluster = createClusterWithLeads(leads, 'Open');

        Test.startTest();

        for (Lead l : leads) {
            l.Email = 'leadafter' + l.Id + '@example.com';
        }
        update leads;

        Test.stopTest();

        DuplicateCluster__c updated = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Stale', updated.Status__c,
            'Cluster should be marked Stale after bulk lead Email change');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: No-op — updating untracked field (LeadSource) leaves cluster unchanged
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void untrackedFieldChangeDoesNotMarkStale() {
        Lead l = new Lead(
            FirstName = 'Jane',
            LastName  = 'Doe',
            Company   = 'TestCo',
            Email     = 'janelead@example.com'
        );
        insert l;

        DuplicateCluster__c cluster = createClusterWithLeads(
            new List<Lead>{ l }, 'Open'
        );

        Test.startTest();

        l.LeadSource = 'Web';
        update l;

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
    // Scenario 3: Merged cluster stays Merged after tracked field change
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void mergedClusterStaysMergedAfterTrackedFieldChange() {
        Lead l = new Lead(
            FirstName = 'John',
            LastName  = 'Smith',
            Company   = 'Acme',
            Email     = 'john@example.com'
        );
        insert l;

        DuplicateCluster__c cluster = createClusterWithLeads(
            new List<Lead>{ l }, 'Merged'
        );

        Test.startTest();

        l.Email = 'john.new@example.com';
        update l;

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
        Lead l = new Lead(
            FirstName = 'Alice',
            LastName  = 'Brown',
            Company   = 'Globex',
            Phone     = '5551234567'
        );
        insert l;

        DuplicateCluster__c cluster = createClusterWithLeads(
            new List<Lead>{ l }, 'Ignored'
        );

        Test.startTest();

        l.Phone = '5559999999';
        update l;

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
    // Scenario 5: Partial cluster with tracked Company change → Stale
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void partialClusterMarkedStaleOnCompanyChange() {
        Lead l = new Lead(
            FirstName = 'Bob',
            LastName  = 'Jones',
            Company   = 'OldCompany'
        );
        insert l;

        DuplicateCluster__c cluster = createClusterWithLeads(
            new List<Lead>{ l }, 'Partial'
        );

        Test.startTest();

        l.Company = 'NewCompany';
        update l;

        Test.stopTest();

        DuplicateCluster__c updated = [
            SELECT Status__c
            FROM   DuplicateCluster__c
            WHERE  Id = :cluster.Id
            LIMIT  1
        ];
        System.assertEquals('Stale', updated.Status__c,
            'Partial cluster should be marked Stale after Company change');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 6: Lead not in any cluster — no error, no DML side effects
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void leadNotInClusterHandledGracefully() {
        Lead l = new Lead(
            FirstName = 'Lone',
            LastName  = 'Wolf',
            Company   = 'Solo Inc',
            Email     = 'lonewolf@example.com'
        );
        insert l;

        Test.startTest();

        l.Email = 'newlonewolf@example.com';
        update l;

        Test.stopTest();

        Integer clusterCount = [
            SELECT COUNT()
            FROM   DuplicateCluster__c
        ];
        System.assertEquals(0, clusterCount,
            'No clusters should exist; handler should handle missing memberships gracefully');
    }
}
