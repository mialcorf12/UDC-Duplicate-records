trigger ContactDuplicateTrigger on Contact (after update) {
    ContactDuplicateTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
}
