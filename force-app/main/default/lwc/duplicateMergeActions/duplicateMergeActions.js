import { LightningElement, api, track } from 'lwc';
import mergeCluster from '@salesforce/apex/DuplicateMergeController.mergeCluster';
import ignoreCluster from '@salesforce/apex/DuplicateMergeController.ignoreCluster';
import getJobStatus from '@salesforce/apex/MergeStatusController.getJobStatus';

const POLL_INTERVAL_MS = 2000;
const MAX_POLL_RETRIES = 3;

export default class DuplicateMergeActions extends LightningElement {
    @api clusterId;
    @api masterId;
    @api fieldOverrideMap;

    @track isLoading = false;
    @track currentStep = null;
    @track errorMessage = null;

    _jobId = null;
    _pollTimer = null;
    _pollCount = 0;

    get isMergeDisabled() {
        return !this.masterId || this.isLoading;
    }

    async handleMerge() {
        if (!this.masterId) {
            this.errorMessage = 'Please select a master record before merging.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = null;
        this.currentStep = 'Queued';

        try {
            const result = await mergeCluster({
                clusterId: this.clusterId,
                masterId: this.masterId,
                fieldOverrides: this.fieldOverrideMap || {}
            });

            if (result.jobId) {
                // Cross-object: start polling
                this._jobId = result.jobId;
                this._pollCount = 0;
                this.currentStep = 'Processing';
                this._startPolling();
            } else if (result.success) {
                // Same-object: immediate success
                this.isLoading = false;
                this.currentStep = null;
                this._fireMergeDone(true, result.message || 'Merge completed successfully.');
            } else {
                this.isLoading = false;
                this.currentStep = null;
                this.errorMessage = result.message || 'Merge failed.';
                this._fireMergeDone(false, this.errorMessage);
            }
        } catch (error) {
            this.isLoading = false;
            this.currentStep = null;
            this.errorMessage = error.body ? error.body.message : 'Merge failed unexpectedly.';
            this._fireMergeDone(false, this.errorMessage);
        }
    }

    async handleIgnore() {
        this.isLoading = true;
        this.errorMessage = null;

        try {
            await ignoreCluster({ clusterId: this.clusterId, reason: 'Manually ignored via console' });
            this.isLoading = false;
            this._fireMergeDone(true, 'Cluster ignored successfully.');
        } catch (error) {
            this.isLoading = false;
            this.errorMessage = error.body ? error.body.message : 'Ignore operation failed.';
            this._fireMergeDone(false, this.errorMessage);
        }
    }

    _startPolling() {
        this._pollTimer = setTimeout(() => {
            this._poll();
        }, POLL_INTERVAL_MS);
    }

    async _poll() {
        this._pollCount++;

        try {
            const result = await getJobStatus({ jobId: this._jobId });
            const status = result.status;

            if (status === 'Completed') {
                this._stopPolling();
                this.isLoading = false;
                this.currentStep = null;
                this._fireMergeDone(true, result.message || 'Merge completed.');
            } else if (status === 'Failed') {
                this._stopPolling();
                this.isLoading = false;
                this.currentStep = null;
                this.errorMessage = result.message || 'Merge failed during processing.';
                this._fireMergeDone(false, this.errorMessage);
            } else if (this._pollCount >= MAX_POLL_RETRIES) {
                // Max retries reached — stop and report timeout
                this._stopPolling();
                this.isLoading = false;
                this.currentStep = null;
                this.errorMessage = 'Merge is taking longer than expected. Check audit log for status.';
                this._fireMergeDone(false, this.errorMessage);
            } else {
                // Still in progress — continue polling
                this.currentStep = status || 'Processing';
                this._pollTimer = setTimeout(() => {
                    this._poll();
                }, POLL_INTERVAL_MS);
            }
        } catch (error) {
            // On poll error count against retries
            if (this._pollCount >= MAX_POLL_RETRIES) {
                this._stopPolling();
                this.isLoading = false;
                this.currentStep = null;
                this.errorMessage = 'Unable to retrieve merge status. Check audit log.';
                this._fireMergeDone(false, this.errorMessage);
            } else {
                // Retry
                this._pollTimer = setTimeout(() => {
                    this._poll();
                }, POLL_INTERVAL_MS);
            }
        }
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearTimeout(this._pollTimer);
            this._pollTimer = null;
        }
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    _fireMergeDone(success, message) {
        this.dispatchEvent(
            new CustomEvent('mergedone', {
                detail: {
                    clusterId: this.clusterId,
                    success,
                    message
                },
                bubbles: false,
                composed: false
            })
        );
    }
}
