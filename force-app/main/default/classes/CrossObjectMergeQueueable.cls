/**
 * @description Queueable Apex for cross-object (Lead → Contact) merge operations.
 *              Supports N leads by self-chaining: each execution converts one lead,
 *              then enqueues the next job for the remaining leads.
 *              A single DuplicateMergeAudit__c record is shared across the chain
 *              (auditId passed through the constructor on continuation calls).
 *
 *              Flow (per iteration):
 *              1. First call: insert DuplicateMergeAudit__c with Status = Pending
 *                 Subsequent calls: load existing audit by auditId
 *              2. Convert the current Lead into the existing Contact
 *              3. Fetch master and converted Contact records
 *              4. Apply fieldOverrides to the master Contact
 *              5. Merge master with converted Contact
 *              6. Accumulate lead ID into audit.MergedRecordIds__c
 *              7a. If more leads remain: update audit (Pending), enqueue next job
 *              7b. If last lead: update cluster Status = Merged, audit Status = Success
 *              On exception: update audit Status = Failed — chain stops
 */
public with sharing class CrossObjectMergeQueueable implements Queueable {

    @TestVisible
    private static Id testConvertedContactIdOverride;

    private List<Id> leadIds;
    private Id contactId;
    private Id clusterId;
    private Map<String, String> fieldOverrides;
    private Id auditId;

    /**
     * @param leadIds        Ordered list of Lead IDs to convert and merge. Each execution
     *                       processes leadIds[0] and chains with the remainder.
     * @param contactId      The master Contact to merge into.
     * @param clusterId      The DuplicateCluster__c that initiated this merge.
     * @param fieldOverrides Map of field API name → winning value to apply to master.
     * @param auditId        Id of the shared DuplicateMergeAudit__c record.
     *                       Pass null on the first call — the audit is created automatically.
     *                       Subsequent (chained) calls receive the Id from the previous job.
     */
    public CrossObjectMergeQueueable(
        List<Id>            leadIds,
        Id                  contactId,
        Id                  clusterId,
        Map<String, String> fieldOverrides,
        Id                  auditId
    ) {
        this.leadIds        = leadIds        != null ? new List<Id>(leadIds) : new List<Id>();
        this.contactId      = contactId;
        this.clusterId      = clusterId;
        this.fieldOverrides = fieldOverrides != null ? fieldOverrides : new Map<String, String>();
        this.auditId        = auditId;
    }

    /**
     * @description Processes all leads in a single execution (loop, no chaining).
     *              A per-lead savepoint rolls back only that lead's partial DML on failure.
     *              The audit record is inserted before any savepoint so catch-block updates
     *              always have a clean DML context.
     */
    public void execute(QueueableContext ctx) {
        if (leadIds.isEmpty()) return;

        // ── Step 1: Insert audit once — before any savepoint ──
        DuplicateMergeAudit__c audit = new DuplicateMergeAudit__c(
            ClusterId__c          = clusterId,
            MasterRecordId__c     = String.valueOf(contactId),
            MergedRecordIds__c    = '',
            Status__c             = 'Pending',
            MergeType__c          = 'CrossObject',
            MergedDate__c         = DateTime.now(),
            JobId__c              = ctx != null ? String.valueOf(ctx.getJobId()) : null,
            FieldOverridesJSON__c = JSON.serialize(fieldOverrides)
        );
        insert audit;
        Id capturedAuditId = audit.Id;

        // ── Steps 2–6: Process each lead; stop chain on first failure ──
        String accumulated = '';
        for (Id leadId : new List<Id>(leadIds)) {
            Savepoint sp = Database.setSavepoint();
            try {
                convertAndMergeLead(leadId);
                accumulated = String.isBlank(accumulated)
                    ? String.valueOf(leadId)
                    : accumulated + ',' + String.valueOf(leadId);
            } catch (Exception ex) {
                Database.rollback(sp);
                update new DuplicateMergeAudit__c(
                    Id              = capturedAuditId,
                    Status__c       = 'Failed',
                    ErrorMessage__c = ex.getMessage()?.abbreviate(255)
                );
                return;
            }
        }

        // ── Step 7: All leads succeeded — finalize ──
        audit.MergedRecordIds__c = accumulated;
        if (clusterId != null) {
            update new DuplicateCluster__c(Id = clusterId, Status__c = 'Merged');
        }
        audit.Status__c = 'Success';
        update audit;
    }

    private void convertAndMergeLead(Id leadId) {
        // ── Step 2: Convert Lead into the existing Contact ──
        Contact masterForConvert = [SELECT AccountId FROM Contact WHERE Id = :contactId LIMIT 1];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadId);
        lc.setContactId(contactId);
        if (masterForConvert.AccountId != null) {
            lc.setAccountId(masterForConvert.AccountId);
        }
        lc.setDoNotCreateOpportunity(true);
        LeadStatus convertedLeadStatus = [
            SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1
        ];
        lc.setConvertedStatus(convertedLeadStatus.MasterLabel);

        Database.LeadConvertResult lcResult = Database.convertLead(lc);

        if (!lcResult.isSuccess()) {
            List<String> errors = new List<String>();
            for (Database.Error e : lcResult.getErrors()) {
                errors.add(e.getMessage());
            }
            throw new DuplicateMergeException('Lead conversion failed: ' + String.join(errors, '; '));
        }

        // ── Step 3: Fetch master Contact + converted Contact ──
        Id convertedContactId = testConvertedContactIdOverride != null
            ? testConvertedContactIdOverride
            : lcResult.getContactId();

        if (convertedContactId != null && convertedContactId != contactId) {
            List<Contact> contactsToMerge = [
                SELECT Id, Email, Phone, FirstName, LastName, AccountId
                FROM   Contact
                WHERE  Id IN :new Set<Id>{ contactId, convertedContactId }
                WITH   SECURITY_ENFORCED
            ];

            Contact masterContact    = null;
            Contact convertedContact = null;
            for (Contact c : contactsToMerge) {
                if (c.Id == contactId) { masterContact    = c; }
                else                   { convertedContact = c; }
            }

            if (masterContact    == null) throw new DuplicateMergeException('Master contact not found: '    + contactId);
            if (convertedContact == null) throw new DuplicateMergeException('Converted contact not found: ' + convertedContactId);

            // ── Step 4: Apply fieldOverrides ──
            Map<String, String> safeOverrides = sanitizeContactOverrides(fieldOverrides);
            if (!safeOverrides.isEmpty()) {
                for (String fieldName : safeOverrides.keySet()) {
                    masterContact.put(fieldName, safeOverrides.get(fieldName));
                }
                update masterContact;
            }

            // ── Step 5: Merge master with converted Contact ──
            Database.merge(masterContact, convertedContact);

        } else {
            Map<String, String> safeOverrides = sanitizeContactOverrides(fieldOverrides);
            if (!safeOverrides.isEmpty()) {
                Contact masterContact = new Contact(Id = contactId);
                for (String fieldName : safeOverrides.keySet()) {
                    masterContact.put(fieldName, safeOverrides.get(fieldName));
                }
                update masterContact;
            }
        }
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
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class DuplicateMergeException extends Exception {}
}
