/**
 * Criteria Library Workspace
 *
 * Purpose:
 * - Admin-facing management UI for criterion records and bundle assignment.
 * - Also re-used in "Evaluation Templates" tab mode.
 *
 * Data flow:
 * User filters/actions -> Apex methods -> rows in component state -> rendered matrix.
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCriteriaLibraryData from '@salesforce/apex/EvaluationCriteriaManagerReadController.getCriteriaLibraryData';
import getEvaluationTemplateRows from '@salesforce/apex/EvaluationCriteriaManagerReadController.getEvaluationTemplateRows';
import saveTemplateDisplayNames from '@salesforce/apex/EvaluationCriteriaManagerReadController.saveTemplateDisplayNames';
import getBundleOptions from '@salesforce/apex/EvaluationCriteriaManagerReadController.getBundleOptions';
import createBundle from '@salesforce/apex/EvaluationCriteriaManagerReadController.createBundle';
import assignCriterionToBundle from '@salesforce/apex/EvaluationCriteriaManagerReadController.assignCriterionToBundle';
import deleteCriterion from '@salesforce/apex/EvaluationCriteriaManagerReadController.deleteCriterion';

const CRITERIA_COLUMNS = [
    {
        type: 'button-icon',
        initialWidth: 42,
        typeAttributes: {
            iconName: 'utility:delete',
            name: 'delete',
            title: 'Delete criterion',
            alternativeText: 'Delete criterion',
            variant: 'bare',
            class: 'slds-icon-text-error'
        }
    },
    { label: 'Criterion Name', fieldName: 'name', type: 'text' },
    { label: 'Bundle', fieldName: 'bundleName', type: 'text' },
    { label: 'Category', fieldName: 'category', type: 'text' },
    { label: 'Default Weight', fieldName: 'defaultWeight', type: 'number' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Templates Using', fieldName: 'templatesUsing', type: 'number' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View', name: 'view' },
                { label: 'Edit', name: 'edit' }
            ]
        }
    }
];

const TEMPLATE_COLUMNS = [
    { label: 'Template Name', fieldName: 'displayName', type: 'text', editable: true },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Version', fieldName: 'version', type: 'text' },
    { label: 'Criteria Count', fieldName: 'criteriaCount', type: 'number' },
    { label: 'Last Updated', fieldName: 'lastUpdated', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'View', name: 'view' }]
        }
    }
];

export default class CriteriaLibraryWorkspace extends NavigationMixin(LightningElement) {
    searchText = '';
    categoryFilter = 'All';
    activeFilter = 'All';
    versionFilter = 'All';
    showFlatList = false;

    criteriaRows = [];
    templateRows = [];
    helperNote = '';
    isTemplateMode = false;
    templateDraftValues = [];
    templateDisplayFieldApiName = null;
    templateDisplayNameEditable = false;

    selectedCriterionId;
    selectedCriterionName;
    selectedBundleId = '';
    newBundleLabel = '';
    quickBundleLabel = '';
    bundleOptions = [];
    isRefreshing = false;

    showDeleteConfirm = false;
    deleteTargetId;
    deleteTargetName;

    criteriaColumns = CRITERIA_COLUMNS;
    templateColumns = TEMPLATE_COLUMNS;

    categoryOptions = [{ label: 'All', value: 'All' }];

    activeOptions = [
        { label: 'All', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    versionOptions = [{ label: 'All', value: 'All' }];

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        // We reuse this same LWC for two tabs.
        // The tab API name tells us which dataset and labels to show.
        const apiName = pageRef?.attributes?.apiName || '';
        const nextMode = apiName === 'Evaluation_Templates';
        if (this.isTemplateMode !== nextMode) {
            this.isTemplateMode = nextMode;
            this.refreshRows();
        }
    }

    connectedCallback() {
        this.refreshRows();
        this.loadBundleOptions();
    }

    get workspaceTitle() {
        return this.isTemplateMode ? 'Evaluation Templates' : 'Criteria Library';
    }

    get workspaceIcon() {
        return this.isTemplateMode ? 'utility:table' : 'utility:thunder';
    }

    get templateColumnsResolved() {
        return TEMPLATE_COLUMNS.map((column) => {
            if (column.fieldName !== 'displayName') {
                return column;
            }
            return {
                ...column,
                editable: this.templateDisplayNameEditable
            };
        });
    }

    get templateEditHelpText() {
        if (!this.templateDisplayFieldApiName) {
            return 'No editable display name field is configured on Evaluation_Template__c. Add one of: Display_Name__c, Template_Display_Name__c, User_Facing_Name__c, Label__c.';
        }
        if (!this.templateDisplayNameEditable) {
            return `Display field (${this.templateDisplayFieldApiName}) exists but is read-only for your current permissions.`;
        }
        return `Inline edit enabled. Saving updates field ${this.templateDisplayFieldApiName}.`;
    }

    get hasSelection() {
        return Boolean(this.selectedCriterionId);
    }

    get criteriaCountLabel() {
        return `${this.criteriaRows.length} criteria`;
    }

    get bundleGroups() {
        const byBundle = new Map();
        (this.criteriaRows || []).forEach((row) => {
            const key = row.bundleName && row.bundleName !== '--' ? row.bundleName : 'Unassigned';
            if (!byBundle.has(key)) {
                byBundle.set(key, []);
            }
            byBundle.get(key).push(row);
        });

        return Array.from(byBundle.keys())
            .sort((a, b) => a.localeCompare(b))
            .map((bundleName) => ({
                key: bundleName,
                bundleName,
                count: byBundle.get(bundleName).length,
                rows: byBundle.get(bundleName)
            }));
    }

    get bundleOptionsWithNone() {
        return [{ label: '-- No Bundle --', value: '' }, ...this.bundleOptions];
    }

    get totalBundleCount() {
        const bundleNames = new Set(
            (this.criteriaRows || [])
                .map((row) => row.bundleName)
                .filter((name) => name && name !== '--')
        );
        return bundleNames.size;
    }

    get unassignedCount() {
        return (this.criteriaRows || []).filter((row) => !row.bundleName || row.bundleName === '--').length;
    }

    async loadBundleOptions() {
        try {
            const rows = await getBundleOptions();
            this.bundleOptions = (rows || []).map((row) => ({ label: row.label, value: row.id }));
        } catch (error) {
            this.showError('Failed to load bundle options.', error);
        }
    }

    async refreshRows() {
        try {
            if (this.isTemplateMode) {
                // Template mode loads evaluation templates.
                const data = await getEvaluationTemplateRows({ searchText: this.searchText || null });
                this.templateRows = data || [];
                this.templateDraftValues = [];
                this.templateDisplayFieldApiName = this.templateRows.length ? this.templateRows[0].displayLabelFieldApiName : null;
                this.templateDisplayNameEditable = this.templateRows.length ? this.templateRows[0].displayNameEditable === true : false;
                this.helperNote = 'Template rows are loaded from Evaluation_Template__c using read-only queries.';
                return;
            }

            // Library mode loads criterion records with filters.
            const response = await getCriteriaLibraryData({
                searchText: this.searchText || null,
                categoryFilter: this.categoryFilter,
                activeFilter: this.activeFilter,
                versionFilter: this.versionFilter
            });
            this.criteriaRows = response?.rows || [];
            this.syncDynamicFilterOptions();
            this.helperNote = response?.helperNote || '';
        } catch (error) {
            this.showError('Failed to load criteria library data.', error);
        }
    }

    syncDynamicFilterOptions() {
        const categories = new Set();
        const versions = new Set();
        (this.criteriaRows || []).forEach((row) => {
            if (row?.category && row.category !== '--') {
                categories.add(row.category);
            }
            if (row?.version && row.version !== '--') {
                versions.add(row.version);
            }
        });

        this.categoryOptions = [{ label: 'All', value: 'All' }, ...Array.from(categories).sort().map((v) => ({ label: v, value: v }))];
        this.versionOptions = [{ label: 'All', value: 'All' }, ...Array.from(versions).sort().map((v) => ({ label: v, value: v }))];
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
        this.refreshRows();
    }

    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
        this.refreshRows();
    }

    handleActiveChange(event) {
        this.activeFilter = event.detail.value;
        this.refreshRows();
    }

    handleVersionChange(event) {
        this.versionFilter = event.detail.value;
        this.refreshRows();
    }

    handleToggleFlatList(event) {
        this.showFlatList = event.target.checked;
    }

    handleCriterionSelection(event) {
        const row = event.currentTarget.dataset ? {
            id: event.currentTarget.dataset.id,
            name: event.currentTarget.dataset.name,
            bundleid: event.currentTarget.dataset.bundleid
        } : null;
        if (!row || !row.id) {
            this.selectedCriterionId = null;
            this.selectedCriterionName = null;
            this.selectedBundleId = '';
            return;
        }
        this.selectedCriterionId = row.id;
        this.selectedCriterionName = row.name;
        this.selectedBundleId = row.bundleid || '';
    }

    handleOpenCriterionRecord(event) {
        const recordId = event.currentTarget?.dataset?.id;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Criterion_Library__c',
                actionName: 'view'
            }
        });
    }

    async handleCriteriaRowAction(event) {
        const actionName = event.currentTarget.dataset.action;
        const row = {
            id: event.currentTarget.dataset.id,
            name: event.currentTarget.dataset.name,
            bundleId: event.currentTarget.dataset.bundleid
        };
        this.handleCriteriaAction(actionName, row);
    }

    handleCriteriaDatatableRowAction(event) {
        const actionName = event.detail?.action?.name;
        const row = event.detail?.row;
        this.handleCriteriaAction(actionName, row);
    }

    handleCriteriaAction(actionName, row) {
        if (!actionName || !row?.id) {
            return;
        }
        if (actionName === 'delete') {
            this.deleteTargetId = row.id;
            this.deleteTargetName = row.name;
            this.showDeleteConfirm = true;
            return;
        }

        this.selectedCriterionId = row.id;
        this.selectedCriterionName = row.name;
        this.selectedBundleId = row.bundleId || '';

        if (actionName === 'view') {
            return;
        }

        if (actionName === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.id,
                    objectApiName: 'Criterion_Library__c',
                    actionName: 'edit'
                }
            });
        }
    }

    async handleAssignBundle() {
        // Bundle assignment updates one criterion at a time for clarity and auditability.
        if (!this.selectedCriterionId) {
            return;
        }
        try {
            await assignCriterionToBundle({
                criterionId: this.selectedCriterionId,
                bundleId: this.selectedBundleId || null
            });
            this.showSuccess('Bundle updated', 'Criterion bundle assignment saved.');
            await this.refreshRows();
        } catch (error) {
            this.showError('Failed to assign bundle.', error);
        }
    }

    handleBundleSelectionChange(event) {
        this.selectedBundleId = event.detail.value;
    }

    handleNewBundleLabelChange(event) {
        this.newBundleLabel = event.detail.value;
    }

    handleQuickBundleLabelChange(event) {
        this.quickBundleLabel = event.detail.value;
    }

    async handleCreateBundleFromMain() {
        if (!this.quickBundleLabel || !this.quickBundleLabel.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Bundle name required',
                    message: 'Enter a bundle name before creating.',
                    variant: 'warning'
                })
            );
            return;
        }
        try {
            const newBundleId = await createBundle({ bundleLabel: this.quickBundleLabel.trim() });
            this.quickBundleLabel = '';
            await this.loadBundleOptions();
            this.selectedBundleId = newBundleId;
            this.showSuccess('Bundle ready', 'Bundle created (or existing bundle found) and added to bundle options.');
        } catch (error) {
            this.showError('Failed to create bundle.', error);
        }
    }

    async handleCreateBundleAndAssign() {
        // This helper workflow creates a bundle first, then assigns selected criterion.
        if (!this.selectedCriterionId) {
            return;
        }
        if (!this.newBundleLabel || !this.newBundleLabel.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Bundle name required',
                    message: 'Enter a bundle name before creating.',
                    variant: 'warning'
                })
            );
            return;
        }

        try {
            const newBundleId = await createBundle({ bundleLabel: this.newBundleLabel.trim() });
            this.newBundleLabel = '';
            await this.loadBundleOptions();
            this.selectedBundleId = newBundleId;
            await assignCriterionToBundle({
                criterionId: this.selectedCriterionId,
                bundleId: newBundleId
            });
            this.showSuccess('Bundle created', 'New bundle created and assigned to criterion.');
            await this.refreshRows();
        } catch (error) {
            this.showError('Failed to create or assign bundle.', error);
        }
    }

    handleCloseDeleteModal() {
        this.showDeleteConfirm = false;
        this.deleteTargetId = null;
        this.deleteTargetName = null;
    }

    async handleConfirmDelete() {
        if (!this.deleteTargetId) {
            return;
        }
        try {
            await deleteCriterion({ criterionId: this.deleteTargetId });
            this.showSuccess('Criterion deleted', `${this.deleteTargetName} was removed from the library.`);
            if (this.selectedCriterionId === this.deleteTargetId) {
                this.selectedCriterionId = null;
                this.selectedCriterionName = null;
                this.selectedBundleId = '';
            }
            this.handleCloseDeleteModal();
            await this.refreshRows();
        } catch (error) {
            this.showError('Delete failed', error);
        }
    }

    handleTemplateRowAction(event) {
        const row = event.detail.row;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: 'Evaluation_Template__c',
                actionName: 'view'
            }
        });
    }

    async handleTemplateInlineSave(event) {
        const draftValues = event.detail.draftValues || [];
        if (!draftValues.length) {
            return;
        }
        try {
            const payload = draftValues
                .filter((row) => row.id)
                .map((row) => ({
                    templateId: row.id,
                    displayName: row.displayName
                }));

            const response = await saveTemplateDisplayNames({ updates: payload });
            if (!response?.success) {
                this.showError('Template name update failed', { message: response?.message || 'Unknown error' });
                return;
            }

            this.templateDraftValues = [];
            this.showSuccess('Template names updated', response.message || 'Display names saved.');
            await this.refreshRows();
        } catch (error) {
            this.showError('Template name update failed', error);
        }
    }

    showSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'success' }));
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unexpected error';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await Promise.all([this.refreshRows(), this.loadBundleOptions()]);
            this.showSuccess('Refreshed', `${this.workspaceTitle} data was refreshed.`);
        } catch (error) {
            this.showError('Refresh Failed', error);
        } finally {
            this.isRefreshing = false;
        }
    }
}