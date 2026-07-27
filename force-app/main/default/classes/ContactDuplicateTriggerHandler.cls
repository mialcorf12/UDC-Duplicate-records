/**
 * @description Handler for ContactDuplicateTrigger.
 *              Marks associated DuplicateCluster__c records as 'Stale' when
 *              key fields (Email, Phone, FirstName, LastName) change on a Contact.
 *              Only Open or Partial clusters are updated — Merged and Ignored
 *              clusters are intentionally left unchanged.
 */
public with sharing class ContactDuplicateTriggerHandler {

    // Fields whose change should invalidate (Stale) an associated cluster
    private static final Set<String> TRACKED_FIELDS = new Set<String>{
        'Email', 'Phone', 'FirstName', 'LastName'
    };

    /**
     * @description Entry point called from ContactDuplicateTrigger (after update).
     *              Identifies contacts where a tracked field changed, finds
     *              associated clusters, and marks qualifying clusters as Stale.
     *
     * @param oldMap Map of Contact Id → old Contact snapshot from Trigger.oldMap.
     * @param newMap Map of Contact Id → new Contact snapshot from Trigger.newMap.
     */
    public static void handleAfterUpdate(
        Map<Id, Contact> oldMap,
        Map<Id, Contact> newMap
    ) {
        // Step 1 — collect IDs where a tracked field changed
        Set<Id> changedIds = new Set<Id>();
        for (Id cId : newMap.keySet()) {
            Contact newC = newMap.get(cId);
            Contact oldC = oldMap.get(cId);
            if (newC.Email     != oldC.Email     ||
                newC.Phone     != oldC.Phone     ||
                newC.FirstName != oldC.FirstName ||
                newC.LastName  != oldC.LastName) {
                changedIds.add(cId);
            }
        }

        if (changedIds.isEmpty()) {
            return;
        }

        // Step 2 — find clusters whose members include these contacts
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
