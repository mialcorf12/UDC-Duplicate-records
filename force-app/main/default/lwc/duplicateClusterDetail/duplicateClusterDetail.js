import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getClusterDetail from '@salesforce/apex/DuplicateClusterController.getClusterDetail';
import setMasterRecord from '@salesforce/apex/DuplicateClusterController.setMasterRecord';

// Canonical comparison-table key for the block-level, object-type-aware
// Address field. Mirrors DuplicateComparisonFields.ADDRESS_KEY on the Apex side.
const ADDRESS_FIELD_KEY = 'Address';

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

            // Auto-select the first record for all fields when cluster is not Merged
            const clusterStatus = data.cluster?.Status__c;
            if (clusterStatus !== 'Merged' && clusterStatus !== 'Ignored' && members.length > 0) {
                const firstId = members[0].RecordId__c || members[0].Id;
                let firstSnapshot = {};
                try { firstSnapshot = JSON.parse(members[0].FieldSnapshotJSON__c || '{}'); } catch (e) {}
                const initialOverrides = {};
                Object.keys(firstSnapshot).forEach((f) => { initialOverrides[f] = firstId; });
                this.fieldOverrideMap = initialOverrides;
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
        return status !== 'Merged' && status !== 'Archived' && status !== 'Ignored';
    }

    get isMerged() {
        const status = this.cluster?.Status__c;
        return status === 'Merged' || status === 'Archived';
    }

    get isMasterDisabled() {
        const status = this.cluster?.Status__c;
        return status === 'Merged' || status === 'Archived' || status === 'Ignored' || status === 'Stale';
    }

    get isReadOnly() {
        const status = this.cluster?.Status__c;
        return status === 'Ignored' || status === 'Archived' || status === 'Stale';
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
        const newMasterId = event.target.value;
        this.selectedMasterId = newMasterId;
        setMasterRecord({ clusterId: this._clusterId, memberRecordId: newMasterId })
            .catch(error => {
                this.errorMessage = error.body ? error.body.message : 'Failed to update master record.';
            });
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
            // Address is a compound, object-type-aware field: the snapshot only
            // holds a formatted display string, which is lossy for merge. Pass
            // the winning record Id through as-is so the merge service can
            // re-read the live compound subfields off the correct source record.
            if (fieldName === ADDRESS_FIELD_KEY) {
                result[fieldName] = winningRecordId;
                continue;
            }

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
