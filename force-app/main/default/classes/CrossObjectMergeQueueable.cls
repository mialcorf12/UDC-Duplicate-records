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

    /**
     * @description Test-only seam that simulates an org where the converted
     *              Lead is deleted immediately after conversion (a real,
     *              empirically-verified possibility — Salesforce allows
     *              deleting a converted Lead even though it blocks further
     *              field updates on it). Used exclusively to prove the
     *              winning Address is captured into a local variable BEFORE
     *              Database.convertLead() runs rather than re-read after it.
     *              Has no effect outside test context.
     */
    @TestVisible
    private static Boolean testSimulateLeadDeletedAfterConvert = false;

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
                try { Database.rollback(sp); } catch (Exception rbEx) { /* rollback best-effort */ }
                audit.Status__c       = 'Failed';
                audit.ErrorMessage__c = ex.getMessage()?.abbreviate(255);
                update audit;
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
        // ── Step 1b: Capture the winning Address BEFORE conversion ──
        // Database.convertLead() consumes the Lead: Salesforce blocks any further
        // field UPDATE on a converted Lead (CANNOT_UPDATE_CONVERTED_LEAD), and a
        // converted Lead can still be deleted outright by downstream cleanup
        // automation running in the same or a later transaction. If this Lead is
        // the selected Address winner, its compound subfields MUST be snapshotted
        // into a local variable now — re-reading them after conversion is not safe.
        Boolean isAddressWinner = isWinningAddressSource(leadId);
        Lead capturedLeadAddress = isAddressWinner ? captureWinningLeadAddress(leadId) : null;

        // ── Step 2: Convert Lead into the existing Contact ──
        Database.LeadConvertResult lcResult = performLeadConversion(leadId);

        if (Test.isRunningTest() && testSimulateLeadDeletedAfterConvert) {
            delete new Lead(Id = leadId);
        }

        // ── Step 3-5: Fetch master + converted Contact, apply overrides, merge ──
        Id convertedContactId = testConvertedContactIdOverride != null
            ? testConvertedContactIdOverride
            : lcResult.getContactId();

        if (convertedContactId != null && convertedContactId != contactId) {
            mergeIntoConvertedContact(convertedContactId, capturedLeadAddress, isAddressWinner);
        } else {
            Contact masterContact = new Contact(Id = contactId);
            if (applyOverridesAndAddress(masterContact, capturedLeadAddress, isAddressWinner)) {
                update masterContact;
            }
        }
    }

    /**
     * @description Builds and executes the Database.convertLead() call for the
     *              given Lead into the master Contact (this.contactId).
     * @param leadId The Lead to convert.
     * @return The successful LeadConvertResult.
     * @throws DuplicateMergeException if the conversion fails.
     */
    private Database.LeadConvertResult performLeadConversion(Id leadId) {
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

        Database.LeadConvertResult lcResult = Database.convertLead(
            new List<Database.LeadConvert>{ lc }, false
        )[0];

        if (!lcResult.isSuccess()) {
            List<String> errors = new List<String>();
            for (Database.Error e : lcResult.getErrors()) {
                errors.add(e.getMessage());
            }
            throw new DuplicateMergeException('Lead conversion failed: ' + String.join(errors, '; '));
        }

        return lcResult;
    }

    /**
     * @description Fetches the master and newly-converted Contact, applies
     *              fieldOverrides (incl. the object-type-aware Address merge),
     *              and merges the converted Contact into the master.
     * @param convertedContactId  The Contact created/matched by lead conversion.
     * @param capturedLeadAddress The winning Lead's pre-convert Address snapshot, or null.
     * @param isAddressWinner     Whether this lead was the selected Address winner.
     */
    private void mergeIntoConvertedContact(Id convertedContactId, Lead capturedLeadAddress, Boolean isAddressWinner) {
        List<Contact> contactsToMerge = (List<Contact>) Security.stripInaccessible(
            AccessType.READABLE,
            [SELECT Id, Email, Phone, FirstName, LastName, AccountId,
                    MailingStreet, MailingCity, MailingState, MailingPostalCode,
                    MailingCountry, MailingLatitude, MailingLongitude, MailingGeocodeAccuracy
             FROM   Contact
             WHERE  Id IN :new Set<Id>{ contactId, convertedContactId }]
        ).getRecords();

        Contact masterContact    = null;
        Contact convertedContact = null;
        for (Contact c : contactsToMerge) {
            if (c.Id == contactId) { masterContact    = c; }
            else                   { convertedContact = c; }
        }

        if (masterContact    == null) throw new DuplicateMergeException('Master contact not found: '    + contactId);
        if (convertedContact == null) throw new DuplicateMergeException('Converted contact not found: ' + convertedContactId);

        if (applyOverridesAndAddress(masterContact, capturedLeadAddress, isAddressWinner)) {
            update masterContact;
        }

        Database.merge(masterContact, convertedContact);
    }

    /**
     * @description Determines whether the given leadId is the record selected
     *              as the winning source for the block-level Address override.
     * @param leadId The Lead currently being converted.
     * @return True if fieldOverrides['Address'] equals leadId.
     */
    private Boolean isWinningAddressSource(Id leadId) {
        if (fieldOverrides == null || !fieldOverrides.containsKey(DuplicateComparisonFields.ADDRESS_KEY)) {
            return false;
        }
        Id winningAddressId = (Id) fieldOverrides.get(DuplicateComparisonFields.ADDRESS_KEY);
        return winningAddressId == leadId;
    }

    /**
     * @description Queries the winning Lead's compound Address subfields. MUST be
     *              called before Database.convertLead() — see the caller's Step 1b
     *              comment for why a post-conversion re-read is not safe.
     * @param leadId The winning Lead to snapshot.
     * @return The Lead record with its Address subfields populated, or null if not found/accessible.
     */
    private Lead captureWinningLeadAddress(Id leadId) {
        List<String> fields = new List<String>{ 'Id' };
        fields.addAll(DuplicateComparisonFields.addressSubfields('Lead'));
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Lead WHERE Id = :leadId LIMIT 1';
        List<Lead> results = (List<Lead>) Security.stripInaccessible(
            AccessType.READABLE,
            Database.query(query)
        ).getRecords();
        return results.isEmpty() ? null : (Lead) results[0];
    }

    /**
     * @description Applies non-Address fieldOverrides to the master Contact and,
     *              when this lead was the selected Address winner, writes its
     *              pre-captured Address onto the master's Mailing* subfields via
     *              the shared DuplicateMergeService.mergeAddressField() helper.
     * @param masterContact       The Contact being mutated (queried or Id-only).
     * @param capturedLeadAddress The winning Lead's pre-convert Address snapshot, or null.
     * @param isAddressWinner     Whether this lead was the selected Address winner.
     * @return True if masterContact was mutated and needs to be updated.
     */
    private Boolean applyOverridesAndAddress(Contact masterContact, Lead capturedLeadAddress, Boolean isAddressWinner) {
        Map<String, String> safeOverrides = sanitizeContactOverrides(fieldOverrides);
        Boolean mutated = !safeOverrides.isEmpty();
        if (mutated) {
            for (String fieldName : safeOverrides.keySet()) {
                masterContact.put(fieldName, safeOverrides.get(fieldName));
            }
        }

        if (isAddressWinner && capturedLeadAddress != null) {
            DuplicateMergeService.mergeAddressField(masterContact, capturedLeadAddress, 'Contact');
            mutated = true;
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
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class DuplicateMergeException extends Exception {}
}
