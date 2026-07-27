/**
 * @description Selector for DuplicateCluster__c and DuplicateClusterMember__c.
 *              All SOQL is centralized here. No SOQL outside this class.
 */
public with sharing class DuplicateClusterSelector {

    /**
     * @description Returns a single cluster with all its members.
     * @param clusterId The Id of the DuplicateCluster__c record.
     * @return The cluster record with a populated Members__r subquery, or null if not found.
     */
    public static DuplicateCluster__c getWithMembers(Id clusterId) {
        List<DuplicateCluster__c> results = [
            SELECT Id,
                   Name,
                   ObjectType__c,
                   Status__c,
                   ClusterScore__c,
                   BlockingKey__c,
                   DetectedDate__c,
                   BatchJobId__c,
                   RecordCount__c,
                   (SELECT Id,
                           RecordId__c,
                           ObjectType__c,
                           IsMaster__c,
                           FieldSnapshotJSON__c
                     FROM   ClusterMembers__r)
            FROM   DuplicateCluster__c
            WHERE  Id = :clusterId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        return results.isEmpty() ? null : results[0];
    }

    /**
     * @description Returns clusters that contain at least one member whose RecordId__c
     *              matches any of the supplied record IDs.
     * @param recordIds Set of Salesforce record Ids to search for.
     * @return List of matching DuplicateCluster__c records.
     */
    public static List<DuplicateCluster__c> getByMemberRecordIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<DuplicateCluster__c>();
        }

        // Convert Id set to String set for Text(18) field comparison
        Set<String> recordIdStrings = new Set<String>();
        for (Id rid : recordIds) {
            recordIdStrings.add(String.valueOf(rid));
        }

        List<DuplicateClusterMember__c> members = [
            SELECT Cluster__c
            FROM   DuplicateClusterMember__c
            WHERE  RecordId__c IN :recordIdStrings
            WITH   SECURITY_ENFORCED
        ];

        Set<Id> clusterIds = new Set<Id>();
        for (DuplicateClusterMember__c m : members) {
            clusterIds.add(m.Cluster__c);
        }

        if (clusterIds.isEmpty()) {
            return new List<DuplicateCluster__c>();
        }

        return [
            SELECT Id,
                   Name,
                   ObjectType__c,
                   Status__c,
                   ClusterScore__c,
                   BlockingKey__c,
                   DetectedDate__c,
                   BatchJobId__c,
                   RecordCount__c
            FROM   DuplicateCluster__c
            WHERE  Id IN :clusterIds
            WITH   SECURITY_ENFORCED
        ];
    }

    /**
     * @description Returns a paginated list of clusters for the LWC console.
     *              Null values for objectType and status mean "no filter on that field".
     * @param objectType  Picklist value to filter on ObjectType__c, or null for all.
     * @param status      Picklist value to filter on Status__c, or null for all.
     * @param minScore    Minimum ClusterScore__c (inclusive). Use 0 to skip score filter.
     * @param pageSize    Number of records per page.
     * @param offset      Zero-based record offset (pageSize * (pageNumber - 1)).
     * @return List of DuplicateCluster__c records for the requested page.
     */
    public static List<DuplicateCluster__c> getOpenClusters(
        String  objectType,
        String  status,
        Decimal minScore,
        Integer pageSize,
        Integer offset
    ) {
        // Build dynamic SOQL to handle nullable filters
        String baseQuery =
            'SELECT Id, Name, ObjectType__c, Status__c, ClusterScore__c, ' +
            'BlockingKey__c, DetectedDate__c, BatchJobId__c, RecordCount__c ' +
            'FROM DuplicateCluster__c ' +
            'WHERE ClusterScore__c >= :minScore ';

        if (String.isNotBlank(objectType)) {
            baseQuery += 'AND ObjectType__c = :objectType ';
        }
        if (String.isNotBlank(status)) {
            baseQuery += 'AND Status__c = :status ';
        }

        baseQuery += 'ORDER BY ClusterScore__c DESC NULLS LAST, DetectedDate__c DESC ';
        baseQuery += 'LIMIT :pageSize OFFSET :offset';

        // Dynamic SOQL does not support WITH SECURITY_ENFORCED in all API versions;
        // sharing is enforced by the "with sharing" class declaration.
        return Database.query(baseQuery); //NOSONAR
    }

    /**
     * @description Returns the total count of clusters matching the given filters.
     *              Used by the LWC controller to support pagination (totalCount).
     *              Mirrors the filter logic of getOpenClusters without pagination params.
     *
     * @param objectType  Picklist value to filter on ObjectType__c, or null for all.
     * @param status      Picklist value to filter on Status__c, or null for all.
     * @param minScore    Minimum ClusterScore__c (inclusive). Use 0 or null to skip.
     * @return Total integer count matching the filters.
     */
    public static Integer countClusters(
        String  objectType,
        String  status,
        Decimal minScore
    ) {
        if (minScore == null) {
            minScore = 0;
        }

        String countQuery =
            'SELECT COUNT() FROM DuplicateCluster__c ' +
            'WHERE ClusterScore__c >= :minScore ';

        if (String.isNotBlank(objectType)) {
            countQuery += 'AND ObjectType__c = :objectType ';
        }
        if (String.isNotBlank(status)) {
            countQuery += 'AND Status__c = :status ';
        }

        // Sharing enforced by "with sharing" class declaration
        return Database.countQuery(countQuery); //NOSONAR
    }

    /**
     * @description Returns distinct DetectedDate__c dates (day only) for clusters
     *              that are not Open. Used to populate the Archive date combobox.
     * @return List of AggregateResult with key 'detectedDate' (Date).
     */
    public static List<AggregateResult> getDistinctNonOpenDates() {
        return [
            SELECT DAY_ONLY(DetectedDate__c) detectedDate
            FROM DuplicateCluster__c
            WHERE Status__c NOT IN ('Open', 'Archived')
            WITH SECURITY_ENFORCED
            GROUP BY DAY_ONLY(DetectedDate__c)
            ORDER BY DAY_ONLY(DetectedDate__c) DESC
        ];
    }

    /**
     * @description Returns clusters eligible to be archived: not Open, not already
     *              Archived, and detected on the given date.
     * @param detectedDate The date to filter on (DAY_ONLY of DetectedDate__c).
     * @return List of DuplicateCluster__c with Id only.
     */
    public static List<DuplicateCluster__c> getArchivableClusters(Date detectedDate) {
        return [
            SELECT Id
            FROM DuplicateCluster__c
            WHERE Status__c != 'Open'
              AND Status__c != 'Archived'
              AND DAY_ONLY(DetectedDate__c) = :detectedDate
            WITH SECURITY_ENFORCED
        ];
    }
}
