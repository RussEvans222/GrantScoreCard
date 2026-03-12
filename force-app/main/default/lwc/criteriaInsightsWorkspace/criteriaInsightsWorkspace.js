/**
 * Criteria Insights Workspace
 *
 * Purpose:
 * - Lets admins run AI framework review against an evaluation template.
 * - Displays structured results (scores, issues, recommendations, improvements).
 *
 * Data flow:
 * LWC button click -> Apex analyzeFramework() -> DTO response -> UI cards/lists.
 */
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEvaluationTemplateOptions from '@salesforce/apex/EvaluationCriteriaManagerReadController.getEvaluationTemplateOptions';
import analyzeFramework from '@salesforce/apex/EvaluationFrameworkReviewService.analyzeFramework';
import applySingleRecommendation from '@salesforce/apex/EvaluationFrameworkReviewService.applySingleRecommendation';

export default class CriteriaInsightsWorkspace extends NavigationMixin(LightningElement) {
    selectedTemplateId;
    templateOptions = [];
    applyLibraryActions = false;
    errorMessage;
    result;
    actionInProgress = false;
    isRefreshing = false;
    appliedRecommendationKeys = new Set();
    wiredTemplateOptionsResult;

    @wire(getEvaluationTemplateOptions)
    wiredTemplates(wiredResult) {
        this.wiredTemplateOptionsResult = wiredResult;
        const { data } = wiredResult;
        // Loads template selector options from Apex (real org data, not mocks).
        if (data) {
            this.templateOptions = (data || []).map((row) => ({ label: row.label, value: row.id }));
        }
    }

    get isAnalyzeDisabled() {
        return !this.selectedTemplateId;
    }

    get selectedTemplateLabel() {
        const match = (this.templateOptions || []).find((item) => item.value === this.selectedTemplateId);
        return match ? match.label : '--';
    }

    get frameworkHealthPercent() {
        const value = this.result?.review?.frameworkHealthScore;
        if (value === null || value === undefined) {
            return 0;
        }
        return Math.max(0, Math.min(100, Number(value) * 10));
    }

    get frameworkHealthDisplay() {
        const value = this.result?.review?.frameworkHealthScore;
        return value === null || value === undefined ? '--' : value;
    }

    get dimensionChips() {
        const dims = this.result?.review?.dimensionScores || {};
        return [
            { label: 'Clarity', value: this.toDisplay(dims.clarity) },
            { label: 'Balance', value: this.toDisplay(dims.balance) },
            { label: 'Coverage', value: this.toDisplay(dims.coverage) },
            { label: 'Redundancy', value: this.toDisplay(dims.redundancy) }
        ];
    }

    get issues() {
        return (this.result?.review?.issues || []).map((issue, index) => ({
            key: `${issue.type || 'issue'}-${index}`,
            type: issue.type || '--',
            message: issue.message || '--'
        }));
    }

    get recommendations() {
        return (this.result?.review?.recommendations || []).map((rec, index) => ({
            key: `${rec.type || 'rec'}-${index}`,
            ...rec,
            typeLabel: (rec.type || '--').replace(/_/g, ' '),
            suggestedWeightDisplay: rec.suggestedWeight === null || rec.suggestedWeight === undefined ? '--' : rec.suggestedWeight,
            actionLabel: this.getActionLabel(rec.type),
            canApply: this.isActionableType(rec.type),
            isApplied: this.appliedRecommendationKeys.has(`${rec.type || ''}|${rec.name || ''}`)
        }));
    }

    get improvements() {
        return (this.result?.review?.improvements || []).map((item, index) => ({
            key: `${item.criterion || 'improvement'}-${index}`,
            criterion: item.criterion || '--',
            message: item.message || '--'
        }));
    }

    get libraryNotes() {
        return this.result?.libraryActionSummary?.notes || [];
    }

    get persistedMessage() {
        if (!this.result) {
            return '';
        }
        if (this.result.persistedFieldApiName) {
            return `Analysis retained on template field: ${this.result.persistedFieldApiName}`;
        }
        if (this.result.templateFieldsUpdated) {
            return 'Template framework score fields were updated.';
        }
        return 'No persistence field for full insight JSON was found in this org.';
    }

    get relatedCriteria() {
        return this.result?.relatedCriteria || [];
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handleOpenTemplateRecord() {
        if (!this.selectedTemplateId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedTemplateId,
                objectApiName: 'Evaluation_Template__c',
                actionName: 'view'
            }
        });
    }

    handleApplyToggle(event) {
        this.applyLibraryActions = event.target.checked;
    }

    async handleAnalyze() {
        // Main Apex -> LWC communication point for framework AI analysis.
        await this.runAnalysis(true);
    }

    async runAnalysis(showToastOnSuccess) {
        this.errorMessage = null;
        this.appliedRecommendationKeys = new Set();

        try {
            const response = await analyzeFramework({
                evaluationTemplateId: this.selectedTemplateId,
                applyLibraryActions: this.applyLibraryActions,
                applyTemplateFieldUpdates: true
            });

            if (!response?.success) {
                this.result = null;
                this.errorMessage = response?.message || 'Framework analysis failed.';
                return;
            }

            this.result = response;
            if (showToastOnSuccess) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Framework Analysis Complete',
                        message: response.message,
                        variant: 'success'
                    })
                );
            }
        } catch (error) {
            this.result = null;
            this.errorMessage = error?.body?.message || error?.message || 'Framework analysis failed.';
        }
    }

    handleExportJson() {
        // Convenience export for debugging/learning what AI returned.
        const json = this.result?.reviewJson;
        if (!json) {
            return;
        }
        const blob = new Blob([json], { type: 'application/json' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = `framework-review-${this.selectedTemplateId || 'template'}.json`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(link.href);
    }

    async handleRecommendationAction(event) {
        const type = event.currentTarget.dataset.type;
        const name = event.currentTarget.dataset.name;
        const description = event.currentTarget.dataset.description;
        const suggestedWeightRaw = event.currentTarget.dataset.weight;
        let suggestedWeight =
            suggestedWeightRaw === undefined || suggestedWeightRaw === null || suggestedWeightRaw === ''
                ? null
                : Number(suggestedWeightRaw);
        if (suggestedWeight !== null && Number.isNaN(suggestedWeight)) {
            suggestedWeight = null;
        }

        if (!this.selectedTemplateId || !type || !name) {
            return;
        }

        this.actionInProgress = true;
        try {
            const response = await applySingleRecommendation({
                evaluationTemplateId: this.selectedTemplateId,
                recommendationType: type,
                recommendationName: name,
                recommendationDescription: description,
                suggestedWeight
            });
            if (!response?.success) {
                throw new Error(response?.message || 'Action failed.');
            }

            this.appliedRecommendationKeys.add(`${type}|${name}`);
            this.appliedRecommendationKeys = new Set(this.appliedRecommendationKeys);

            if (this.result && response.summary) {
                this.result = {
                    ...this.result,
                    libraryActionSummary: {
                        ...(this.result.libraryActionSummary || {}),
                        createdCount: (this.result.libraryActionSummary?.createdCount || 0) + (response.summary.createdCount || 0),
                        flaggedForReviewCount: (this.result.libraryActionSummary?.flaggedForReviewCount || 0) + (response.summary.flaggedForReviewCount || 0),
                        suggestedWeightUpdates: (this.result.libraryActionSummary?.suggestedWeightUpdates || 0) + (response.summary.suggestedWeightUpdates || 0),
                        skippedCount: (this.result.libraryActionSummary?.skippedCount || 0) + (response.summary.skippedCount || 0),
                        notes: [...(this.result.libraryActionSummary?.notes || []), ...(response.summary.notes || [])]
                    }
                };
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Recommendation Applied',
                    message: response.message,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Action Failed',
                    message: error?.body?.message || error?.message || 'Unable to apply recommendation.',
                    variant: 'error'
                })
            );
        } finally {
            this.actionInProgress = false;
        }
    }

    isActionableType(type) {
        const normalized = (type || '').toLowerCase();
        return normalized === 'newcriterion' || normalized === 'modifycriterion' || normalized === 'adjustweight';
    }

    getActionLabel(type) {
        const normalized = (type || '').toLowerCase();
        if (normalized === 'newcriterion') {
            return 'Create Draft Criterion';
        }
        if (normalized === 'modifycriterion') {
            return 'Flag For Review';
        }
        if (normalized === 'adjustweight') {
            return 'Apply Suggested Weight';
        }
        return 'No Action';
    }

    toDisplay(value) {
        return value === null || value === undefined ? '--' : value;
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            if (this.wiredTemplateOptionsResult) {
                await refreshApex(this.wiredTemplateOptionsResult);
            }
            if (this.selectedTemplateId && this.result) {
                await this.runAnalysis(false);
            }
            if (this.errorMessage) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Refresh Failed',
                        message: this.errorMessage,
                        variant: 'error'
                    })
                );
                return;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refreshed',
                    message: 'Template options and insight values were refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refresh Failed',
                    message: error?.body?.message || error?.message || 'Unable to refresh criteria insights.',
                    variant: 'error'
                })
            );
        } finally {
            this.isRefreshing = false;
        }
    }
}
