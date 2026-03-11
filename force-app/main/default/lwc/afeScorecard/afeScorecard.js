import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getScores from '@salesforce/apex/AFEScorecardController.getScores';
import saveScores from '@salesforce/apex/AFEScorecardController.saveScores';
import getEvaluationSummary from '@salesforce/apex/AFEScorecardController.getEvaluationSummary';
import getApplicationContext from '@salesforce/apex/AFEScorecardController.getApplicationContext';
import generateAISuggestion from '@salesforce/apex/AFEScorecardController.generateAISuggestion';
import generateAISuggestionsForEvaluation from '@salesforce/apex/AFEScorecardController.generateAISuggestionsForEvaluation';

export default class AfeScorecard extends LightningElement {
    _recordId;
    _lastLoadedRecordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value && value !== this._lastLoadedRecordId) {
            this.refreshAll();
        }
    }

    rows = [];
    summary;
    applicationContext = { fundingOpportunity: {}, applicationForm: {} };
    hasStatusField = false;

    isLoading = false;
    isSaving = false;
    isAiAllLoading = false;
    aiMode = 'OVERWRITE_ALL';

    pendingChanges = new Map();
    currentScreen = 'context';

    connectedCallback() {
        if (this.recordId) {
            this.refreshAll();
        }
    }

    get weightedTotal() {
        return this.summary?.Weighted_Total__c;
    }

    get hasWeightedTotal() {
        return this.weightedTotal !== null && this.weightedTotal !== undefined;
    }

    get recommendationLabel() {
        return this.summary?.Final_Recommendation__c || 'Not Yet Rated';
    }

    get recommendationBadgeClass() {
        const base = 'slds-badge';
        const rec = this.summary?.Final_Recommendation__c;
        if (rec === 'Award') {
            return `${base} slds-theme_success`;
        }
        if (rec === 'Ask for Revisions') {
            return `${base} slds-theme_warning`;
        }
        if (rec === 'Deny') {
            return `${base} slds-theme_error`;
        }
        return base;
    }

    get createdDate() {
        return this.summary?.CreatedDate;
    }

    get statusValue() {
        return this.summary?.Status__c || 'N/A';
    }

    get isSaveDisabled() {
        return this.isLoading || this.isSaving || this.pendingChanges.size === 0;
    }

    get isAiAllDisabled() {
        return this.isLoading || this.isSaving || this.isAiAllLoading || !this.rows.length;
    }

    get isContextScreen() {
        return this.currentScreen === 'context';
    }

    get isScoringScreen() {
        return this.currentScreen === 'scoring';
    }

    async refreshAll() {
        if (!this.recordId) {
            return;
        }

        this.isLoading = true;
        try {
            const [summaryResult, scoreResult, contextResult] = await Promise.all([
                getEvaluationSummary({ afeId: this.recordId }),
                getScores({ afeId: this.recordId }),
                getApplicationContext({ afeId: this.recordId })
            ]);

            this.summary = summaryResult || null;
            this.hasStatusField = !!(summaryResult && Object.prototype.hasOwnProperty.call(summaryResult, 'Status__c'));
            this.rows = (scoreResult || []).map((row) => this.toViewModel(row));
            this.applicationContext = contextResult || { fundingOpportunity: {}, applicationForm: {} };
            this._lastLoadedRecordId = this.recordId;
            this.pendingChanges.clear();
        } catch (error) {
            this.showToast('Error Loading Scorecard', this.normalizeError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get fundingOpportunity() {
        return this.applicationContext?.fundingOpportunity || {};
    }

    get applicationForm() {
        return this.applicationContext?.applicationForm || {};
    }

    get fundingName() {
        return this.fundingOpportunity.name;
    }

    get fundingProgramMin() {
        return this.fundingOpportunity.programMin;
    }

    get hasFundingProgramMin() {
        return this.fundingProgramMin !== null && this.fundingProgramMin !== undefined;
    }

    get fundingProgramMax() {
        return this.fundingOpportunity.programMax;
    }

    get hasFundingProgramMax() {
        return this.fundingProgramMax !== null && this.fundingProgramMax !== undefined;
    }

    get applicationFormName() {
        return this.applicationForm.name;
    }

    get hasApplicationFormName() {
        return !!this.applicationFormName;
    }

    get applicationFormPurpose() {
        return this.applicationForm.purpose;
    }

    get applicationFormRequestedAmount() {
        return this.applicationForm.requestedAmount;
    }

    get applicationFormSummary() {
        return this.applicationForm.applicationSummary;
    }

    get hasApplicationFormRequestedAmount() {
        return this.applicationFormRequestedAmount !== null && this.applicationFormRequestedAmount !== undefined;
    }

    get applicationFormStage() {
        return this.applicationForm.stage;
    }

    get hasApplicationFormStage() {
        return !!this.applicationFormStage;
    }

    get applicationFormType() {
        return this.applicationForm.type;
    }

    get hasApplicationFormType() {
        return !!this.applicationFormType;
    }

    get scoredCriteriaRows() {
        return (this.rows || [])
            .filter((row) => row.finalScore !== null && row.finalScore !== undefined)
            .map((row) => ({
                id: row.id,
                sectionName: row.sectionName || 'General',
                criterionLabel: row.label || 'Untitled Criterion',
                weightDisplay: row.weightDisplay || '--',
                finalScoreDisplay: row.finalScore,
                rationaleDisplay: this.normalizeRationale(row.rationaleInput) || 'No rationale provided.',
                hasRationale: !!this.normalizeRationale(row.rationaleInput)
            }));
    }

    get hasScoredCriteriaRows() {
        return this.scoredCriteriaRows.length > 0;
    }

    toViewModel(row) {
        const rationaleInput = this.normalizeRationale(row.Rationale__c);

        return {
            id: row.Id,
            sectionName: row.Section_Name__c || '--',
            criterionKey: row.Criterion_Key__c || '',
            label: row.Label__c || 'Untitled Criterion',
            weight: row.Weight__c,
            weightDisplay: row.Weight__c !== null && row.Weight__c !== undefined ? `${row.Weight__c}%` : '--',
            suggestedScore: row.Suggested_Score__c,
            originalSuggestedScore: row.Suggested_Score__c,
            suggestedScoreDisplay:
                row.Suggested_Score__c !== null && row.Suggested_Score__c !== undefined
                    ? row.Suggested_Score__c
                    : '--',
            finalScore: row.Final_Score__c,
            originalFinalScore: row.Final_Score__c,
            finalScoreInput:
                row.Final_Score__c !== null && row.Final_Score__c !== undefined
                    ? Number(row.Final_Score__c)
                    : null,
            rationaleInput,
            originalRationale: rationaleInput,
            finalScoreLabel: `Score for ${row.Label__c || 'criterion'}`,
            finalScoreTitle: `Enter score from 0 to 5 for ${row.Label__c || 'criterion'}`,
            rationaleLabel: `Rationale for ${row.Label__c || 'criterion'}`,
            rationaleTitle: `Enter optional rationale for ${row.Label__c || 'criterion'}`,
            displayOrder: row.Display_Order__c,
            isAiLoading: false
        };
    }

    get aiModeOptions() {
        return [
            { label: 'Overwrite all', value: 'OVERWRITE_ALL' },
            { label: 'Fill blanks only', value: 'FILL_BLANKS' }
        ];
    }

    handleAiModeChange(event) {
        this.aiMode = event.detail.value;
    }

    handleScoreChange(event) {
        const rowId = event.target.dataset.id;
        const rawValue = event?.target?.value;
        const row = this.rows.find((r) => r.id === rowId);

        if (!rowId || !row) {
            return;
        }

        if (rawValue === '' || rawValue === null || rawValue === undefined) {
            this.updateRowFinalScore(rowId, null);
            this.updatePendingChange(rowId, row.suggestedScore, null, row.rationaleInput, row.originalSuggestedScore, row.originalFinalScore, row.originalRationale);
            return;
        }

        const parsed = Number(rawValue);
        const isInteger = Number.isInteger(parsed);
        if (!isInteger || parsed < 0 || parsed > 5) {
            this.showToast('Invalid Score', 'Score must be a whole number between 0 and 5.', 'error');
            event.target.value = row.finalScoreInput;
            return;
        }

        this.updateRowFinalScore(rowId, parsed);
        this.updatePendingChange(rowId, row.suggestedScore, parsed, row.rationaleInput, row.originalSuggestedScore, row.originalFinalScore, row.originalRationale);
    }

    handleRationaleChange(event) {
        const rowId = event.target.dataset.id;
        const row = this.rows.find((r) => r.id === rowId);
        if (!rowId || !row) {
            return;
        }

        const rationale = this.normalizeRationale(event?.detail?.value ?? event?.target?.value);
        this.updateRowRationale(rowId, rationale);
        this.updatePendingChange(rowId, row.suggestedScore, row.finalScore, rationale, row.originalSuggestedScore, row.originalFinalScore, row.originalRationale);
    }

    syncPendingChangesFromDom() {
        const scoreInputs = this.template.querySelectorAll('lightning-input[data-id]');
        scoreInputs.forEach((inputCmp) => {
            const rowId = inputCmp?.dataset?.id;
            const row = this.rows.find((r) => r.id === rowId);
            if (!rowId || !row) {
                return;
            }

            const rawValue = inputCmp.value;
            let parsedScore = null;
            if (rawValue !== '' && rawValue !== null && rawValue !== undefined) {
                const parsed = Number(rawValue);
                if (Number.isInteger(parsed) && parsed >= 0 && parsed <= 5) {
                    parsedScore = parsed;
                } else {
                    return;
                }
            }

            this.updateRowFinalScore(rowId, parsedScore);
            this.updatePendingChange(
                rowId,
                row.suggestedScore,
                parsedScore,
                row.rationaleInput,
                row.originalSuggestedScore,
                row.originalFinalScore,
                row.originalRationale
            );
        });

        const rationaleInputs = this.template.querySelectorAll('lightning-textarea[data-id]');
        rationaleInputs.forEach((textareaCmp) => {
            const rowId = textareaCmp?.dataset?.id;
            const row = this.rows.find((r) => r.id === rowId);
            if (!rowId || !row) {
                return;
            }

            const rationale = this.normalizeRationale(textareaCmp.value);
            this.updateRowRationale(rowId, rationale);
            this.updatePendingChange(
                rowId,
                row.suggestedScore,
                row.finalScore,
                rationale,
                row.originalSuggestedScore,
                row.originalFinalScore,
                row.originalRationale
            );
        });
    }

    updateRowFinalScore(rowId, score) {
        this.rows = this.rows.map((row) => {
            if (row.id !== rowId) {
                return row;
            }
            return {
                ...row,
                finalScore: score,
                finalScoreInput: score
            };
        });
    }

    updateRowRationale(rowId, rationale) {
        this.rows = this.rows.map((row) => {
            if (row.id !== rowId) {
                return row;
            }
            return {
                ...row,
                rationaleInput: rationale
            };
        });
    }

    async handleGenerateSuggestion(event) {
        const rowId = event.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === rowId);
        if (!rowId || !row || !this.recordId) {
            return;
        }

        this.setRowAiLoading(rowId, true);
        try {
            const result = await generateAISuggestion({
                evaluationId: this.recordId,
                criterionScoreId: rowId
            });

            const suggestedScore = Number(result?.suggestedScore);
            const isValidSuggestion = Number.isInteger(suggestedScore) && suggestedScore >= 0 && suggestedScore <= 5;
            const aiScore = isValidSuggestion ? suggestedScore : null;
            const aiRationale = this.normalizeRationale(result?.suggestedRationale);
            const nextFinalScore = row.finalScore;

            this.rows = this.rows.map((candidate) => {
                if (candidate.id !== rowId) {
                    return candidate;
                }
                return {
                    ...candidate,
                    suggestedScore: aiScore,
                    suggestedScoreDisplay: aiScore !== null ? aiScore : '--',
                    finalScore: nextFinalScore,
                    finalScoreInput: nextFinalScore,
                    rationaleInput: aiRationale
                };
            });

            // Single-row AI runs persist immediately so users can refresh safely without losing generated text.
            await saveScores({
                updates: [{
                    Id: rowId,
                    Suggested_Score__c: aiScore,
                    Final_Score__c: nextFinalScore,
                    Rationale__c: aiRationale
                }]
            });

            await this.notifyRelatedRecordUpdates();
            await this.refreshAll();
            if (result?.source === 'fallback') {
                this.showToast(
                    'Fallback Suggestion Applied',
                    result?.warning || 'AI runtime unavailable; fallback suggestion applied.',
                    'warning'
                );
            } else {
                this.showToast('AI Suggestion Applied', 'Suggested score and rationale were saved.', 'success');
            }
        } catch (error) {
            this.showToast('AI Suggestion Failed', this.normalizeError(error), 'error');
        } finally {
            this.setRowAiLoading(rowId, false);
        }
    }

    async handleGenerateAllSuggestions() {
        if (!this.recordId || !this.rows.length) {
            return;
        }

        this.isAiAllLoading = true;
        try {
            const results = await generateAISuggestionsForEvaluation({
                evaluationId: this.recordId,
                mode: this.aiMode
            });
            const byId = new Map((results || []).map((item) => [item.criterionScoreId, item]));
            let updatedCount = 0;
            let fallbackCount = 0;

            this.rows = this.rows.map((row) => {
                const suggestion = byId.get(row.id);
                if (!suggestion || suggestion.skipped) {
                    return row;
                }

                const suggestedScore = Number(suggestion.suggestedScore);
                const validScore = Number.isInteger(suggestedScore) && suggestedScore >= 0 && suggestedScore <= 5
                    ? suggestedScore
                    : null;
                const rationale = this.normalizeRationale(suggestion.suggestedRationale);
                const nextFinalScore = row.finalScore;
                updatedCount++;
                if (suggestion.source === 'fallback') {
                    fallbackCount++;
                }

                // Bulk AI writes are staged in pendingChanges; reviewer confirms with Save Scores.
                this.updatePendingChange(
                    row.id,
                    validScore,
                    nextFinalScore,
                    rationale,
                    row.originalSuggestedScore,
                    row.originalFinalScore,
                    row.originalRationale
                );

                return {
                    ...row,
                    suggestedScore: validScore,
                    suggestedScoreDisplay: validScore !== null ? validScore : '--',
                    finalScore: nextFinalScore,
                    finalScoreInput: nextFinalScore,
                    rationaleInput: rationale
                };
            });

            if (updatedCount === 0) {
                this.showToast('AI Review Complete', 'No criteria required updates for the selected mode.', 'info');
            } else if (fallbackCount > 0) {
                this.showToast(
                    'AI Review Complete',
                    `${updatedCount} criterion suggestions prepared (${fallbackCount} using fallback). Click Save Scores to persist.`,
                    'warning'
                );
            } else {
                this.showToast(
                    'AI Review Complete',
                    `${updatedCount} criterion suggestions prepared. Click Save Scores to persist.`,
                    'success'
                );
            }
        } catch (error) {
            this.showToast('AI Review Failed', this.normalizeError(error), 'error');
        } finally {
            this.isAiAllLoading = false;
        }
    }

    setRowAiLoading(rowId, isLoading) {
        this.rows = this.rows.map((row) => {
            if (row.id !== rowId) {
                return row;
            }
            return {
                ...row,
                isAiLoading: isLoading
            };
        });
    }

    goToScoringScreen() {
        this.currentScreen = 'scoring';
    }

    goToContextScreen() {
        this.currentScreen = 'context';
    }

    async handleSave() {
        this.syncPendingChangesFromDom();
        if (this.pendingChanges.size === 0) {
            return;
        }

        this.isSaving = true;
        this.isLoading = true;
        try {
            const payload = Array.from(this.pendingChanges.entries()).map(([id, change]) => ({
                Id: id,
                Suggested_Score__c: change.suggestedScore,
                Final_Score__c: change.finalScore,
                Rationale__c: this.normalizeRationale(change.rationale)
            }));

            await saveScores({ updates: payload });
            await this.notifyRelatedRecordUpdates();
            this.showToast('Success', 'Evaluation scores saved successfully.', 'success');
            await this.refreshAll();
        } catch (error) {
            this.showToast('Save Failed', this.normalizeError(error), 'error');
        } finally {
            this.isSaving = false;
            this.isLoading = false;
        }
    }

    normalizeError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return 'An unexpected error occurred while processing the scorecard.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    updatePendingChange(
        rowId,
        suggestedScore,
        finalScore,
        rationale,
        originalSuggestedScore,
        originalFinalScore,
        originalRationale
    ) {
        const normalizedOriginalRationale = this.normalizeRationale(originalRationale);
        const normalizedRationale = this.normalizeRationale(rationale);
        const isSuggestedChanged = suggestedScore !== originalSuggestedScore;
        const isFinalChanged = finalScore !== originalFinalScore;
        const isRationaleChanged = normalizedRationale !== normalizedOriginalRationale;

        if (isSuggestedChanged || isFinalChanged || isRationaleChanged) {
            this.pendingChanges.set(rowId, {
                suggestedScore,
                finalScore,
                rationale: normalizedRationale
            });
            return;
        }
        this.pendingChanges.delete(rowId);
    }

    normalizeRationale(value) {
        return value === null || value === undefined ? '' : value;
    }

    async notifyRelatedRecordUpdates() {
        const recordIds = [];
        if (this.recordId) {
            recordIds.push({ recordId: this.recordId });
        }

        const applicationFormId = this.applicationForm?.id;
        if (applicationFormId) {
            recordIds.push({ recordId: applicationFormId });
        }

        if (recordIds.length > 0) {
            // Notify LDS so other record-page components (for example snapshot/status cards) refresh in place.
            await notifyRecordUpdateAvailable(recordIds);
        }
    }
}
