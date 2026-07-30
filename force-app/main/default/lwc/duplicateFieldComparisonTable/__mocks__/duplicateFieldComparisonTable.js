import { LightningElement, api } from 'lwc';

/**
 * Test-only stub for c-duplicate-field-comparison-table used by
 * duplicateClusterDetail's Jest suite. Keeps that suite isolated to its own
 * override-resolution logic instead of re-exercising the table's own
 * rendering (covered independently by this component's own __tests__).
 */
export default class DuplicateFieldComparisonTableStub extends LightningElement {
    @api members;
    @api fieldOverrideMap;
    @api isMerged;
    @api isReadOnly;
    @api masterRecordId;
}
