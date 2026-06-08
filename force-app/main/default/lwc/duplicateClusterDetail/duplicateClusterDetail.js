import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getClusterDetail from '@salesforce/apex/DuplicateClusterController.getClusterDetail';

export default class DuplicateClusterDetail extends LightningElement {
    @track fieldOverrideMap = {};
    @track selectedMasterId = null;
    @track errorMessage = null;

    _clusterId = null;
    _wiredDetailResult;

    @api
    get clusterId() {
        return this._clusterId;
    }
    set clusterId(value) {
        this._clusterId = value;
        // Reset state when cluster changes
        this.fieldOverrideMap = {};
        this.selectedMasterId = null;
        this.errorMessage = null;
    }

    @wire(getClusterDetail, { clusterId: '$_clusterId' })
    wiredDetail(result) {
        this._wiredDetailResult = result;
        const { data, error } = result;
        this.errorMessage = null;

        if (data) {
            // Pre-select the master member
            const members = data.members || [];
            const masterMember = members.find((m) => m.IsMaster__c);
            if (masterMember) {
                this.selectedMasterId = masterMember.RecordId__c;
            } else if (members.length > 0) {
                this.selectedMasterId = members[0].RecordId__c;
            }
        } else if (error) {
            this.errorMessage = error.body
                ? error.body.message
                : 'Error loading cluster details.';
        }
    }

    get hasClusterId() {
        return !!this._clusterId;
    }

    get isLoading() {
        return this.hasClusterId && !this._wiredDetailResult;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasData() {
        return (
            !this.isLoading &&
            !this.hasError &&
            this._wiredDetailResult &&
            this._wiredDetailResult.data
        );
    }

    get cluster() {
        return this._wiredDetailResult && this._wiredDetailResult.data
            ? this._wiredDetailResult.data.cluster
            : null;
    }

    get rawMembers() {
        return this._wiredDetailResult && this._wiredDetailResult.data
            ? this._wiredDetailResult.data.members || []
            : [];
    }

    get parsedMembers() {
        // The table component handles JSON parsing internally
        return this.rawMembers;
    }

    get memberOptions() {
        return this.rawMembers.map((m) => ({
            recordId: m.RecordId__c,
            inputId: `master-${m.RecordId__c}`,
            label: `${m.ObjectType__c || 'Record'} — ${m.RecordId__c ? m.RecordId__c.slice(-6) : ''}`,
            isSelected: m.RecordId__c === this.selectedMasterId
        }));
    }

    get isMergeAllowed() {
        const status = this.cluster?.Status__c;
        return status !== 'Merged' && status !== 'Ignored';
    }

    get formattedDate() {
        if (!this.cluster || !this.cluster.DetectedDate__c) return '';
        try {
            return new Date(this.cluster.DetectedDate__c).toLocaleDateString();
        } catch (e) {
            return this.cluster.DetectedDate__c;
        }
    }

    handleMasterChange(event) {
        this.selectedMasterId = event.target.value;
    }

    handleFieldOverride(event) {
        const { fieldName, winningRecordId } = event.detail;
        this.fieldOverrideMap = {
            ...this.fieldOverrideMap,
            [fieldName]: winningRecordId
        };
    }

    get resolvedFieldOverrides() {
        const result = {};
        for (const [fieldName, winningRecordId] of Object.entries(this.fieldOverrideMap || {})) {
            const member = this.rawMembers.find(
                (m) => (m.RecordId__c || m.Id) === winningRecordId
            );
            if (member) {
                let snapshot = {};
                try { snapshot = JSON.parse(member.FieldSnapshotJSON__c || '{}'); } catch (e) {}
                result[fieldName] = snapshot[fieldName] ?? '';
            }
        }
        return result;
    }

    handleMergeDone(event) {
        const { success, message } = event.detail;

        if (!success) {
            this.errorMessage = message || 'Merge failed.';
        }

        // Refresh wire data
        refreshApex(this._wiredDetailResult);

        // Fire clustermerged event up to the container
        this.dispatchEvent(
            new CustomEvent('clustermerged', {
                detail: event.detail,
                bubbles: false,
                composed: false
            })
        );
    }
}
