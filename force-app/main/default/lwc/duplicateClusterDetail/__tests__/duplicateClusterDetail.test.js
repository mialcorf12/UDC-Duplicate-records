import { createElement } from 'lwc';
import DuplicateClusterDetail from 'c/duplicateClusterDetail';
import getClusterDetail from '@salesforce/apex/DuplicateClusterController.getClusterDetail';

// The mock factory must build the adapter entirely inside its own closure
// (via require, not a captured module-scope const) — jest.mock() factories
// run the first time the mocked path is require()'d, which happens while
// 'c/duplicateClusterDetail' itself is being loaded, i.e. before any
// module-scope const declared later in this file would be initialized.
jest.mock(
    '@salesforce/apex/DuplicateClusterController.getClusterDetail',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/wire-service-jest-util');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/DuplicateClusterController.setMasterRecord',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Use the lightweight stubs under each component's __mocks__ folder so this
// suite stays focused on duplicateClusterDetail's own override-resolution
// logic instead of re-exercising the child components' own rendering/Apex.
jest.mock('c/duplicateFieldComparisonTable');
jest.mock('c/duplicateMergeActions');

const MASTER_ID = '003000000000001AAA';
const WINNER_ID = '00Q000000000001AAA';

const CLUSTER_DATA = {
    cluster: {
        Id: 'a00000000000001AAA',
        Name: 'CLUST-0001',
        Status__c: 'Open',
        ObjectType__c: 'Mixed',
        ClusterScore__c: 90,
        RecordCount__c: 2,
        DetectedDate__c: '2026-07-01T00:00:00.000Z'
    },
    members: [
        {
            Id: 'm1',
            RecordId__c: MASTER_ID,
            ObjectType__c: 'Contact',
            IsMaster__c: true,
            FieldSnapshotJSON__c: JSON.stringify({
                FirstName: 'Addr',
                LastName: 'Master',
                Address: '1 Old St, OldCity, OS, 00000, US'
            })
        },
        {
            Id: 'm2',
            RecordId__c: WINNER_ID,
            ObjectType__c: 'Lead',
            IsMaster__c: false,
            FieldSnapshotJSON__c: JSON.stringify({
                FirstName: 'Addr',
                LastName: 'Winner',
                Address: '2 New Ave, NewCity, NS, 11111, US'
            })
        }
    ]
};

function createDetail() {
    const element = createElement('c-duplicate-cluster-detail', {
        is: DuplicateClusterDetail
    });
    element.clusterId = CLUSTER_DATA.cluster.Id;
    document.body.appendChild(element);
    return element;
}

describe('c-duplicate-cluster-detail — Address override resolution', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('passes the winning record Id (not the flattened Address string) to the merge action component', () => {
        const element = createDetail();
        getClusterDetail.emit(CLUSTER_DATA);

        return Promise.resolve()
            .then(() => {
                const table = element.shadowRoot.querySelector(
                    'c-duplicate-field-comparison-table'
                );
                expect(table).not.toBeNull();

                // Simulate the user picking the Lead's Address block as the winner.
                table.dispatchEvent(
                    new CustomEvent('fieldoverride', {
                        detail: { fieldName: 'Address', winningRecordId: WINNER_ID }
                    })
                );
                return Promise.resolve();
            })
            .then(() => {
                const mergeActions = element.shadowRoot.querySelector(
                    'c-duplicate-merge-actions'
                );
                expect(mergeActions).not.toBeNull();
                expect(mergeActions.fieldOverrideMap.Address).toBe(WINNER_ID);
                // Must NOT be resolved to the lossy formatted display string.
                expect(mergeActions.fieldOverrideMap.Address).not.toBe(
                    '2 New Ave, NewCity, NS, 11111, US'
                );
            });
    });

    it('resolves a scalar field override to the winning snapshot value, unlike the Address special case', () => {
        const element = createDetail();
        getClusterDetail.emit(CLUSTER_DATA);

        return Promise.resolve()
            .then(() => {
                const table = element.shadowRoot.querySelector(
                    'c-duplicate-field-comparison-table'
                );
                table.dispatchEvent(
                    new CustomEvent('fieldoverride', {
                        detail: { fieldName: 'FirstName', winningRecordId: MASTER_ID }
                    })
                );
                return Promise.resolve();
            })
            .then(() => {
                const mergeActions = element.shadowRoot.querySelector(
                    'c-duplicate-merge-actions'
                );
                // Scalar fields resolve to the snapshot's actual value, not the record Id.
                expect(mergeActions.fieldOverrideMap.FirstName).toBe('Addr');
            });
    });

    it('does not throw and renders no Address override when the fieldOverrideMap starts empty', () => {
        const element = createDetail();
        getClusterDetail.emit(CLUSTER_DATA);

        return Promise.resolve().then(() => {
            const mergeActions = element.shadowRoot.querySelector(
                'c-duplicate-merge-actions'
            );
            expect(mergeActions).not.toBeNull();
            // Auto-selection on load defaults every field (incl. Address) to the
            // first member's winning record Id — this must not throw and must
            // resolve Address to a record Id, never undefined.
            expect(mergeActions.fieldOverrideMap.Address).toBe(MASTER_ID);
        });
    });
});
