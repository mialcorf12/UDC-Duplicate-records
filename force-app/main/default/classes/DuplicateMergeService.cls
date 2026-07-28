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
                Map<Id, Lead> leadsById = new Map<Id, Lead>();

                for (Lead l : leads) {
                    leadsById.put(l.Id, l);
                    if (l.Id == masterId) {
                        masterLead = l;
                    } else {
                        secondaryLeads.add(l);
                    }
                }

                if (masterLead == null) {
                    throw new DuplicateMergeServiceException('Master Lead not found: ' + masterId);
                }

                if (applyLeadOverrides(masterLead, leadsById, fieldOverrides)) {
                    update masterLead;
                }

                // Merge (max 2 secondaries)
                // Pass Id-only records to avoid INVALID_FIELD_FOR_INSERT_UPDATE caused by
                // read-only system fields (IsConverted) loaded on the queried SObjects.
                List<Id> secondaryLeadIds = new List<Id>();
                for (Lead l : secondaryLeads) {
                    secondaryLeadIds.add(l.Id);
                }
                Database.merge(new Lead(Id = masterLead.Id), secondaryLeadIds);

            } else {
                // ── Contact-Contact merge ──
                List<Contact> contacts = ContactSelector.getByIds(allIds);
                Contact masterContact = null;
                List<Contact> secondaryContacts = new List<Contact>();
                Map<Id, Contact> contactsById = new Map<Id, Contact>();

                for (Contact c : contacts) {
                    contactsById.put(c.Id, c);
                    if (c.Id == masterId) {
                        masterContact = c;
                    } else {
                        secondaryContacts.add(c);
                    }
                }

                if (masterContact == null) {
                    throw new DuplicateMergeServiceException('Master Contact not found: ' + masterId);
                }

                if (applyContactOverrides(masterContact, contactsById, fieldOverrides)) {
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

    /**
     * @description Applies fieldOverrides to a master Lead: generic put() for every
     *              key except the block-level Address field, which is resolved from
     *              the already-queried cluster members and delegated to
     *              mergeAddressField().
     * @param masterLead     The Lead being mutated.
     * @param leadsById      All queried cluster member Leads (allIds), keyed by Id.
     * @param fieldOverrides Map of field API name → winning value (or winning record Id for Address).
     * @return True if masterLead was mutated and needs to be updated.
     */
    private static Boolean applyLeadOverrides(Lead masterLead, Map<Id, Lead> leadsById, Map<String, String> fieldOverrides) {
        Boolean mutated = false;
        if (fieldOverrides != null && !fieldOverrides.isEmpty()) {
            for (String fieldName : fieldOverrides.keySet()) {
                if (fieldName == DuplicateComparisonFields.ADDRESS_KEY) {
                    continue;
                }
                masterLead.put(fieldName, fieldOverrides.get(fieldName));
                mutated = true;
            }
        }

        if (fieldOverrides != null && fieldOverrides.containsKey(DuplicateComparisonFields.ADDRESS_KEY)) {
            Id winningAddressId = (Id) fieldOverrides.get(DuplicateComparisonFields.ADDRESS_KEY);
            SObject winningAddressSource = leadsById.get(winningAddressId);
            if (winningAddressSource != null) {
                mergeAddressField(masterLead, winningAddressSource, 'Lead');
                mutated = true;
            }
        }

        return mutated;
    }

    /**
     * @description Applies fieldOverrides to a master Contact: sanitizeContactOverrides()
     *              already strips the block-level Address field (alongside Company/Account)
     *              from the generic put() path; the Address winner is resolved from the
     *              already-queried cluster members and delegated to mergeAddressField().
     * @param masterContact  The Contact being mutated.
     * @param contactsById   All queried cluster member Contacts (allIds), keyed by Id.
     * @param fieldOverrides Map of field API name → winning value (or winning record Id for Address).
     * @return True if masterContact was mutated and needs to be updated.
     */
    private static Boolean applyContactOverrides(Contact masterContact, Map<Id, Contact> contactsById, Map<String, String> fieldOverrides) {
        Map<String, String> safeOverrides = sanitizeContactOverrides(fieldOverrides);
        Boolean mutated = !safeOverrides.isEmpty();
        if (mutated) {
            for (String fieldName : safeOverrides.keySet()) {
                masterContact.put(fieldName, safeOverrides.get(fieldName));
            }
        }

        if (fieldOverrides != null && fieldOverrides.containsKey(DuplicateComparisonFields.ADDRESS_KEY)) {
            Id winningAddressId = (Id) fieldOverrides.get(DuplicateComparisonFields.ADDRESS_KEY);
            SObject winningAddressSource = contactsById.get(winningAddressId);
            if (winningAddressSource != null) {
                mergeAddressField(masterContact, winningAddressSource, 'Contact');
                mutated = true;
            }
        }

        return mutated;
    }

    private static Map<String, String> sanitizeContactOverrides(Map<String, String> overrides) {
        if (overrides == null || overrides.isEmpty()) return new Map<String, String>();
        final Set<String> BLOCKED = new Set<String>{ 'Company', 'Account', DuplicateComparisonFields.ADDRESS_KEY };
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
    // Block-level Address merge (object-type-aware)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Applies the winning Address block (Contact.MailingAddress or
     *              Lead.Address) from the winning source record onto the master
     *              record. Address is a compound field whose API names differ by
     *              object type (Mailing* on Contact, plain on Lead) and cannot be
     *              written via the generic fieldOverrides put() loop, so callers
     *              special-case the `Address` override key and delegate here.
     *              Reads the winning source's subfields (positionally matched to
     *              its own object type) and writes the master's target subfields
     *              (positionally matched to masterObjectType). Mutates master in
     *              place — the caller owns the single DML update.
     * @param master           The record being kept as the merge master (Contact or Lead).
     * @param winningSource    The record whose Address block was selected as the winner.
     * @param masterObjectType 'Contact' or 'Lead' — determines the target subfield API names.
     */
    public static void mergeAddressField(SObject master, SObject winningSource, String masterObjectType) {
        if (master == null || winningSource == null) {
            return;
        }

        String sourceObjectType = winningSource.getSObjectType().getDescribe().getName();
        List<String> sourceSubfields = DuplicateComparisonFields.addressSubfields(sourceObjectType);
        List<String> targetSubfields = DuplicateComparisonFields.addressSubfields(masterObjectType);

        for (Integer i = 0; i < targetSubfields.size(); i++) {
            master.put(targetSubfields[i], winningSource.get(sourceSubfields[i]));
        }
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
