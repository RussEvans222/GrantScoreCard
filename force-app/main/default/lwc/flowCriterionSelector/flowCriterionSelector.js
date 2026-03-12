import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { loadStyle } from 'lightning/platformResourceLoader';
import getActiveCriteria from '@salesforce/apex/CriterionLibrarySelectorController.getActiveCriteria';
import scorecardFullscreenModal from '@salesforce/resourceUrl/scorecardFullscreenModal';

export default class FlowCriterionSelector extends LightningElement {
    @api selectedCriterionIdsCsv;

    rows = [];
    removedRowIdStack = [];
    loading = true;
    error;
    hasLoadedFullscreenModalStyle = false;

    connectedCallback() {
        document.body.classList.add('gs-fullscreen-modal-open');
        this.loadData();
    }

    disconnectedCallback() {
        document.body.classList.remove('gs-fullscreen-modal-open');
    }

    renderedCallback() {
        if (this.hasLoadedFullscreenModalStyle) {
            return;
        }
        this.hasLoadedFullscreenModalStyle = true;
        // Reuse the same scoped fullscreen modal style used by the scorecard action.
        loadStyle(this, scorecardFullscreenModal).catch(() => {});
    }

    async loadData() {
        this.loading = true;
        this.error = undefined;
        try {
            const preselected = new Set((this.selectedCriterionIdsCsv || '')
                .split(';')
                .map((v) => v.trim())
                .filter((v) => !!v));
            const data = await getActiveCriteria();
            this.rows = (data || []).map((row) => ({
                ...row,
                selected: preselected.has(row.id),
                removed: false
            }));
            this.removedRowIdStack = [];
            this.publish();
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load criteria.';
        } finally {
            this.loading = false;
        }
    }

    handleToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.rows = this.rows.map((row) => (
            row.id === id ? { ...row, selected: checked } : row
        ));
        this.publish();
    }

    handleRemove(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) {
            return;
        }

        // Remove from current matrix view/selection only; underlying library metadata is unchanged.
        this.rows = this.rows.map((row) => (
            row.id === id
                ? { ...row, removed: true, selected: false }
                : row
        ));
        this.removedRowIdStack = [...this.removedRowIdStack, id];
        this.publish();
    }

    handleUndoRemove() {
        if (!this.removedRowIdStack.length) {
            return;
        }
        const rowId = this.removedRowIdStack[this.removedRowIdStack.length - 1];
        this.rows = this.rows.map((row) => (
            row.id === rowId
                ? { ...row, removed: false, selected: true }
                : row
        ));
        this.removedRowIdStack = this.removedRowIdStack.slice(0, -1);
        this.publish();
    }

    get selectedCount() {
        return this.rows.filter((row) => row.selected).length;
    }

    get showRecommendedIndicator() {
        return this.selectedCount >= 4 && this.selectedCount <= 6;
    }

    get showSelectionWarning() {
        return this.selectedCount > 6;
    }

    get groupedRows() {
        const byBundle = new Map();
        this.rows.filter((row) => !row.removed).forEach((row) => {
            // "Bundle" is a UX label; it maps to section name data from the library.
            const bundleName = row.sectionName || 'General';
            if (!byBundle.has(bundleName)) {
                byBundle.set(bundleName, []);
            }
            byBundle.get(bundleName).push(row);
        });
        return Array.from(byBundle.entries()).map(([bundleName, items]) => ({
            bundleName,
            items
        }));
    }

    get hasRemovedRows() {
        return this.removedRowIdStack.length > 0;
    }

    get removedCount() {
        return this.removedRowIdStack.length;
    }

    publish() {
        const selectedIds = this.rows
            .filter((row) => row.selected && !row.removed)
            .map((row) => row.id);
        this.selectedCriterionIdsCsv = selectedIds.join(';');
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedCriterionIdsCsv', this.selectedCriterionIdsCsv));
    }
}