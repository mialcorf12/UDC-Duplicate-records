import { LightningElement, api } from 'lwc';

/**
 * Test-only stub for c-duplicate-merge-actions used by duplicateClusterDetail's
 * Jest suite. Captures the resolvedFieldOverrides map passed down from the
 * parent so tests can assert on it without exercising the real merge-actions
 * component's own Apex/merge logic.
 */
export default class DuplicateMergeActionsStub extends LightningElement {
    @api clusterId;
    @api masterId;
    @api fieldOverrideMap;
}
