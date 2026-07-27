import { LightningElement, api } from 'lwc';

// Standard (same-object) flow steps
const STEPS_STANDARD = ['Queued', 'Processing', 'Completed'];
// Cross-object flow steps
const STEPS_CROSS = ['Queued', 'Converting', 'Merging', 'Completed'];

const STEP_LABELS = {
    Queued: 'Queued',
    Processing: 'Processing',
    Converting: 'Converting',
    Merging: 'Merging',
    Completed: 'Completed'
};

const STATUS_LABELS = {
    Queued: 'Waiting in queue…',
    Processing: 'Processing merge…',
    Converting: 'Converting lead…',
    Merging: 'Merging contacts…',
    Completed: 'Merge complete.',
    Failed: 'Merge failed.',
    Idle: ''
};

export default class DuplicateMergeProgress extends LightningElement {
    @api step = 'Idle';

    get isVisible() {
        return this.step && this.step !== 'Idle';
    }

    get isFailed() {
        return this.step === 'Failed';
    }

    get isCompleted() {
        return this.step === 'Completed';
    }

    get isCrossObject() {
        return this.step === 'Converting' || this.step === 'Merging';
    }

    get activeSteps() {
        // If we ever see Converting or Merging, this is a cross-object flow
        return this.isCrossObject ? STEPS_CROSS : STEPS_STANDARD;
    }

    get steps() {
        const activeSteps = this.activeSteps;
        const currentIdx = activeSteps.indexOf(this.step);

        return activeSteps.map((s, idx) => {
            const isComplete = idx < currentIdx;
            const isActive = idx === currentIdx;
            let cssClass = 'slds-progress__item';
            if (isComplete) cssClass += ' slds-is-completed';
            else if (isActive) cssClass += ' slds-is-active';

            let containerClass = 'step-item';
            if (isComplete) containerClass += ' is-complete';
            else if (isActive) containerClass += ' is-active';

            return {
                label: STEP_LABELS[s] || s,
                labelId: `step-label-${s}`,
                cssClass,
                containerClass,
                isComplete
            };
        });
    }

    get progressPercent() {
        const activeSteps = this.activeSteps;
        const currentIdx = activeSteps.indexOf(this.step);
        if (currentIdx < 0) return 0;
        return Math.round((currentIdx / (activeSteps.length - 1)) * 100);
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get statusLabel() {
        return STATUS_LABELS[this.step] || '';
    }
}
