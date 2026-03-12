/**
 * Evaluation Criteria Manager Home
 *
 * Why this component exists:
 * - Gives admins a simple dashboard view of criteria health and usage.
 * - Shows quick actions that map to future workflows.
 *
 * Data flow:
 * Apex (wire) -> this.data -> computed getters -> card UI.
 */
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHomeDashboardData from '@salesforce/apex/EvaluationCriteriaManagerReadController.getHomeDashboardData';

export default class EvaluationCriteriaManagerHome extends NavigationMixin(LightningElement) {
    data;
    isRefreshing = false;
    wiredDashboardResult;

    @wire(getHomeDashboardData)
    wiredDashboard(wiredResult) {
        this.wiredDashboardResult = wiredResult;
        const { data } = wiredResult;
        // Wire adapter automatically refreshes when LDS/Apex cache updates.
        if (data) {
            this.data = data;
        }
    }

    get metricCards() {
        const metrics = this.data?.metrics || {};
        return [
            { label: 'Total Active Criteria', value: this.toDisplay(metrics.activeCriteria) },
            { label: 'Criteria In Use', value: this.toDisplay(metrics.templatesUsingCriteria) },
            { label: 'Templates Using Criteria', value: this.toDisplay(metrics.totalTemplates) },
            { label: 'Criteria Needing Review', value: this.toDisplay(metrics.criteriaNeedingReview) }
        ];
    }

    handleActionClick(event) {
        // Quick actions route admins into purpose-built manager workspaces.
        const action = event.currentTarget.dataset.action;
        if (action === 'new') {
            this.navigateToTab('Criteria_Library');
            return;
        }
        if (action === 'template') {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Evaluation_Template__c',
                    actionName: 'new'
                }
            });
            return;
        }
        if (action === 'insights' || action === 'generate') {
            this.navigateToTab('Criteria_Insights');
            return;
        }
    }

    toDisplay(value) {
        return value === null || value === undefined ? '--' : value;
    }

    handleCriterionRowClick(event) {
        const recordId = event.currentTarget.dataset.id;
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

    handleOpenInsights() {
        this.navigateToTab('Criteria_Insights');
    }

    navigateToTab(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName }
        });
    }

    async handleRefresh() {
        if (!this.wiredDashboardResult) {
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredDashboardResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refreshed',
                    message: 'Home metrics and lists were refreshed.',
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
}