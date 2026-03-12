import { LightningElement, api, wire } from 'lwc';
import getEvaluationSnapshot from '@salesforce/apex/AFEvaluationSnapshotController.getEvaluationSnapshot';

export default class AfeEvaluationSnapshot extends LightningElement {
    @api recordId;

    snapshot;
    error;

    @wire(getEvaluationSnapshot, { afeId: '$recordId' })
    wiredSnapshot({ data, error }) {
        if (data) {
            this.snapshot = data;
            this.error = undefined;
            return;
        }
        if (error) {
            this.error = error;
            this.snapshot = undefined;
        }
    }

    get hasData() {
        return !!this.snapshot;
    }

    get evaluatorName() {
        return this.snapshot?.evaluatorName || 'Unassigned';
    }

    get statusValue() {
        return this.snapshot?.status || 'Not Started';
    }

    get dueDateValue() {
        return this.snapshot?.dueDate;
    }

    get weightedTotalValue() {
        return this.snapshot?.weightedTotal;
    }

    get hasWeightedTotal() {
        return this.weightedTotalValue !== null && this.weightedTotalValue !== undefined;
    }

    get recommendationValue() {
        return this.snapshot?.recommendation || 'Pending';
    }

    get applicationTitle() {
        return this.snapshot?.applicationTitle || 'N/A';
    }

    get requestedAmount() {
        return this.snapshot?.requestedAmount;
    }

    get fundingOpportunityName() {
        return this.snapshot?.fundingOpportunityName || 'N/A';
    }

    get statusBadgeClass() {
        const status = (this.statusValue || '').toLowerCase();
        if (status.includes('complete')) {
            return 'badge badge-success';
        }
        if (status.includes('progress') || status.includes('review')) {
            return 'badge badge-info';
        }
        return 'badge badge-neutral';
    }

    get recommendationBadgeClass() {
        const recommendation = (this.recommendationValue || '').toLowerCase();
        if (recommendation.includes('award') || recommendation.includes('approve')) {
            return 'badge badge-success';
        }
        if (recommendation.includes('revision') || recommendation.includes('pending')) {
            return 'badge badge-warning';
        }
        if (recommendation.includes('deny') || recommendation.includes('reject')) {
            return 'badge badge-critical';
        }
        return 'badge badge-neutral';
    }
}
