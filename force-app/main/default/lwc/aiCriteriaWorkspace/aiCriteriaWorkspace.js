/**
 * AI Criteria Workspace (Scaffold)
 *
 * This component intentionally provides placeholder actions.
 * It teaches developers where future AI tools (generator/improver/builder)
 * will be connected without changing production business behavior today.
 */
import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AiCriteriaWorkspace extends LightningElement {
    handlePlaceholder(event) {
        const tool = event.currentTarget.dataset.tool;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Coming Soon',
                message: `The ${tool} tool is scaffolded and will be activated in a later phase.`,
                variant: 'info'
            })
        );
    }
}
