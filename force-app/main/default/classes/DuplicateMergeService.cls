/**
 * @description Stateless service layer for duplicate record merge operations.
 *              Handles both same-object (Contact-Contact, Lead-Lead) and
 *              cross-object (Lead → Contact) merges.
 *
 *              Does NOT contain SOQL — delegates all queries to selectors.
 *              Does NOT instantiate stateful objects — all methods are static.
 */
public with sharing class DuplicateMergeService {

    // ─────────────────────────────────────────────────────────────────────────
    // Same-object merge: Contact-Contact or Lead-Lead
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Merges duplicate records of the same object type.
     *              Applies fieldOverrides to the master record before merging.
     *              Inserts a DuplicateMergeAudit__c record and updates cluster status.
     *
     * @param clusterId      The Id of the DuplicateCluster__c to process.
     * @param masterId       The Id of the record to keep as master.
     * @param fieldOverrides Map of field API name → winning value.
     * @return Map<String, Object>: { success: Boolean, message: String }
     */
    public static Map<String, Object> mergeSameObject(
        Id clusterId,
        Id masterId,
        Map<String, String> fieldOverrides
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'message' => ''
        };

        DuplicateMergeAudit__c audit = new DuplicateMergeAudit__c(
            ClusterId__c      = clusterId,
            MasterRecordId__c = String.valueOf(masterId),
            Status__c         = 'Pending',
            MergeType__c      = 'SameObject',
            MergedDate__c     = DateTime.now(),
            FieldOverridesJSON__c = JSON.serialize(fieldOverrides)
        );
        insert audit;

        try {
            // ── Step 1: Query cluster + members ──
            DuplicateCluster__c cluster = DuplicateClusterSelector.getWithMembers(clusterId);
            if (cluster == null) {
                throw new DuplicateMergeServiceException('Cluster not found: ' + clusterId);
            }

            // ── Step 2: Identify secondary IDs ──
            List<String> secondaryIds = new List<String>();
            String objectType = cluster.ObjectType__c;

            for (DuplicateClusterMember__c member : cluster.ClusterMembers__r) {
                if (member.RecordId__c != String.valueOf(masterId)) {
                    secondaryIds.add(member.RecordId__c);
                }
            }

            if (secondaryIds.isEmpty()) {
                throw new DuplicateMergeServiceException('No secondary records found in cluster: ' + clusterId);
            }

            // Apex merge supports max 2 secondary records
            if (secondaryIds.size() > 2) {
                secondaryIds = new List<String>{ secondaryIds[0], secondaryIds[1] };
            }

            Set<Id> secondaryIdSet = new Set<Id>();
            for (String s : secondaryIds) {
                secondaryIdSet.add((Id) s);
            }
            Set<Id> allIds = new Set<Id>{ masterId };
            allIds.addAll(secondaryIdSet);

            if (objectType == 'Lead') {
                // ── Lead-Lead merge ──
                List<Lead> leads = LeadSelector.getByIds(allIds);
                Lead masterLead = null;
                List<Lead> secondaryLeads = new List<Lead>();

                for (Lead l : leads) {
                    if (l.Id == masterId) {
                        masterLead = l;
                    } else {
                        secondaryLeads.add(l);
                    }
                }

                if (masterLead == null) {
                    throw new DuplicateMergeServiceException('Master Lead not found: ' + masterId);
                }

                // Apply field overrides
                if (fieldOverrides != null && !fieldOverrides.isEmpty()) {
                    for (String fieldName : fieldOverrides.keySet()) {
                        masterLead.put(fieldName, fieldOverrides.get(fieldName));
                    }
                    update masterLead;
                }

                // Merge (max 2 secondaries)
                Database.merge(masterLead, secondaryLeads);

            } else {
                // ── Contact-Contact merge ──
                List<Contact> contacts = ContactSelector.getByIds(allIds);
                Contact masterContact = null;
                List<Contact> secondaryContacts = new List<Contact>();

                for (Contact c : contacts) {
                    if (c.Id == masterId) {
                        masterContact = c;
                    } else {
                        secondaryContacts.add(c);
                    }
                }

                if (masterContact == null) {
                    throw new DuplicateMergeServiceException('Master Contact not found: ' + masterId);
                }

                // Apply field overrides
                Map<String, String> safeOverrides = sanitizeContactOverrides(fieldOverrides);
                if (!safeOverrides.isEmpty()) {
                    for (String fieldName : safeOverrides.keySet()) {
                        masterContact.put(fieldName, safeOverrides.get(fieldName));
                    }
                    update masterContact;
                }

                // Merge (max 2 secondaries)
                // Pass Id-only records to avoid INVALID_FIELD_FOR_INSERT_UPDATE caused by
                // relationship fields (Account.Name) loaded on the queried SObjects.
                List<Id> secondaryContactIds = new List<Id>();
                for (Contact c : secondaryContacts) {
                    secondaryContactIds.add(c.Id);
                }
                Database.merge(new Contact(Id = masterContact.Id), secondaryContactIds);
            }

            // ── Update cluster status ──
            update new DuplicateCluster__c(Id = clusterId, Status__c = 'Merged');

            // ── Update audit to Success ──
            audit.Status__c        = 'Success';
            audit.MergedRecordIds__c = String.join(secondaryIds, ',');
            update audit;

            result.put('success', true);
            result.put('message', 'Merge completed successfully');

        } catch (Exception ex) {
            audit.Status__c       = 'Failed';
            audit.ErrorMessage__c = ex.getMessage();
            update audit;

            result.put('success', false);
            result.put('message', ex.getMessage());
        }

        return result;
    }

    private static Map<String, String> sanitizeContactOverrides(Map<String, String> overrides) {
        if (overrides == null || overrides.isEmpty()) return new Map<String, String>();
        final Set<String> BLOCKED = new Set<String>{ 'Company', 'Account' };
        Map<String, String> clean = new Map<String, String>();
        for (String key : overrides.keySet()) {
            if (BLOCKED.contains(key)) continue;
            clean.put(key, overrides.get(key));
        }
        if (overrides.containsKey('Account') && !overrides.containsKey('AccountId')) {
            clean.put('AccountId', overrides.get('Account'));
        }
        return clean;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cross-object merge: Lead → Contact (async via Queueable)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Initiates a cross-object (Lead → Contact) merge by enqueueing
     *              a CrossObjectMergeQueueable job. Supports N leads via self-chaining.
     *              Returns the async job ID of the first job for polling.
     *
     * @param clusterId      The DuplicateCluster__c that owns this merge.
     * @param leadIds        All Lead IDs to convert and merge into the master Contact.
     * @param contactId      The master Contact to merge into.
     * @param fieldOverrides Map of field API name → winning value.
     * @return Map<String, Object>: { success: Boolean, jobId: String }
     */
    public static Map<String, Object> initiateCrossObjectMerge(
        Id                  clusterId,
        List<Id>            leadIds,
        Id                  contactId,
        Map<String, String> fieldOverrides
    ) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'jobId'   => null
        };

        Id jobId = System.enqueueJob(
            new CrossObjectMergeQueueable(leadIds, contactId, clusterId, fieldOverrides, null)
        );

        result.put('success', true);
        result.put('jobId', String.valueOf(jobId));

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class DuplicateMergeServiceException extends Exception {}
}
