import { api } from 'lwc';
import OmniscriptBaseMixin from 'omnistudio/omniscriptBaseMixin';

export default class GrantDiscoveryIntakeStep extends OmniscriptBaseMixin(class {}) {
    // OmniScript node source for step 1 discovery text.
    @api projectDescription = '';
    @api analyzeRequested = false;

    get isAnalyzeDisabled() {
        return !this.projectDescription || !this.projectDescription.trim();
    }

    handleDescriptionChange(event) {
        this.projectDescription = event.detail.value;
        this.analyzeRequested = false;
        this.syncOmniContext();
    }

    handleAnalyzeProject() {
        this.analyzeRequested = true;
        this.syncOmniContext();
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

    syncOmniContext() {
        // Keep OmniScript JSON aligned so IPs can read context.projectDescription.
        this.omniApplyCallResp({
            context: {
                projectDescription: this.projectDescription
            },
            meta: {
                analyzeRequested: this.analyzeRequested
            }
        });
    }
}
