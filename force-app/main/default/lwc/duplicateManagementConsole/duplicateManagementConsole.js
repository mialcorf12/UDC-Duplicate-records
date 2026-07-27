import { LightningElement, track } from 'lwc';

export default class DuplicateManagementConsole extends LightningElement {
    @track selectedClusterId = null;
    @track objectType = null;
    @track status = 'Open';
    @track minScore = 0;

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
}
