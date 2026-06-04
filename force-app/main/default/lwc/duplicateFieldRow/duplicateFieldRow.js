import { LightningElement, api, track } from 'lwc';

export default class DuplicateFieldRow extends LightningElement {
    @api fieldLabel;
    @api fieldName;
    @api selectedRecordId;

    _values = [];

    @api
    get values() {
        return this._values;
    }
    set values(incoming) {
        this._values = (incoming || []).map((v) => ({
            ...v,
            inputId: `${this.fieldName}-${v.recordId}`,
            isSelected: v.recordId === this.selectedRecordId
        }));
    }

    handleRadioChange(event) {
        const winningRecordId = event.target.value;
        this.dispatchEvent(
            new CustomEvent('fieldoverride', {
                detail: { fieldName: this.fieldName, winningRecordId },
                bubbles: true,
                composed: true
            })
        );
    }
}
