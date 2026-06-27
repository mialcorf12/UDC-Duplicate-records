/**
 * @description AuraEnabled controller for launching the DuplicateDetectionBatch job.
 *              Returns the AsyncApexJob Id as a String for client-side polling.
 */
public with sharing class BatchLaunchController {

    @TestVisible
    private static Boolean throwForTest = false;

    /**
     * @description Enqueues the DuplicateDetectionBatch with a chunk size of 200
     *              and returns the resulting AsyncApexJob Id.
     *
     * @return String representation of the AsyncApexJob Id.
     * @throws AuraHandledException if the batch could not be enqueued.
     */
    @AuraEnabled
    public static String launchDetection() {
        try {
            if (throwForTest) throw new IllegalArgumentException('forced test exception');
            DuplicateDetectionBatch batch = new DuplicateDetectionBatch();
            Id jobId = Database.executeBatch(batch, 200);
            return String.valueOf(jobId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
