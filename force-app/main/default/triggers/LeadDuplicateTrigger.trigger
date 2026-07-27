trigger LeadDuplicateTrigger on Lead (after update) {
    LeadDuplicateTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
}
