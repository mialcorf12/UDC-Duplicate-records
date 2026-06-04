/**
 * @description Queueable Apex for cross-object (Lead → Contact) merge operations.
 *              Runs in a fresh governor limit envelope to avoid DML+callout conflicts.
 *
 *              Flow:
 *              1. Insert DuplicateMergeAudit__c with Status = Pending
 *              2. Convert the Lead into the existing Contact
 *              3. Fetch master and converted Contact records
 *              4. Apply fieldOverrides to the master Contact
 *              5. Merge master with converted Contact
 *              6. Update DuplicateCluster__c Status = Merged
 *              7. Update audit record Status = Success
 *              On exception: update audit Status = Failed with error message
 */
public with sharing class CrossObjectMergeQueueable implements Queueable {

    private Id leadId;
    private Id contactId;
    private Id clusterId;
    private Map<String, String> fieldOverrides;

    /**
     * @param leadId         The Lead record to be converted and merged.
     * @param contactId      The master Contact to merge into.
     * @param clusterId      The DuplicateCluster__c that initiated this merge.
     * @param fieldOverrides Map of field API name → winning value to apply to master.
     */
    public CrossObjectMergeQueueable(
        Id leadId,
        Id contactId,
        Id clusterId,
        Map<String, String> fieldOverrides
    ) {
        this.leadId         = leadId;
        this.contactId      = contactId;
        this.clusterId      = clusterId;
        this.fieldOverrides = fieldOverrides != null ? fieldOverrides : new Map<String, String>();
    }

    /**
     * @description Executes the cross-object merge within the Queueable transaction.
     */
    public void execute(QueueableContext ctx) {
        // ── Step 1: Insert audit record with Status = Pending ──
        DuplicateMergeAudit__c audit = new DuplicateMergeAudit__c(
            ClusterId__c      = clusterId,
            MasterRecordId__c = String.valueOf(contactId),
            MergedRecordIds__c = String.valueOf(leadId),
            Status__c         = 'Pending',
            MergeType__c      = 'CrossObject',
            MergedDate__c     = DateTime.now(),
            JobId__c          = ctx != null ? String.valueOf(ctx.getJobId()) : null,
            FieldOverridesJSON__c = JSON.serialize(fieldOverrides)
        );
        insert audit;

        try {
            // ── Step 2: Convert Lead into the existing Contact ──
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setContactId(contactId);
            lc.setDoNotCreateOpportunity(true);
            lc.setConvertedStatus('Closed - Converted');

            Database.LeadConvertResult lcResult = Database.convertLead(lc);

            if (!lcResult.isSuccess()) {
                List<String> errors = new List<String>();
                for (Database.Error e : lcResult.getErrors()) {
                    errors.add(e.getMessage());
                }
                throw new DuplicateMergeException('Lead conversion failed: ' + String.join(errors, '; '));
            }

            // ── Step 3: Fetch master Contact + converted Contact ──
            Id convertedContactId = lcResult.getContactId();

            List<Contact> contactsToMerge = [
                SELECT Id, Email, Phone, FirstName, LastName, AccountId
                FROM   Contact
                WHERE  Id IN :new Set<Id>{ contactId, convertedContactId }
                WITH   SECURITY_ENFORCED
            ];

            Contact masterContact    = null;
            Contact convertedContact = null;
            for (Contact c : contactsToMerge) {
                if (c.Id == contactId) {
                    masterContact = c;
                } else {
                    convertedContact = c;
                }
            }

            if (masterContact == null) {
                throw new DuplicateMergeException('Master contact not found: ' + contactId);
            }
            if (convertedContact == null) {
                throw new DuplicateMergeException('Converted contact not found: ' + convertedContactId);
            }

            // ── Step 4: Apply fieldOverrides to master Contact ──
            if (!fieldOverrides.isEmpty()) {
                for (String fieldName : fieldOverrides.keySet()) {
                    masterContact.put(fieldName, fieldOverrides.get(fieldName));
                }
                update masterContact;
            }

            // ── Step 5: Merge master with converted Contact ──
            Database.merge(masterContact, convertedContact);

            // ── Step 6: Update cluster status ──
            if (clusterId != null) {
                update new DuplicateCluster__c(Id = clusterId, Status__c = 'Merged');
            }

            // ── Step 7: Update audit record to Success ──
            audit.Status__c = 'Success';
            update audit;

        } catch (Exception ex) {
            // Update audit record to Failed
            audit.Status__c      = 'Failed';
            audit.ErrorMessage__c = ex.getMessage();
            update audit;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class DuplicateMergeException extends Exception {}
}
