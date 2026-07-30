import { createElement } from 'lwc';
import DuplicateFieldComparisonTable from 'c/duplicateFieldComparisonTable';

const CONTACT_MEMBER_FULL_SNAPSHOT = {
    RecordId__c: '003000000000001AAA',
    ObjectType__c: 'Contact',
    IsMaster__c: true,
    FieldSnapshotJSON__c: JSON.stringify({
        FirstName: 'John',
        LastName: 'Smith',
        Email: 'john@example.com',
        Phone: '5551234567',
        MobilePhone: '5559998888',
        Company: 'Acme Corp',
        Sales_Informed_Agreement_Signed__c: '2026-01-15',
        Email_Collection__c: 'opted-in',
        Portal_User_ID__c: 'PORTAL001',
        Address: '123 Main St, Springfield, IL, 62701, US'
    })
};

const LEAD_MEMBER_FULL_SNAPSHOT = {
    RecordId__c: '00Q000000000001AAA',
    ObjectType__c: 'Lead',
    IsMaster__c: false,
    FieldSnapshotJSON__c: JSON.stringify({
        FirstName: 'Jane',
        LastName: 'Doe',
        Email: 'jane@company.com',
        Phone: '5559876543',
        MobilePhone: '5551112222',
        Company: 'Acme Corp',
        Sales_Informed_Agreement_Signed__c: '2026-02-01',
        Email_Collection__c: 'opted-out',
        Portal_User_ID__c: 'PORTAL002',
        Address: '456 Oak Ave, Metropolis, NY, 10001, US'
    })
};

// Legacy snapshot predating this change: none of the new fields exist at all.
const LEGACY_MEMBER_MISSING_NEW_FIELDS = {
    RecordId__c: '003000000000002AAA',
    ObjectType__c: 'Contact',
    IsMaster__c: false,
    FieldSnapshotJSON__c: JSON.stringify({
        FirstName: 'Legacy',
        LastName: 'Record',
        Email: 'legacy@example.com',
        Phone: '5550000000',
        Company: 'Old Corp'
    })
};

function createTable(overrides = {}) {
    const element = createElement('c-duplicate-field-comparison-table', {
        is: DuplicateFieldComparisonTable
    });
    Object.assign(element, overrides);
    document.body.appendChild(element);
    return element;
}

describe('c-duplicate-field-comparison-table', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders a row for every new comparison field plus the block-level Address row', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA'
        });

        return Promise.resolve().then(() => {
            const rowLabelCells = element.shadowRoot.querySelectorAll(
                'tbody tr td:first-child span'
            );
            const labels = Array.from(rowLabelCells).map((el) => el.textContent);

            expect(labels).toContain('Mobile Phone');
            expect(labels).toContain('Date Account Agreement Signed');
            expect(labels).toContain('Email Collection');
            expect(labels).toContain('Portal User ID');
            expect(labels).toContain('Address');
        });
    });

    it('renders the formatted Address string as the row value for each record', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA'
        });

        return Promise.resolve().then(() => {
            const radioLabels = element.shadowRoot.querySelectorAll(
                '.slds-radio__label .slds-form-element__label'
            );
            const values = Array.from(radioLabels).map((el) => el.title);

            expect(values).toContain('123 Main St, Springfield, IL, 62701, US');
            expect(values).toContain('456 Oak Ave, Metropolis, NY, 10001, US');
        });
    });

    it('renders blank values (no error) when the snapshot is missing the new field keys', () => {
        const element = createTable({
            members: [LEGACY_MEMBER_MISSING_NEW_FIELDS],
            masterRecordId: '003000000000002AAA'
        });

        return Promise.resolve().then(() => {
            // Row labels must still exist — the table shows the row, just blank.
            const rowLabelCells = element.shadowRoot.querySelectorAll(
                'tbody tr td:first-child span'
            );
            const labels = Array.from(rowLabelCells).map((el) => el.textContent);
            expect(labels).toContain('Portal User ID');
            expect(labels).toContain('Address');

            // The corresponding radio label for the legacy record must render blank text.
            const portalIdRowIndex = labels.indexOf('Portal User ID');
            const rows = element.shadowRoot.querySelectorAll('tbody tr');
            const portalIdRow = rows[portalIdRowIndex];
            const radioLabel = portalIdRow.querySelector(
                '.slds-form-element__label'
            );
            expect(radioLabel.textContent.trim()).toBe('');
        });
    });

    it('dispatches a fieldoverride event with the winning record Id when the Address radio changes', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA'
        });

        const handler = jest.fn();
        element.addEventListener('fieldoverride', handler);

        return Promise.resolve().then(() => {
            const addressRadio = element.shadowRoot.querySelector(
                `input[name="Address"][value="${LEAD_MEMBER_FULL_SNAPSHOT.RecordId__c}"]`
            );
            expect(addressRadio).not.toBeNull();

            addressRadio.checked = true;
            addressRadio.dispatchEvent(new CustomEvent('change'));

            expect(handler).toHaveBeenCalledTimes(1);
            const { detail } = handler.mock.calls[0][0];
            expect(detail.fieldName).toBe('Address');
            expect(detail.winningRecordId).toBe(LEAD_MEMBER_FULL_SNAPSHOT.RecordId__c);
        });
    });

    it('renders read-only plain text (no radios) for every row, including Address, when isReadOnly is true', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA',
            isReadOnly: true
        });

        return Promise.resolve().then(() => {
            const radios = element.shadowRoot.querySelectorAll('input[type="radio"]');
            expect(radios.length).toBe(0);

            const readOnlySpans = element.shadowRoot.querySelectorAll(
                'tbody td span.slds-text-color_weak'
            );
            const readOnlyValues = Array.from(readOnlySpans).map((el) => el.title);
            expect(readOnlyValues).toContain('123 Main St, Springfield, IL, 62701, US');
        });
    });

    it('highlights a populated Portal_User_ID__c value in red/bold on the open (radio) row', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA'
        });

        return Promise.resolve().then(() => {
            const portalRadio = element.shadowRoot.querySelector(
                `input[name="Portal_User_ID__c"][value="${CONTACT_MEMBER_FULL_SNAPSHOT.RecordId__c}"]`
            );
            const label = portalRadio.closest('.slds-radio').querySelector(
                '.slds-form-element__label'
            );
            expect(label.classList).toContain('slds-text-color_error');
            expect(label.classList).toContain('slds-text-bold');

            // A different row (FirstName) must never get the highlight classes.
            const firstNameRadio = element.shadowRoot.querySelector(
                `input[name="FirstName"][value="${CONTACT_MEMBER_FULL_SNAPSHOT.RecordId__c}"]`
            );
            const firstNameLabel = firstNameRadio.closest('.slds-radio').querySelector(
                '.slds-form-element__label'
            );
            expect(firstNameLabel.classList).not.toContain('slds-text-color_error');
        });
    });

    it('does not highlight Portal_User_ID__c when the value is blank', () => {
        const element = createTable({
            members: [LEGACY_MEMBER_MISSING_NEW_FIELDS],
            masterRecordId: '003000000000002AAA'
        });

        return Promise.resolve().then(() => {
            const portalRadio = element.shadowRoot.querySelector(
                `input[name="Portal_User_ID__c"][value="${LEGACY_MEMBER_MISSING_NEW_FIELDS.RecordId__c}"]`
            );
            const label = portalRadio.closest('.slds-radio').querySelector(
                '.slds-form-element__label'
            );
            expect(label.classList).not.toContain('slds-text-color_error');
        });
    });

    it('highlights a populated Portal_User_ID__c value in read-only mode', () => {
        const element = createTable({
            members: [CONTACT_MEMBER_FULL_SNAPSHOT, LEAD_MEMBER_FULL_SNAPSHOT],
            masterRecordId: '003000000000001AAA',
            isReadOnly: true
        });

        return Promise.resolve().then(() => {
            const rows = element.shadowRoot.querySelectorAll('tbody tr');
            const rowLabels = Array.from(rows).map(
                (r) => r.querySelector('td:first-child span').textContent
            );
            const portalRow = rows[rowLabels.indexOf('Portal User ID')];
            const highlighted = portalRow.querySelector('span.slds-text-color_error.slds-text-bold');
            expect(highlighted).not.toBeNull();
        });
    });

    it('shows the empty-state illustration when there are no members', () => {
        const element = createTable({ members: [] });

        return Promise.resolve().then(() => {
            expect(
                element.shadowRoot.textContent
            ).toContain('No member data available.');
        });
    });
});
