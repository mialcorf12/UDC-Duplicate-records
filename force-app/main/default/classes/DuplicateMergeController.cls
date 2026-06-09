/**
 * @description AuraEnabled controller for merge and ignore actions on duplicate clusters.
 *              Delegates merge logic to DuplicateMergeService and ignore logic to
 *              DuplicateIgnoreService. Sharing enforced by "with sharing".
 */
public with sharing class DuplicateMergeController {

    /**
     * @description Merges all duplicate records in a cluster, keeping masterId as the winner.
     *              For Mixed (Lead + Contact) clusters the merge is initiated asynchronously
     *              and a jobId is returned for polling. Same-object merges are synchronous.
     *
     * @param clusterId      Id of the DuplicateCluster__c to process.
     * @param masterId       Id of the record to retain as master.
     * @param fieldOverrides Map of field API name → winning value to apply to the master.
     * @return Map with keys: success (Boolean), jobId (String, cross-object only), message (String).
     * @throws AuraHandledException on blank inputs or missing records.
     */
    @AuraEnabled
    public static Map<String, Object> mergeCluster(
        String              clusterId,
        String              masterId,
        Map<String, String> fieldOverrides
    ) {
        if (String.isBlank(clusterId) || String.isBlank(masterId)) {
            throw new AuraHandledException('clusterId and masterId are required');
        }

        try {
            DuplicateCluster__c cluster =
                DuplicateClusterSelector.getWithMembers((Id) clusterId);

            if (cluster == null) {
                throw new AuraHandledException('Cluster not found: ' + clusterId);
            }

            if (cluster.ObjectType__c == 'Mixed') {
                // ── Cross-object path: collect all Lead members ──
                List<Id> leadIds = new List<Id>();
                Id contactId     = (Id) masterId;

                for (DuplicateClusterMember__c m : cluster.ClusterMembers__r) {
                    if (m.ObjectType__c == 'Lead' &&
                        m.RecordId__c   != masterId) {
                        leadIds.add((Id) m.RecordId__c);
                    }
                }

                if (leadIds.isEmpty()) {
                    throw new AuraHandledException(
                        'No Lead member found in Mixed cluster: ' + clusterId
                    );
                }

                return DuplicateMergeService.initiateCrossObjectMerge(
                    (Id) clusterId, leadIds, contactId, fieldOverrides
                );

            } else {
                // ── Same-object path (Contact-Contact or Lead-Lead) ──
                return DuplicateMergeService.mergeSameObject(
                    (Id) clusterId, (Id) masterId, fieldOverrides
                );
            }

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Marks all pairs in the cluster as ignored and updates cluster status
     *              to 'Ignored'. Creates DuplicateIgnore__c records for every member
     *              combination so the next batch run skips these pairs.
     *
     * @param clusterId  Id of the DuplicateCluster__c to ignore.
     * @param reason     Free-text reason stored on each DuplicateIgnore__c record.
     * @throws AuraHandledException on blank clusterId or missing cluster.
     */
    @AuraEnabled
    public static void ignoreCluster(String clusterId, String reason) {
        if (String.isBlank(clusterId)) {
            throw new AuraHandledException('clusterId is required');
        }

        DuplicateCluster__c cluster =
            DuplicateClusterSelector.getWithMembers((Id) clusterId);

        if (cluster == null) {
            throw new AuraHandledException('Cluster not found: ' + clusterId);
        }

        // Collect member record IDs
        List<Id> memberIds = new List<Id>();
        for (DuplicateClusterMember__c m : cluster.ClusterMembers__r) {
            memberIds.add((Id) m.RecordId__c);
        }

        // Create ignore records for every unique pair combination
        for (Integer i = 0; i < memberIds.size(); i++) {
            for (Integer j = i + 1; j < memberIds.size(); j++) {
                DuplicateIgnoreService.ignorePair(
                    memberIds[i],
                    memberIds[j],
                    UserInfo.getUserId(),
                    reason
                );
            }
        }

        // Update cluster status to Ignored
        update new DuplicateCluster__c(Id = cluster.Id, Status__c = 'Ignored');
    }
}
