/**
 * @description Batch job that merges all Open duplicate clusters matching a minimum score
 *              and optional object type filter. Scope=1 ensures each cluster is an isolated
 *              transaction — a failure on one cluster does not roll back others.
 */
public with sharing class BulkMergeBatch implements Database.Batchable<SObject> {

    private final Decimal minScore;
    private final String  objectType; // null = All

    public BulkMergeBatch(Decimal minScore, String objectType) {
        this.minScore   = minScore;
        this.objectType = objectType;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String soql =
            'SELECT Id, ObjectType__c ' +
            'FROM DuplicateCluster__c ' +
            'WHERE ClusterScore__c >= :minScore ' +
            '  AND Status__c = \'Open\' ';
        if (String.isNotBlank(objectType)) {
            soql += 'AND ObjectType__c = :objectType ';
        }
        soql += 'WITH SECURITY_ENFORCED';
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        DuplicateCluster__c cluster = (DuplicateCluster__c) scope[0];
        DuplicateCluster__c loaded  = DuplicateClusterSelector.getWithMembers(cluster.Id);
        if (loaded == null) { return; }

        List<DuplicateClusterMember__c> members =
            loaded.ClusterMembers__r != null
                ? loaded.ClusterMembers__r
                : new List<DuplicateClusterMember__c>();
        if (members.isEmpty()) { return; }

        // Resolve master: IsMaster__c flag, fallback to first member
        String masterId = null;
        for (DuplicateClusterMember__c m : members) {
            if (m.IsMaster__c) { masterId = m.RecordId__c; break; }
        }
        if (masterId == null) { masterId = members[0].RecordId__c; }

        if (cluster.ObjectType__c == 'Mixed') {
            List<Id> leadIds = new List<Id>();
            Id contactId     = null;
            for (DuplicateClusterMember__c m : members) {
                if (m.ObjectType__c == 'Lead') {
                    leadIds.add((Id) m.RecordId__c);
                } else if (contactId == null) {
                    contactId = (Id) m.RecordId__c;
                }
            }
            if (!leadIds.isEmpty() && contactId != null) {
                DuplicateMergeService.initiateCrossObjectMerge(
                    cluster.Id, leadIds, contactId, new Map<String, String>()
                );
            }
        } else {
            DuplicateMergeService.mergeSameObject(
                cluster.Id, (Id) masterId, new Map<String, String>()
            );
        }
    }

    public void finish(Database.BatchableContext bc) {}
}
