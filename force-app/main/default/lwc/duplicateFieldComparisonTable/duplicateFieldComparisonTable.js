import { LightningElement, api } from 'lwc';

// Fields to display in the comparison grid (in order)
const COMPARISON_FIELDS = [
    { fieldName: 'Email', fieldLabel: 'Email' },
    { fieldName: 'Phone', fieldLabel: 'Phone' },
    { fieldName: 'Name', fieldLabel: 'Name' },
    { fieldName: 'Company', fieldLabel: 'Company' }
];

const OBJECT_TYPE_BADGE = {
    Contact: 'slds-badge slds-badge_lightest slds-theme_info',
    Lead: 'slds-badge slds-badge_lightest slds-theme_warning'
};

export default class DuplicateFieldComparisonTable extends LightningElement {
    _members = [];
    _parsedMembers = [];

    @api fieldOverrideMap = {};

    @api
    get members() {
        return this._members;
    }
    set members(incoming) {
        this._members = incoming || [];
        this._parsedMembers = this._parseMembers(this._members);
    }

    _parseMembers(members) {
        return (members || []).map((m) => {
            let snapshot = {};
            try {
                snapshot = m.FieldSnapshotJSON__c
                    ? JSON.parse(m.FieldSnapshotJSON__c)
                    : {};
            } catch (e) {
                snapshot = {};
            }
            return {
                recordId: m.RecordId__c || m.Id,
                objectType: m.ObjectType__c || 'Contact',
                snapshot
            };
        });
    }

    get hasMembers() {
        return this._parsedMembers && this._parsedMembers.length > 0;
    }

    get memberHeaders() {
        return this._parsedMembers.map((m) => ({
            recordId: m.recordId,
            objectType: m.objectType,
            title: `${m.objectType} — ${m.recordId}`,
            shortId: m.recordId ? m.recordId.slice(-6) : '',
            badgeClass: OBJECT_TYPE_BADGE[m.objectType] || 'slds-badge'
        }));
    }

    get fieldRows() {
        return COMPARISON_FIELDS.map((f) => {
            const values = this._parsedMembers.map((m) => ({
                recordId: m.recordId,
                value: m.snapshot[f.fieldName] || '',
                objectType: m.objectType
            }));
            const selectedRecordId = this.fieldOverrideMap
                ? this.fieldOverrideMap[f.fieldName]
                : null;

            return {
                fieldName: f.fieldName,
                fieldLabel: f.fieldLabel,
                values,
                selectedRecordId: selectedRecordId || null
            };
        });
    }

    handleFieldOverride(event) {
        // Bubble up the fieldoverride event from duplicateFieldRow
        this.dispatchEvent(
            new CustomEvent('fieldoverride', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );
    }
}
