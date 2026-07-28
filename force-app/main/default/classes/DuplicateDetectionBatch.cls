/**
 * @description Stateful Batch Apex job that detects duplicate Contact/Lead pairs
 *              using pre-computed blocking keys (Email_Block__c) and weighted scoring.
 *
 *              Governor limit strategy:
 *              - Max 6 SOQL per execute (1 LeadSelector + 1 IgnoreSelector + existing cluster query)
 *              - Max 2 DML per execute (upsert clusters + insert members)
 *              - Blocking key grouping is done in-memory within each chunk
 *
 *              Scoring weights: Email(40) + Phone(30) + Name(20) + Company(10) = 100 max
 *              Threshold: ≥ 70 to qualify as a duplicate pair
 */
public without sharing class DuplicateDetectionBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Stateful counters — survive across execute() invocations
    private Integer clustersCreated = 0;
    private Integer clustersUpdated = 0;

    private static final Decimal SCORE_THRESHOLD = 70;

    // ─────────────────────────────────────────────────────────────────────────
    // Batchable interface
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Defines the scope of records to process.
     *              Returns all non-deleted Contacts that have an email block.
     * @param bc Batch context.
     * @return QueryLocator for non-deleted Contacts with a populated email block.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        List<String> fields = new List<String>(DuplicateComparisonFields.CONTACT_SNAPSHOT_FIELDS);
        fields.addAll(DuplicateComparisonFields.addressSubfields('Contact'));
        String query = 'SELECT ' + String.join(fields, ', ') +
            ' FROM Contact WHERE IsDeleted = false AND Email_Block__c != null';
        return Database.getQueryLocator(query);
    }

    /**
     * @description Processes one chunk of Contact records.
     *              Groups by Email_Block__c, queries matching Leads, scores all pairs,
     *              and upserts duplicate cluster records for qualifying pairs.
     *
     * @param bc    Batch context.
     * @param scope Chunk of Contact records (up to 200).
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Contact> contacts = (List<Contact>) scope;

        // ── Step 1: Group received contacts by Email_Block__c in memory ──
        Map<String, List<Contact>> contactsByBlock = new Map<String, List<Contact>>();
        for (Contact c : contacts) {
            if (String.isBlank(c.Email_Block__c)) { continue; }
            if (!contactsByBlock.containsKey(c.Email_Block__c)) {
                contactsByBlock.put(c.Email_Block__c, new List<Contact>());
            }
            contactsByBlock.get(c.Email_Block__c).add(c);
        }

        if (contactsByBlock.isEmpty()) { return; }

        Set<String> blockKeys = contactsByBlock.keySet();

        // ── Step 2: Query matching Leads via selector (SOQL #1) ──
        List<Lead> matchingLeads = LeadSelector.getByEmailBlock(blockKeys);

        // Group leads by their email block key
        Map<String, List<Lead>> leadsByBlock = new Map<String, List<Lead>>();
        for (Lead l : matchingLeads) {
            if (String.isBlank(l.Email_Block__c)) { continue; }
            if (!leadsByBlock.containsKey(l.Email_Block__c)) {
                leadsByBlock.put(l.Email_Block__c, new List<Lead>());
            }
            leadsByBlock.get(l.Email_Block__c).add(l);
        }

        // ── Step 3: Score all pairs and collect qualifying pairs ──
        // Structure: blockKey → Map<pairKey, PairData>
        Map<String, PairData> qualifiedPairs = new Map<String, PairData>();

        for (String blockKey : contactsByBlock.keySet()) {
            List<Contact> blockContacts = contactsByBlock.get(blockKey);

            // Contact-Contact pairs
            for (Integer i = 0; i < blockContacts.size(); i++) {
                for (Integer j = i + 1; j < blockContacts.size(); j++) {
                    Contact c1 = blockContacts[i];
                    Contact c2 = blockContacts[j];
                    Decimal score = DuplicateScoringUtil.scoreRecords(c1, c2);
                    if (score >= SCORE_THRESHOLD) {
                        String pairKey = buildPairKey(c1.Id, c2.Id);
                        qualifiedPairs.put(pairKey, new PairData(
                            pairKey, blockKey, score,
                            c1.Id, 'Contact',
                            c2.Id, 'Contact',
                            DuplicateScoringUtil.buildSnapshotJSON(c1, 'Contact'),
                            DuplicateScoringUtil.buildSnapshotJSON(c2, 'Contact')
                        ));
                    }
                }
            }

            // Contact-Lead pairs
            List<Lead> blockLeads = leadsByBlock.containsKey(blockKey)
                ? leadsByBlock.get(blockKey)
                : new List<Lead>();

            for (Contact c : blockContacts) {
                for (Lead l : blockLeads) {
                    Decimal score = DuplicateScoringUtil.scoreRecords(c, l);
                    if (score >= SCORE_THRESHOLD) {
                        String pairKey = buildPairKey(c.Id, l.Id);
                        qualifiedPairs.put(pairKey, new PairData(
                            pairKey, blockKey, score,
                            c.Id, 'Contact',
                            l.Id, 'Lead',
                            DuplicateScoringUtil.buildSnapshotJSON(c, 'Contact'),
                            DuplicateScoringUtil.buildSnapshotJSON(l, 'Lead')
                        ));
                    }
                }
            }
        }

        if (qualifiedPairs.isEmpty()) { return; }

        // ── Step 4: Filter out ignored pairs (SOQL #2) ──
        Map<String, DuplicateIgnore__c> ignoredPairs =
            DuplicateIgnoreSelector.getByPairKeys(qualifiedPairs.keySet());

        List<PairData> pairsToProcess = new List<PairData>();
        for (String pairKey : qualifiedPairs.keySet()) {
            if (!ignoredPairs.containsKey(pairKey)) {
                pairsToProcess.add(qualifiedPairs.get(pairKey));
            }
        }

        if (pairsToProcess.isEmpty()) { return; }

        // ── Step 5: Build cluster and member records (DML #1 + DML #2) ──
        // Group pairs by blockKey to cluster related duplicates together
        Map<String, List<PairData>> pairsByBlock = new Map<String, List<PairData>>();
        for (PairData pd : pairsToProcess) {
            if (!pairsByBlock.containsKey(pd.blockKey)) {
                pairsByBlock.put(pd.blockKey, new List<PairData>());
            }
            pairsByBlock.get(pd.blockKey).add(pd);
        }

        // Determine ObjectType for each cluster
        List<DuplicateCluster__c> clustersToUpsert = new List<DuplicateCluster__c>();
        Map<String, DuplicateCluster__c> clusterByBlockKey = new Map<String, DuplicateCluster__c>();

        for (String blockKey : pairsByBlock.keySet()) {
            List<PairData> pairs = pairsByBlock.get(blockKey);
            String objectType = determineObjectType(pairs);
            Decimal totalScore = 0;
            for (PairData pd : pairs) {
                totalScore += pd.score;
            }
            Decimal avgScore = (totalScore / pairs.size()).setScale(2);

            DuplicateCluster__c cluster = new DuplicateCluster__c(
                ObjectType__c   = objectType,
                Status__c       = 'Open',
                ClusterScore__c = avgScore,
                BlockingKey__c  = blockKey,
                DetectedDate__c = DateTime.now(),
                BatchJobId__c   = bc.getJobId() != null ? String.valueOf(bc.getJobId()).left(18) : null
            );
            clustersToUpsert.add(cluster);
            clusterByBlockKey.put(blockKey, cluster);
        }

        // DML #1: upsert clusters
        // Using upsert by Name (no external ID on cluster) — insert only for simplicity
        // A production hardening approach would use BlockingKey__c as ExternalId if indexed
        insert clustersToUpsert;
        clustersCreated += clustersToUpsert.size();

        // DML #2: insert members
        List<DuplicateClusterMember__c> membersToInsert = new List<DuplicateClusterMember__c>();
        for (String blockKey : pairsByBlock.keySet()) {
            DuplicateCluster__c cluster = clusterByBlockKey.get(blockKey);
            List<PairData> pairs = pairsByBlock.get(blockKey);

            // Collect distinct record IDs in this cluster (first pair member = master)
            Map<String, String[]> distinctMembers = new Map<String, String[]>();
            for (PairData pd : pairs) {
                if (!distinctMembers.containsKey(pd.record1Id)) {
                    distinctMembers.put(pd.record1Id, new String[]{ pd.type1, pd.snapshot1 });
                }
                if (!distinctMembers.containsKey(pd.record2Id)) {
                    distinctMembers.put(pd.record2Id, new String[]{ pd.type2, pd.snapshot2 });
                }
            }

            Boolean firstMember = true;
            for (String recordIdStr : distinctMembers.keySet()) {
                String[] meta = distinctMembers.get(recordIdStr);
                membersToInsert.add(new DuplicateClusterMember__c(
                    Cluster__c           = cluster.Id,
                    RecordId__c          = recordIdStr,
                    ObjectType__c        = meta[0],
                    IsMaster__c          = firstMember,
                    FieldSnapshotJSON__c = meta[1]
                ));
                firstMember = false;
            }
        }

        insert membersToInsert;
    }

    /**
     * @description Logs a summary of cluster statistics after all chunks complete.
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(
            'DuplicateDetectionBatch complete. ' +
            'Clusters created: ' + clustersCreated + ' | ' +
            'Clusters updated: ' + clustersUpdated
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner class — pair metadata container
    // ─────────────────────────────────────────────────────────────────────────

    private class PairData {
        String  pairKey;
        String  blockKey;
        Decimal score;
        String  record1Id;
        String  type1;
        String  record2Id;
        String  type2;
        String  snapshot1;
        String  snapshot2;

        PairData(
            String pairKey, String blockKey, Decimal score,
            Id r1Id, String type1,
            Id r2Id, String type2,
            String snapshot1, String snapshot2
        ) {
            this.pairKey   = pairKey;
            this.blockKey  = blockKey;
            this.score     = score;
            this.record1Id = String.valueOf(r1Id);
            this.type1     = type1;
            this.record2Id = String.valueOf(r2Id);
            this.type2     = type2;
            this.snapshot1 = snapshot1;
            this.snapshot2 = snapshot2;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Builds a canonical pair key that is order-independent.
     *              PairKey = min(id1, id2) + '_' + max(id1, id2)
     */
    private static String buildPairKey(Id id1, Id id2) {
        String s1 = String.valueOf(id1);
        String s2 = String.valueOf(id2);
        return (s1 < s2) ? s1 + '_' + s2 : s2 + '_' + s1;
    }

    /**
     * @description Determines the cluster ObjectType based on member types.
     */
    private static String determineObjectType(List<PairData> pairs) {
        Boolean hasContact = false;
        Boolean hasLead    = false;
        for (PairData pd : pairs) {
            if (pd.type1 == 'Contact' || pd.type2 == 'Contact') { hasContact = true; }
            if (pd.type1 == 'Lead'    || pd.type2 == 'Lead')    { hasLead    = true; }
        }
        if (hasContact && hasLead) { return 'Mixed'; }
        if (hasContact)            { return 'Contact'; }
        return 'Lead';
    }
}
