import { LightningElement, track } from 'lwc';

export default class DuplicateFilterBar extends LightningElement {
    @track objectType = null;
    @track status = 'Open';
    @track minScore = 0;

    get objectTypeOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Contact', value: 'Contact' },
            { label: 'Lead', value: 'Lead' },
            { label: 'Mixed', value: 'Mixed' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Open', value: 'Open' },
            { label: 'Stale', value: 'Stale' },
            { label: 'Ignored', value: 'Ignored' },
            { label: 'Merged', value: 'Merged' }
        ];
    }

    handleObjectTypeChange(event) {
        this.objectType = event.detail.value || null;
    }

    handleStatusChange(event) {
        this.status = event.detail.value || null;
    }

    handleMinScoreChange(event) {
        const val = parseInt(event.detail.value, 10);
        this.minScore = isNaN(val) ? 0 : Math.min(100, Math.max(0, val));
    }

    handleApply() {
        this.dispatchEvent(
            new CustomEvent('filterchange', {
                detail: {
                    objectType: this.objectType || null,
                    status: this.status || null,
                    minScore: this.minScore
                },
                bubbles: false,
                composed: false
            })
        );
    }
}
