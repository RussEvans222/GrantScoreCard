import { LightningElement, api } from 'lwc';
import {
    FlowNavigationBackEvent,
    FlowNavigationNextEvent
} from 'lightning/flowSupport';

export default class FlowStepNavigator extends LightningElement {
    @api availableActions = [];
    @api stepNumber;
    @api totalSteps;
    @api stepLabel;

    get canGoBack() {
        // Some runtime containers don't provide availableActions consistently.
        // Default to enabled unless Flow explicitly omits the action.
        if (!Array.isArray(this.availableActions) || this.availableActions.length === 0) {
            return true;
        }
        return this.availableActions.includes('BACK');
    }

    get canGoNext() {
        if (!Array.isArray(this.availableActions) || this.availableActions.length === 0) {
            return true;
        }
        return this.availableActions.includes('NEXT');
    }

    get disableBack() {
        return !this.canGoBack;
    }

    get disableNext() {
        return !this.canGoNext;
    }

    get progressPercent() {
        const step = Number(this.stepNumber) || 1;
        const total = Number(this.totalSteps) || 1;
        if (total <= 1) {
            return 100;
        }
        return Math.min(100, Math.max(0, Math.round((step / total) * 100)));
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%;`;
    }

    handleBack() {
        if (this.canGoBack) {
            this.dispatchEvent(new FlowNavigationBackEvent());
        }
    }

    handleNext() {
        if (this.canGoNext) {
            this.dispatchEvent(new FlowNavigationNextEvent());
        }
    }
}