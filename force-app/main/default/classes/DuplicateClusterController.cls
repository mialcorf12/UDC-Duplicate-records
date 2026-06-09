/**
 * @description AuraEnabled controller for the duplicate cluster list and detail views.
 *              Delegates all SOQL to DuplicateClusterSelector. Sharing enforced
 *              by the "with sharing" declaration.
 */
public with sharing class DuplicateClusterController {

    /**
     * @description Returns a paginated list of clusters matching the supplied filters,
     *              plus a total count for client-side pagination controls.
     *
     * @param objectType   Picklist value ('Contact'|'Lead'|'Mixed'), or null for all.
     * @param status       Picklist value ('Open'|'Stale'|...), or null for all.
     * @param minScore     Minimum ClusterScore__c, default 0.
     * @param pageSize     Records per page, default 50.
     * @param pageNumber   1-based page number, default 1.
     * @return Map with keys: clusters (List), totalCount (Integer), pageNumber (Integer), pageSize (Integer).
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getClusterList(
        String  objectType,
        String  status,
        Decimal minScore,
        Integer pageSize,
        Integer pageNumber
    ) {
        // Apply defaults / guard clauses
        if (pageSize   == null || pageSize   <= 0) { pageSize   = 10; }
        if (pageNumber == null || pageNumber  < 1) { pageNumber = 1;  }
        if (minScore   == null)                    { minScore   = 0;  }

        Integer offset = pageSize * (pageNumber - 1);

        List<DuplicateCluster__c> clusters =
            DuplicateClusterSelector.getOpenClusters(
                objectType, status, minScore, pageSize, offset
            );

        // Separate COUNT() query — SOQL OFFSET is not valid on COUNT()
        Integer totalCount =
            DuplicateClusterSelector.countClusters(objectType, status, minScore);

        return new Map<String, Object>{
            'clusters'    => clusters,
            'totalCount'  => totalCount,
            'pageNumber'  => pageNumber,
            'pageSize'    => pageSize
        };
    }

    /**
     * @description Returns a single cluster with its member records.
     *
     * @param clusterId  Id of the DuplicateCluster__c to retrieve (String accepted from LWC).
     * @return Map with keys: cluster (DuplicateCluster__c), members (List<DuplicateClusterMember__c>).
     * @throws AuraHandledException if clusterId is blank or the cluster is not found.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getClusterDetail(String clusterId) {
        if (String.isBlank(clusterId)) {
            throw new AuraHandledException('clusterId is required');
        }

        DuplicateCluster__c cluster =
            DuplicateClusterSelector.getWithMembers((Id) clusterId);

        if (cluster == null) {
            throw new AuraHandledException('Cluster not found: ' + clusterId);
        }

        return new Map<String, Object>{
            'cluster' => cluster,
            'members' => cluster.ClusterMembers__r
        };
    }

    /**
     * @description Sets IsMaster__c = true on the chosen member and clears it on all others
     *              in the same cluster. Persists the user's master record selection.
     *
     * @param clusterId      Id of the DuplicateCluster__c.
     * @param memberRecordId RecordId__c value of the member to promote as master.
     */
    @AuraEnabled
    public static void setMasterRecord(String clusterId, String memberRecordId) {
        if (String.isBlank(clusterId) || String.isBlank(memberRecordId)) {
            throw new AuraHandledException('clusterId and memberRecordId are required');
        }
        List<DuplicateClusterMember__c> members = [
            SELECT Id, RecordId__c, IsMaster__c
            FROM DuplicateClusterMember__c
            WHERE Cluster__c = :clusterId
            WITH SECURITY_ENFORCED
        ];
        for (DuplicateClusterMember__c m : members) {
            m.IsMaster__c = (m.RecordId__c == memberRecordId);
        }
        update members;
    }
}
