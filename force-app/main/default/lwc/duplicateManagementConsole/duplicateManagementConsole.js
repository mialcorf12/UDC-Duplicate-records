import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import launchDetection from '@salesforce/apex/BatchLaunchController.launchDetection';
import launchBulkMerge from '@salesforce/apex/DuplicateMergeController.launchBulkMerge';
import getArchivableDates from '@salesforce/apex/DuplicateClusterController.getArchivableDates';
import archiveClustersByDate from '@salesforce/apex/DuplicateClusterController.archiveClustersByDate';

export default class DuplicateManagementConsole extends LightningElement {
    @track selectedClusterId = null;
    @track objectType = null;
    @track status = 'Open';
    @track minScore = 0;

    @track activeSections = ['clusters'];
    @track bulkMergeScore = 100;
    @track bulkMergeObjectType = '';
    @track isBulkMerging = false;

    @track isDetecting = false;
    @track detectionJobId = null;

    @track archiveDate = null;
    @track archiveDateOptions = [];
    @track isArchiving = false;

    get bulkMergeObjectTypeOptions() {
        return [
            { label: 'All',     value: '' },
            { label: 'Contact', value: 'Contact' },
            { label: 'Lead',    value: 'Lead' },
            { label: 'Mixed',   value: 'Mixed' }
        ];
    }

    connectedCallback() {
        getArchivableDates()
            .then(options => { this.archiveDateOptions = options; })
            .catch(() => {});
    }

    handleFilterChange(event) {
        const { objectType, status, minScore } = event.detail;
        this.objectType = objectType || null;
        this.status = status || null;
        this.minScore = minScore || 0;
        // Changing filters resets selection
        this.selectedClusterId = null;
    }

    handleClusterSelect(event) {
        this.selectedClusterId = event.detail.clusterId;
    }

    handleClusterMerged() {
        // Reset selection — the list will re-run its wire on the next interaction
        this.selectedClusterId = null;
    }

    handleRunDetection() {
        this.isDetecting = true;
        launchDetection()
            .then(jobId => {
                this.detectionJobId = jobId;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Detection Started',
                    message: `Batch job enqueued: ${jobId}`,
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.isDetecting = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : 'An unexpected error occurred.',
                    variant: 'error'
                }));
            });
    }

    handleBulkScoreChange(event) {
        this.bulkMergeScore = parseFloat(event.detail.value);
    }

    handleBulkObjectTypeChange(event) {
        this.bulkMergeObjectType = event.detail.value;
    }

    handleBulkMerge() {
        this.isBulkMerging = true;
        const objectType = this.bulkMergeObjectType || null;
        launchBulkMerge({ minScore: this.bulkMergeScore, objectType })
            .then(jobId => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Bulk Merge Started',
                    message: `Job ID: ${jobId}`,
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Bulk Merge Failed',
                    message: error.body ? error.body.message : 'An unexpected error occurred.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isBulkMerging = false;
            });
    }

    handleArchiveDateChange(event) {
        this.archiveDate = event.detail.value;
    }

    handleArchive() {
        if (!this.archiveDate) { return; }
        this.isArchiving = true;
        archiveClustersByDate({ dateValue: this.archiveDate })
            .then(count => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Archive Completed',
                    message: `${count} clusters archived successfully.`,
                    variant: 'success'
                }));
                return getArchivableDates();
            })
            .then(options => {
                this.archiveDateOptions = options;
                this.archiveDate = null;
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : 'An unexpected error occurred.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isArchiving = false;
            });
    }
}
