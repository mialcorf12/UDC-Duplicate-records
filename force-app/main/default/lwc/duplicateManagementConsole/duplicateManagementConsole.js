import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import launchBulkMerge from '@salesforce/apex/DuplicateMergeController.launchBulkMerge';

export default class DuplicateManagementConsole extends LightningElement {
    @track selectedClusterId = null;
    @track objectType = null;
    @track status = 'Open';
    @track minScore = 0;

    @track activeSections = ['clusters'];
    @track bulkMergeScore = 100;
    @track bulkMergeObjectType = '';
    @track isBulkMerging = false;

    get bulkMergeObjectTypeOptions() {
        return [
            { label: 'All',     value: '' },
            { label: 'Contact', value: 'Contact' },
            { label: 'Lead',    value: 'Lead' },
            { label: 'Mixed',   value: 'Mixed' }
        ];
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
}
