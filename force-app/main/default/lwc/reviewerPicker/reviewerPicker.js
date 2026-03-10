import { api, LightningElement, wire } from 'lwc';
import { getRecord, getRecords } from 'lightning/uiRecordApi';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import USER_NAME from '@salesforce/schema/User.Name';
import USER_EMAIL from '@salesforce/schema/User.Email';

const USER_FIELDS = [USER_NAME, USER_EMAIL];
const USER_FIELD_PATHS = ['User.Name', 'User.Email'];
const NAME_UNAVAILABLE_LABEL = 'Name unavailable';

export default class ReviewerPicker extends LightningElement {
    @api maxSelections = 10;
    @api reviewerIds = [];
    @api reviewerIdsCsv = '';

    pendingReviewerId;
    pendingReviewerLabel;
    selectedReviewers = [];
    reviewerRecordRequests = [];

    matchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Email' }]
    };

    displayInfo = {
        primaryField: 'Name',
        additionalFields: ['Email']
    };

    @wire(getRecord, { recordId: '$pendingReviewerId', fields: USER_FIELDS })
    wiredPendingReviewer({ data, error }) {
        if (!this.pendingReviewerId) {
            return;
        }

        if (data) {
            const name = data.fields?.Name?.value || NAME_UNAVAILABLE_LABEL;
            this.pendingReviewerLabel = name;
        } else if (error) {
            this.pendingReviewerLabel = NAME_UNAVAILABLE_LABEL;
        } else {
            return;
        }
        // Auto-add after label resolution so pills never render raw user Id values.
        this.tryAddPendingReviewer();
    }

    @wire(getRecords, { records: '$reviewerRecordRequests' })
    wiredSelectedReviewers({ data }) {
        if (!data?.results || !this.selectedReviewers.length) {
            return;
        }

        const labelById = new Map();
        data.results.forEach((entry) => {
            const record = entry?.result;
            const id = record?.id;
            if (!id) {
                return;
            }
            const name = record.fields?.Name?.value || NAME_UNAVAILABLE_LABEL;
            labelById.set(id, name);
        });

        if (!labelById.size) {
            return;
        }

        let changed = false;
        this.selectedReviewers = this.selectedReviewers.map((reviewer) => {
            const resolvedLabel = labelById.get(reviewer.id);
            if (resolvedLabel && reviewer.label !== resolvedLabel) {
                changed = true;
                return { ...reviewer, label: resolvedLabel };
            }
            return reviewer;
        });

        if (changed) {
            this.sortSelectedReviewers();
        }
    }

    connectedCallback() {
        if (!Array.isArray(this.reviewerIds)) {
            this.reviewerIds = [];
        }
        this.selectedReviewers = this.reviewerIds.map((id) => ({
            id,
            label: NAME_UNAVAILABLE_LABEL
        }));
        this.sortSelectedReviewers();
        this.refreshReviewerHydrationRequests();
        this.updateFlowOutputs();
    }

    get disableAdd() {
        return (
            !this.pendingReviewerId ||
            !this.pendingReviewerLabel ||
            this.selectedReviewers.some((r) => r.id === this.pendingReviewerId) ||
            this.selectedReviewers.length >= Number(this.maxSelections || 10)
        );
    }

    get isResolvingReviewer() {
        return !!this.pendingReviewerId && !this.pendingReviewerLabel;
    }

    get selectionCountText() {
        return `${this.selectedReviewers.length}/${this.maxSelections} selected`;
    }

    handleLookupChange(event) {
        this.pendingReviewerId = event.detail?.recordId;
        this.pendingReviewerLabel = null;
    }

    handleAddReviewer() {
        this.tryAddPendingReviewer();
    }

    handleRemoveReviewer(event) {
        const reviewerId = event.target.name;
        this.selectedReviewers = this.selectedReviewers.filter((r) => r.id !== reviewerId);
        this.refreshReviewerHydrationRequests();
        this.updateFlowOutputs();
    }

    updateFlowOutputs() {
        // Flow invocable action expects a semicolon-delimited String input for reviewer ids.
        const ids = this.selectedReviewers.map((r) => r.id);
        this.reviewerIds = ids;
        this.reviewerIdsCsv = ids.join(';');

        this.dispatchEvent(new FlowAttributeChangeEvent('reviewerIds', this.reviewerIds));
        this.dispatchEvent(new FlowAttributeChangeEvent('reviewerIdsCsv', this.reviewerIdsCsv));
    }

    tryAddPendingReviewer() {
        if (this.disableAdd) {
            return;
        }

        const label = this.pendingReviewerLabel || NAME_UNAVAILABLE_LABEL;
        this.selectedReviewers = [
            ...this.selectedReviewers,
            { id: this.pendingReviewerId, label }
        ];
        this.sortSelectedReviewers();
        this.refreshReviewerHydrationRequests();
        this.pendingReviewerId = null;
        this.pendingReviewerLabel = null;
        this.updateFlowOutputs();
    }

    refreshReviewerHydrationRequests() {
        // Batch hydrate names for preselected reviewers provided by flow input state.
        const uniqueIds = [...new Set(this.selectedReviewers.map((reviewer) => reviewer.id).filter(Boolean))];
        this.reviewerRecordRequests = uniqueIds.map((id) => ({
            recordIds: [id],
            fields: USER_FIELD_PATHS
        }));
    }

    sortSelectedReviewers() {
        this.selectedReviewers = [...this.selectedReviewers].sort((a, b) => {
            const aLabel = (a?.label || '').toLowerCase();
            const bLabel = (b?.label || '').toLowerCase();
            return aLabel.localeCompare(bLabel);
        });
    }

    @api
    validate() {
        const isValid = this.selectedReviewers.length > 0;
        return {
            isValid,
            errorMessage: isValid ? null : 'Select at least one reviewer.'
        };
    }
}
