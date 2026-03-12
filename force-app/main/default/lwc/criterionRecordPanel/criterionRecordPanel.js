/**
 * Criterion Record Panel
 *
 * Purpose:
 * - Show a beginner-friendly detail view for the currently selected criterion.
 * - Help admins understand where a criterion is used in real evaluations.
 *
 * Data flow:
 * Parent passes criterionId -> Apex wire fetches detail DTO -> UI renders fields/links.
 */
import { LightningElement, api, wire } from 'lwc';
import getCriterionRecordPanelData from '@salesforce/apex/EvaluationCriteriaManagerReadController.getCriterionRecordPanelData';

export default class CriterionRecordPanel extends LightningElement {
    @api criterionId;
    criterion;

    @wire(getCriterionRecordPanelData, { criterionId: '$criterionId' })
    wiredCriterion({ data }) {
        // Convert raw DTO values into display-friendly values/URLs for template rendering.
        if (!data) {
            this.criterion = null;
            return;
        }

        this.criterion = {
            ...data,
            defaultWeightDisplay: data.defaultWeight === null || data.defaultWeight === undefined
                ? '--'
                : data.defaultWeight,
            recentApplicationUsages: (data.recentApplicationUsages || []).map((row, index) => ({
                key: row.evaluationId || row.applicationFormId || `usage-${index}`,
                ...row,
                appFormUrl: row.applicationFormId ? `/${row.applicationFormId}` : null,
                evaluationUrl: row.evaluationId ? `/${row.evaluationId}` : null
            }))
        };
    }

    get hasRecentUsage() {
        return (this.criterion?.recentApplicationUsages || []).length > 0;
    }
}
