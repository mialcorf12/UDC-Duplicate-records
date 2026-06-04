/**
 * @description Handler for LeadDuplicateTrigger.
 *              Marks associated DuplicateCluster__c records as 'Stale' when
 *              key fields (Email, Phone, FirstName, LastName, Company) change on a Lead.
 *              Only Open or Partial clusters are updated — Merged and Ignored
 *              clusters are intentionally left unchanged.
 *
 *              Note: Company is tracked in addition to the standard four fields
 *              because it is a significant identifier for Lead records and
 *              feeds into the scoring weight system.
 */
public with sharing class LeadDuplicateTriggerHandler {

    // Fields whose change should invalidate (Stale) an associated cluster
    private static final Set<String> TRACKED_FIELDS = new Set<String>{
        'Email', 'Phone', 'FirstName', 'LastName', 'Company'
    };

    /**
     * @description Entry point called from LeadDuplicateTrigger (after update).
     *              Identifies leads where a tracked field changed, finds
     *              associated clusters, and marks qualifying clusters as Stale.
     *
     * @param oldMap Map of Lead Id → old Lead snapshot from Trigger.oldMap.
     * @param newMap Map of Lead Id → new Lead snapshot from Trigger.newMap.
     */
    public static void handleAfterUpdate(
        Map<Id, Lead> oldMap,
        Map<Id, Lead> newMap
    ) {
        // Step 1 — collect IDs where a tracked field changed
        Set<Id> changedIds = new Set<Id>();
        for (Id lId : newMap.keySet()) {
            Lead newL = newMap.get(lId);
            Lead oldL = oldMap.get(lId);
            if (newL.Email     != oldL.Email     ||
                newL.Phone     != oldL.Phone     ||
                newL.FirstName != oldL.FirstName ||
                newL.LastName  != oldL.LastName  ||
                newL.Company   != oldL.Company) {
                changedIds.add(lId);
            }
        }

        if (changedIds.isEmpty()) {
            return;
        }

        // Step 2 — find clusters whose members include these leads
        List<DuplicateCluster__c> clusters =
            DuplicateClusterSelector.getByMemberRecordIds(changedIds);

        if (clusters.isEmpty()) {
            return;
        }

        // Step 3 — mark only Open or Partial clusters as Stale
        List<DuplicateCluster__c> toUpdate = new List<DuplicateCluster__c>();
        for (DuplicateCluster__c c : clusters) {
            if (c.Status__c == 'Open' || c.Status__c == 'Partial') {
                toUpdate.add(new DuplicateCluster__c(
                    Id        = c.Id,
                    Status__c = 'Stale'
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
