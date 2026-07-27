import { LightningElement, api } from 'lwc';

const OBJECT_TYPE_BADGE = {
    Contact: 'slds-badge slds-badge_lightest slds-theme_info',
    Lead: 'slds-badge slds-badge_lightest slds-theme_warning',
    Mixed: 'slds-badge slds-badge_lightest slds-theme_shade'
};

const STATUS_BADGE = {
    Open: 'slds-badge slds-badge_success',
    Stale: 'slds-badge slds-badge_warning',
    Ignored: 'slds-badge',
    Merged: 'slds-badge slds-badge_inverse',
    Partial: 'slds-badge slds-badge_warning'
};

export default class DuplicateClusterListItem extends LightningElement {
    @api cluster;

    get badgeClass() {
        const objectType = this.cluster && this.cluster.ObjectType__c;
        return OBJECT_TYPE_BADGE[objectType] || 'slds-badge';
    }

    get statusBadgeClass() {
        const status = this.cluster && this.cluster.Status__c;
        return STATUS_BADGE[status] || 'slds-badge';
    }

    get recordCountLabel() {
        const count = this.cluster && this.cluster.RecordCount__c;
        return count === 1 ? '1 record' : `${count || 0} records`;
    }

    handleClick() {
        this._fireSelect();
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this._fireSelect();
        }
    }

    _fireSelect() {
        this.dispatchEvent(
            new CustomEvent('clusterselect', {
                detail: { clusterId: this.cluster.Id },
                bubbles: true,
                composed: true
            })
        );
    }
}
