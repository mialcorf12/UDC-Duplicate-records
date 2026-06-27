/**
 * @description Test class for BatchLaunchController.
 *              Verifies that launchDetection returns a non-null job Id and
 *              the job appears in AsyncApexJob after enqueue.
 */
@isTest
private class BatchLaunchControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 1: launchDetection returns a non-null String
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchDetectionReturnsNonNullJobId() {
        Test.startTest();

        String jobId = BatchLaunchController.launchDetection();

        Test.stopTest();

        System.assertNotEquals(null, jobId,
            'launchDetection should return a non-null String');
        System.assert(String.isNotBlank(jobId),
            'Returned jobId should not be blank');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 2: Returned job Id appears in AsyncApexJob after enqueue
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchDetectionJobAppearsInAsyncApexJob() {
        Test.startTest();

        String jobIdStr = BatchLaunchController.launchDetection();

        Test.stopTest();

        Id jobId = (Id) jobIdStr;
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobType
            FROM   AsyncApexJob
            WHERE  Id = :jobId
            LIMIT  1
        ];

        System.assertEquals(1, jobs.size(),
            'AsyncApexJob record should exist for the returned jobId');
        System.assertEquals('BatchApex', jobs[0].JobType,
            'Job type should be BatchApex');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 3: Returned job Id is a valid 18-character Salesforce Id
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchDetectionReturnsValidSalesforceId() {
        Test.startTest();

        String jobId = BatchLaunchController.launchDetection();

        Test.stopTest();

        // Valid Salesforce Id: 15 or 18 characters, starts with '707' (AsyncApexJob prefix)
        System.assert(
            jobId.length() == 15 || jobId.length() == 18,
            'Returned jobId should be a valid Salesforce Id (15 or 18 chars), got: ' + jobId.length()
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario 4: Exception in launchDetection throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void launchDetectionThrowsAuraHandledException() {
        BatchLaunchController.throwForTest = true;
        AuraHandledException caught;

        Test.startTest();
        try {
            BatchLaunchController.launchDetection();
        } catch (AuraHandledException e) {
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught,
            'launchDetection should throw AuraHandledException when an error occurs');
        System.assert(String.isNotBlank(caught.getMessage()),
            'AuraHandledException message should not be blank');
    }

}
