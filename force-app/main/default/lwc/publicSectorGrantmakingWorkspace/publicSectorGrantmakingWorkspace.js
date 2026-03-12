import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspaceRows from '@salesforce/apex/PublicSectorGrantmakingReadController.getWorkspaceRows';

const COLUMNS = [
    {
        label: 'Record Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' },
        sortable: true
    },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true },
    { label: 'Primary Date', fieldName: 'primaryDate', type: 'text', sortable: true },
    { label: 'Secondary', fieldName: 'secondaryValue', type: 'text', sortable: true },
    { label: 'Detail', fieldName: 'detail', type: 'text' }
];

export default class PublicSectorGrantmakingWorkspace extends LightningElement {
    searchText = '';
    rows = [];
    columns = COLUMNS;
    isLoading = false;
    isRefreshing = false;
    errorMessage = '';
    helperNote = '';
    workspaceKey = 'fundingOpportunities';
    workspaceTitle = 'Funding Opportunities';
    objectApiName = 'FundingOpportunity';
    pageSize = 25;
    pageNumber = 1;
    totalCount = 0;
    hasMore = false;
    sortBy = 'recordName';
    sortDirection = 'desc';

    workspaceApiNameToKey = {
        PSG_Funding_Opportunities: 'fundingOpportunities',
        PSG_Application_Forms: 'applicationForms',
        PSG_Evaluations: 'evaluations',
        PSG_Evaluation_Templates: 'evaluationTemplates',
        PSG_Criteria_Library: 'criteriaLibrary'
    };

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const apiName = pageRef?.attributes?.apiName;
        const nextKey = this.workspaceApiNameToKey[apiName] || 'fundingOpportunities';
        if (nextKey !== this.workspaceKey) {
            this.workspaceKey = nextKey;
            this.pageNumber = 1;
            this.loadRows();
        }
    }

    connectedCallback() {
        this.loadRows();
    }

    get rowCountLabel() {
        return `${this.rows.length} shown / ${this.totalCount} total`;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.rows.length;
    }

    get pageLabel() {
        return `Page ${this.pageNumber}`;
    }

    get disablePrevious() {
        return this.isLoading || this.pageNumber <= 1;
    }

    get disableNext() {
        return this.isLoading || !this.hasMore;
    }

    async loadRows() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const response = await getWorkspaceRows({
                workspaceKey: this.workspaceKey,
                searchText: this.searchText || null,
                pageSize: this.pageSize,
                pageNumber: this.pageNumber,
                sortBy: this.sortBy,
                sortDirection: this.sortDirection
            });
            this.rows = response?.rows || [];
            this.workspaceTitle = response?.title || 'Workspace';
            this.objectApiName = response?.objectApiName || '--';
            this.pageSize = response?.pageSize || this.pageSize;
            this.pageNumber = response?.pageNumber || this.pageNumber;
            this.totalCount = response?.totalCount || 0;
            this.hasMore = Boolean(response?.hasMore);
            this.helperNote = response?.helperNote || '';
        } catch (error) {
            this.rows = [];
            this.totalCount = 0;
            this.hasMore = false;
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load workspace data.';
        } finally {
            this.isLoading = false;
        }
    }

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleRunSearch() {
        this.pageNumber = 1;
        this.loadRows();
    }

    async handleRefresh() {
        this.isRefreshing = true;
        await this.loadRows();
        if (this.errorMessage) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refresh Failed',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refreshed',
                    message: `${this.workspaceTitle} values were refreshed.`,
                    variant: 'success'
                })
            );
        }
        this.isRefreshing = false;
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.pageNumber = 1;
        this.loadRows();
    }

    handlePreviousPage() {
        if (this.pageNumber <= 1 || this.isLoading) {
            return;
        }
        this.pageNumber -= 1;
        this.loadRows();
    }

    handleNextPage() {
        if (!this.hasMore || this.isLoading) {
            return;
        }
        this.pageNumber += 1;
        this.loadRows();
    }
}