import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = ['ApplicationForm.ApplicationStatus', 'ApplicationForm.Stage'];

export default class ApplicationStatusTracker extends LightningElement {
    @api applicationFormId;
    @api recordId;
    pageRecordId;
    urlRecordId;

    applicationRecord;
    error;

    get resolvedRecordId() {
        // Keep backward compatibility with flow-passed ids while preferring record page context.
        return this.recordId || this.applicationFormId || this.pageRecordId || this.urlRecordId;
    }

    connectedCallback() {
        // Experience URLs include the record Id in the path; use it as a final fallback.
        const match = window?.location?.pathname?.match(/\/applicationform\/([a-zA-Z0-9]{15,18})\//i);
        if (match && match[1]) {
            this.urlRecordId = match[1];
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) {
            return;
        }

        const candidate =
            pageRef?.state?.recordId ||
            pageRef?.state?.c__recordId ||
            pageRef?.attributes?.recordId;
        if (candidate) {
            this.pageRecordId = candidate;
        }
    }

    @wire(getRecord, { recordId: '$resolvedRecordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.applicationRecord = data;
            this.error = undefined;
            return;
        }
        if (error) {
            this.error = error;
            this.applicationRecord = undefined;
        }
    }

    get statusValue() {
        // Prefer applicant-facing ApplicationStatus when available; Stage is an org-level fallback.
        const applicationStatus = this.applicationRecord?.fields?.ApplicationStatus?.value;
        if (applicationStatus) {
            return applicationStatus;
        }
        return this.applicationRecord?.fields?.Stage?.value;
    }

    get hasStatusValue() {
        return !!this.statusValue;
    }

    get statusMessage() {
        const normalized = (this.statusValue || '').toLowerCase();
        if (!normalized) {
            return null;
        }
        if (normalized === 'submitted') {
            return 'Your application has been submitted successfully and is awaiting review.';
        }
        if (normalized === 'under review') {
            return 'Your application is currently being evaluated.';
        }
        if (normalized === 'approved') {
            return 'Your application has been approved.';
        }
        if (normalized === 'rejected') {
            return 'Your application was not selected for funding.';
        }
        return 'Your application status has been updated.';
    }
}