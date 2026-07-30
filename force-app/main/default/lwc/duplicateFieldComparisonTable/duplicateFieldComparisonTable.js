import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const BASE_FIELDS = [
    { fieldName: 'Portal_User_ID__c',   fieldLabel: 'Portal User ID' },
    { fieldName: 'FirstName',           fieldLabel: 'First Name' },
    { fieldName: 'LastName',            fieldLabel: 'Last Name' },
    { fieldName: 'Email',               fieldLabel: 'Email' },
    { fieldName: 'Phone',               fieldLabel: 'Phone' },
    { fieldName: 'MobilePhone',         fieldLabel: 'Mobile Phone' },
    { fieldName: 'AccountId',           fieldLabel: 'Company', displayFieldName: 'Company' },
    { fieldName: 'Sales_Informed_Agreement_Signed__c', fieldLabel: 'Date Account Agreement Signed' },
    { fieldName: 'Email_Collection__c', fieldLabel: 'Email Collection' },
    // Address is a single block-level row: one radio per record selects the
    // entire compound address, not per-subfield rows. The row displays the
    // pre-formatted "Address" string from the snapshot; the merge write itself
    // (object-type-aware subfield mapping) is handled server-side.
    { fieldName: 'Address',             fieldLabel: 'Address' }
];

const OBJECT_TYPE_BADGE = {
    Contact: 'slds-badge slds-badge_lightest slds-theme_info',
    Lead: 'slds-badge slds-badge_lightest slds-theme_warning'
};

export default class DuplicateFieldComparisonTable extends NavigationMixin(LightningElement) {
    _members = [];
    _parsedMembers = [];

    @api fieldOverrideMap = {};
    @api isMerged = false;
    @api isReadOnly = false;
    @api masterRecordId;

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

    get comparisonFields() {
        return [...BASE_FIELDS];
    }

    get fieldRows() {
        return this.comparisonFields.map((f) => {
            const selectedRecordId = this.fieldOverrideMap
                ? this.fieldOverrideMap[f.fieldName]
                : null;
            const values = this._parsedMembers.map((m) => {
                const value = m.snapshot[f.displayFieldName || f.fieldName] || '';
                const isHighlighted = f.fieldName === 'Portal_User_ID__c' && !!value;
                const highlightSuffix = isHighlighted ? ' slds-text-color_error slds-text-title_bold' : '';
                return {
                    recordId: m.recordId,
                    value,
                    objectType: m.objectType,
                    inputId: `${f.fieldName}-${m.recordId}`,
                    isSelected: selectedRecordId === m.recordId,
                    isMaster: m.recordId === this.masterRecordId,
                    isHighlighted,
                    plainTextClass: `slds-text-body_small slds-text-color_weak${highlightSuffix}`,
                    badgeClass: `slds-badge slds-badge_lightest${highlightSuffix}`,
                    labelClass: `slds-form-element__label slds-truncate${highlightSuffix}`
                };
            });

            return {
                fieldName: f.fieldName,
                fieldLabel: f.fieldLabel,
                values
            };
        });
    }

    handleRecordClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        }).then((url) => {
            window.open(url, '_blank');
        });
    }

    handleRadioChange(event) {
        const fieldName = event.target.dataset.fieldName;
        const winningRecordId = event.target.value;
        this.dispatchEvent(
            new CustomEvent('fieldoverride', {
                detail: { fieldName, winningRecordId },
                bubbles: true,
                composed: true
            })
        );
    }
}
