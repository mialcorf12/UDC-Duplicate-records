/**
 * @description AuraEnabled controller for polling the status of a cross-object merge job.
 *              Queries AsyncApexJob for execution state and maps it to a UI-friendly status.
 *
 *              Note: DuplicateMergeAudit__c does not have a JobId__c field in the current
 *              data model — audit correlation is deferred to a future enhancement.
 *              Job status is derived from AsyncApexJob.Status alone.
 */
public with sharing class MergeStatusController {

    /**
     * @description Returns the current status of an async Apex job (Queueable or Batch).
     *              Maps Salesforce job status values to UI-friendly labels:
     *              - Queued / Holding / Preparing → 'Queued'
     *              - Processing / InProgress      → 'Processing'
     *              - Completed                    → 'Completed'
     *              - Failed / Aborted             → 'Failed'
     *
     * @param jobId  The AsyncApexJob.Id returned when the job was enqueued.
     * @return Map with keys: status (String), message (String).
     * @throws AuraHandledException if jobId is blank.
     */
    @AuraEnabled
    public static Map<String, Object> getJobStatus(String jobId) {
        if (String.isBlank(jobId)) {
            throw new AuraHandledException('jobId is required');
        }

        List<AsyncApexJob> jobs = [
            SELECT Id, Status, ExtendedStatus
            FROM   AsyncApexJob
            WHERE  Id = :jobId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        if (jobs.isEmpty()) {
            return new Map<String, Object>{
                'status'  => 'NotFound',
                'message' => 'Job not found: ' + jobId
            };
        }

        AsyncApexJob job = jobs[0];

        // Map platform status to UI-friendly status
        String uiStatus;
        String sfStatus = job.Status;

        if (sfStatus == 'Completed') {
            uiStatus = 'Completed';
        } else if (sfStatus == 'Failed' || sfStatus == 'Aborted') {
            uiStatus = 'Failed';
        } else if (sfStatus == 'Processing' || sfStatus == 'InProgress') {
            uiStatus = 'Processing';
        } else {
            // Queued, Holding, Preparing
            uiStatus = 'Queued';
        }

        return new Map<String, Object>{
            'status'  => uiStatus,
            'message' => String.isNotBlank(job.ExtendedStatus)
                             ? job.ExtendedStatus
                             : uiStatus
        };
    }
}
