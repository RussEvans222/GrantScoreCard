import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHomeDashboardData from '@salesforce/apex/PublicSectorGrantmakingReadController.getHomeDashboardData';

export default class PublicSectorGrantmakingHome extends NavigationMixin(LightningElement) {
    data;
    wiredResult;
    isRefreshing = false;

    @wire(getHomeDashboardData)
    wiredHome(result) {
        this.wiredResult = result;
        const { data } = result;
        if (data) {
            this.data = data;
        }
    }

    get metricCards() {
        return [
            { label: 'Active Funding Opportunities', value: this.toDisplay(this.data?.activeFundingOpportunities) },
            { label: 'Open Application Forms', value: this.toDisplay(this.data?.openApplicationForms) },
            { label: 'In Review Evaluations', value: this.toDisplay(this.data?.inReviewEvaluations) },
            { label: 'Published Templates', value: this.toDisplay(this.data?.publishedTemplates) },
            { label: 'Active Criteria', value: this.toDisplay(this.data?.activeCriteria) }
        ];
    }

    get hasTableauUrl() {
        return Boolean(this.data?.tableauEmbedUrl);
    }

    get recentApplicationForms() {
        return this.data?.recentApplicationForms || [];
    }

    get recentEvaluations() {
        return this.data?.recentEvaluations || [];
    }

    handleOpenTab(event) {
        const apiName = event.currentTarget.dataset.api;
        if (!apiName) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName }
        });
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;
        if (!recordId || !objectApiName) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    async handleRefresh() {
        if (!this.wiredResult) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refreshed',
                    message: 'Public Sector Grantmaking home data was refreshed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refresh Failed',
                    message: error?.body?.message || error?.message || 'Unable to refresh home data.',
                    variant: 'error'
                })
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    toDisplay(value) {
        return value === null || value === undefined ? '--' : value;
    }
}