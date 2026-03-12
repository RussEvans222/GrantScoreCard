/**
 * Template Usage Workspace
 *
 * Purpose:
 * - Helps admins answer: "Where is this criterion used?"
 * - Shows criterion-to-template mapping and version mismatch signals.
 *
 * Data flow:
 * User filters -> Apex getTemplateUsageRows() -> table rows with record links.
 */
import { LightningElement } from 'lwc';
import getTemplateUsageRows from '@salesforce/apex/EvaluationCriteriaManagerReadController.getTemplateUsageRows';

const COLUMNS = [
    {
        label: 'Criterion Name',
        fieldName: 'criterionRecordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'criterionName' }, target: '_self' }
    },
    {
        label: 'Template Name',
        fieldName: 'templateRecordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'templateDisplayName' }, target: '_self' }
    },
    { label: 'Template Status', fieldName: 'templateStatus', type: 'text' },
    { label: 'Template Version', fieldName: 'templateVersion', type: 'text' },
    { label: 'Usage State', fieldName: 'usageState', type: 'text' },
    { label: 'Version Mismatch', fieldName: 'versionMismatchLabel', type: 'text' }
];

export default class TemplateUsageWorkspace extends LightningElement {
    searchText = '';
    selectedCriterionId = null;
    rows = [];
    columns = COLUMNS;
    isLoading = false;
    errorMessage = '';
    showMismatchOnly = false;
    criterionDisplayInfo = {
        primaryField: 'Label__c'
    };
    criterionMatchingInfo = {
        primaryField: { fieldPath: 'Label__c' }
    };

    connectedCallback() {
        this.loadRows();
    }

    async loadRows() {
        // Central fetch method keeps loading/error/empty states predictable.
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getTemplateUsageRows({
                searchText: this.searchText || null,
                criterionLibraryId: this.selectedCriterionId
            });
            this.rows = (data || []).map((row, index) => ({
                key: `${row.templateName}-${row.criterionName}-${index}`,
                ...row,
                versionMismatchLabel: row.versionMismatch ? 'Yes' : 'No',
                criterionRecordUrl: row.criterionId ? `/${row.criterionId}` : null,
                templateRecordUrl: row.templateId ? `/${row.templateId}` : null
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load template usage.';
            this.rows = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleCriterionSelect(event) {
        this.selectedCriterionId = event.detail.recordId || null;
    }

    handleClearCriterionFilter() {
        this.selectedCriterionId = null;
        // Re-rendering with a null value clears record picker selection.
    }

    handleRunSearch() {
        this.loadRows();
    }

    handleMismatchToggle(event) {
        this.showMismatchOnly = event.target.checked;
    }

    get displayedRows() {
        if (!this.showMismatchOnly) {
            return this.rows;
        }
        return this.rows.filter((row) => row.versionMismatch);
    }

    get hasRows() {
        return this.displayedRows.length > 0;
    }

    get rowCountLabel() {
        return `${this.displayedRows.length} usage row${this.displayedRows.length === 1 ? '' : 's'}`;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasRows;
    }
}
