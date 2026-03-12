import { LightningElement, api } from 'lwc';

export default class GrantDiscoveryIntakeStep extends LightningElement {
    // Flow screen input/output field for step 1 discovery text.
    @api projectDescription = '';
    @api analyzeRequested = false;

    get isAnalyzeDisabled() {
        return !this.projectDescription || !this.projectDescription.trim();
    }

    handleDescriptionChange(event) {
        this.projectDescription = event.detail.value;
        this.analyzeRequested = false;
    }

    handleAnalyzeProject() {
        this.analyzeRequested = true;
        this.dispatchEvent(
            new CustomEvent('analyzeproject', {
                detail: {
                    projectDescription: this.projectDescription
                },
                bubbles: true,
                composed: true
            })
        );
    }
}