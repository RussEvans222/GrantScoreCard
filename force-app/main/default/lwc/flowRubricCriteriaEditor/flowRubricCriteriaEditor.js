import { api, LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import scorecardFullscreenModal from '@salesforce/resourceUrl/scorecardFullscreenModal';

export default class FlowRubricCriteriaEditor extends LightningElement {
    @api criteriaJsonIn;
    @api criteriaJsonOut;
    @api isValid = false;
    @api validationMessage = '';
    @api totalWeight = '0';
    @api isWeightTotalValid = false;

    rows = [];
    hasLoadedFullscreenModalStyle = false;

    isModalOpen = false;
    isEditing = false;
    editingRowId;
    draftRow = this.createDraftRow();

    connectedCallback() {
        document.body.classList.add('gs-fullscreen-modal-open');
        this.parseInput();
    }

    disconnectedCallback() {
        document.body.classList.remove('gs-fullscreen-modal-open');
    }

    renderedCallback() {
        if (this.hasLoadedFullscreenModalStyle) {
            return;
        }
        this.hasLoadedFullscreenModalStyle = true;
        // Reuse shared static-resource CSS so setup matrix can render in full-width modal space.
        loadStyle(this, scorecardFullscreenModal).catch(() => {});
    }

    parseInput() {
        let parsed = [];
        if (this.criteriaJsonIn) {
            try {
                parsed = JSON.parse(this.criteriaJsonIn);
            } catch (e) {
                parsed = [];
            }
        }

        this.rows = (Array.isArray(parsed) ? parsed : []).map((row, index) => ({
            localId: row.localId || `row-${index + 1}`,
            Evaluation_Template__c: row.Evaluation_Template__c || null,
            SourceLibraryCriterion__c: row.SourceLibraryCriterion__c || null,
            IsCustom__c: row.IsCustom__c || false,
            isCustom: row.IsCustom__c === true || !row.SourceLibraryCriterion__c,
            Section_Name__c: row.Section_Name__c || 'General',
            Section_Order__c: row.Section_Order__c ?? null,
            Section_Key__c: row.Section_Key__c || '',
            Label__c: row.Label__c || '',
            Description__c: row.Description__c || '',
            Weight__c: row.Weight__c ?? null,
            Required__c: row.Required__c || false,
            Display_Order__c: row.Display_Order__c ?? null,
            Criterion_Key__c: row.Criterion_Key__c || ''
        }));

        this.publishState();
    }

    createDraftRow(seed = {}) {
        return {
            localId: seed.localId,
            Label__c: seed.Label__c || '',
            Description__c: seed.Description__c || '',
            Section_Name__c: seed.Section_Name__c || 'General',
            Weight__c: seed.Weight__c ?? null,
            Display_Order__c: seed.Display_Order__c ?? null,
            IsCustom__c: seed.IsCustom__c || false,
            isCustom: seed.isCustom !== false,
            bundleSearchTerm: seed.Section_Name__c || 'General',
            showBundleDropdown: false
        };
    }

    get progressValue() {
        const total = Number(this.totalWeight);
        if (Number.isNaN(total) || total <= 0) {
            return 0;
        }
        return Math.min(100, Math.round(total));
    }

    get progressLabel() {
        return `Total Weight: ${this.totalWeight} / 100`;
    }

    get weightStateClass() {
        return this.isWeightTotalValid ? 'weight-state good' : 'weight-state warn';
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get modalTitle() {
        return this.isEditing ? 'Edit Criterion' : 'Add Criterion';
    }

    get sortedRows() {
        return [...this.rows].sort((a, b) => {
            const aOrder = a.Display_Order__c === null || a.Display_Order__c === undefined || a.Display_Order__c === ''
                ? Number.MAX_SAFE_INTEGER
                : Number(a.Display_Order__c);
            const bOrder = b.Display_Order__c === null || b.Display_Order__c === undefined || b.Display_Order__c === ''
                ? Number.MAX_SAFE_INTEGER
                : Number(b.Display_Order__c);
            if (aOrder !== bOrder) {
                return aOrder - bOrder;
            }
            return (a.Label__c || '').localeCompare(b.Label__c || '');
        }).map((row) => ({
            ...row,
            descriptionText: row.Description__c || 'No description provided.',
            bundleText: row.Section_Name__c || 'General',
            weightText: row.Weight__c === null || row.Weight__c === undefined || row.Weight__c === '' ? '--' : `${row.Weight__c}%`,
            rowTypeLabel: row.isCustom ? 'Custom' : 'Library'
        }));
    }

    get allBundleNames() {
        return Array.from(new Set(
            this.rows
                .map((row) => (row.Section_Name__c || '').trim())
                .filter((name) => !!name)
        )).sort((a, b) => a.localeCompare(b));
    }

    get bundleSuggestions() {
        const query = (this.draftRow.bundleSearchTerm || '').trim().toLowerCase();
        return this.allBundleNames
            .filter((name) => !query || name.toLowerCase().includes(query))
            .slice(0, 8)
            .map((name, index) => ({
                key: `draft-bundle-${index + 1}`,
                value: name
            }));
    }

    get showCreateBundleOption() {
        const query = (this.draftRow.bundleSearchTerm || '').trim();
        if (!query) {
            return false;
        }
        return !this.allBundleNames.some((name) => name.toLowerCase() === query.toLowerCase());
    }

    get isDraftLibraryRow() {
        return this.isEditing && !this.draftRow.isCustom;
    }

    openAddModal() {
        this.isEditing = false;
        this.editingRowId = null;
        this.draftRow = this.createDraftRow({
            localId: `custom-${Date.now()}`,
            IsCustom__c: true,
            isCustom: true,
            Section_Name__c: 'General'
        });
        this.isModalOpen = true;
    }

    openEditModal(event) {
        const rowId = event.currentTarget?.dataset?.id;
        const row = this.rows.find((item) => item.localId === rowId);
        if (!row) {
            return;
        }

        this.isEditing = true;
        this.editingRowId = row.localId;
        this.draftRow = this.createDraftRow(row);
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
        this.editingRowId = null;
        this.isEditing = false;
        this.draftRow = this.createDraftRow();
    }

    handleDeleteRow(event) {
        const rowId = event.currentTarget?.dataset?.id;
        if (!rowId) {
            return;
        }
        this.rows = this.rows.filter((row) => row.localId !== rowId);
        this.publishState();
    }

    handleDraftFieldChange(event) {
        const field = event.target.dataset.field;
        if (!field) {
            return;
        }

        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.draftRow = {
            ...this.draftRow,
            [field]: value
        };

        if (field === 'Section_Name__c') {
            this.draftRow = {
                ...this.draftRow,
                bundleSearchTerm: value,
                showBundleDropdown: true
            };
        }
    }

    handleBundleFocus() {
        this.draftRow = {
            ...this.draftRow,
            showBundleDropdown: true
        };
    }

    handleBundleBlur() {
        window.clearTimeout(this.bundleBlurTimeout);
        this.bundleBlurTimeout = window.setTimeout(() => {
            this.draftRow = {
                ...this.draftRow,
                showBundleDropdown: false
            };
        }, 180);
    }

    handleBundleOptionSelect(event) {
        const selectedBundle = event.currentTarget.dataset.value;
        window.clearTimeout(this.bundleBlurTimeout);
        this.draftRow = {
            ...this.draftRow,
            Section_Name__c: selectedBundle,
            bundleSearchTerm: selectedBundle,
            showBundleDropdown: false
        };
    }

    handleSaveDraft() {
        const draft = {
            ...this.draftRow,
            Section_Name__c: (this.draftRow.Section_Name__c || this.draftRow.bundleSearchTerm || 'General').trim() || 'General'
        };

        if (this.isEditing && this.editingRowId) {
            this.rows = this.rows.map((row) => {
                if (row.localId !== this.editingRowId) {
                    return row;
                }

                const isLibrary = !row.isCustom;
                // Preserve existing behavior: library rows keep label/description/bundle locked.
                return {
                    ...row,
                    Label__c: isLibrary ? row.Label__c : draft.Label__c,
                    Description__c: isLibrary ? row.Description__c : draft.Description__c,
                    Section_Name__c: isLibrary ? row.Section_Name__c : draft.Section_Name__c,
                    Weight__c: draft.Weight__c,
                    Display_Order__c: draft.Display_Order__c
                };
            });
        } else {
            this.rows = [
                ...this.rows,
                {
                    localId: draft.localId || `custom-${Date.now()}`,
                    Evaluation_Template__c: null,
                    SourceLibraryCriterion__c: null,
                    IsCustom__c: true,
                    isCustom: true,
                    Section_Name__c: draft.Section_Name__c,
                    Section_Order__c: null,
                    Section_Key__c: '',
                    Label__c: draft.Label__c,
                    Description__c: draft.Description__c,
                    Weight__c: draft.Weight__c,
                    Required__c: false,
                    Display_Order__c: draft.Display_Order__c,
                    Criterion_Key__c: ''
                }
            ];
        }

        this.closeModal();
        this.publishState();
    }

    publishState() {
        const errors = [];
        let runningWeight = 0;
        this.rows.forEach((row, idx) => {
            const weight = row.Weight__c;
            const order = row.Display_Order__c;
            if (weight !== null && weight !== '' && Number.isNaN(Number(weight))) {
                errors.push(`Row ${idx + 1}: Weight must be numeric.`);
            }
            if (weight !== null && weight !== '' && !Number.isNaN(Number(weight))) {
                runningWeight += Number(weight);
            }
            if (order !== null && order !== '' && Number.isNaN(Number(order))) {
                errors.push(`Row ${idx + 1}: Display Order must be numeric.`);
            }
        });

        const rounded = Number(runningWeight.toFixed(2));
        this.totalWeight = String(rounded);
        this.isWeightTotalValid = rounded === 100;

        this.isValid = errors.length === 0;
        const validationMessages = [...errors];
        if (!this.isWeightTotalValid) {
            // Activation remains gated by total weight = 100, but editing is still allowed in draft state.
            validationMessages.push('Total weight must equal 100 to activate.');
        }
        this.validationMessage = validationMessages.join(' ');

        const payload = this.rows.map((row) => ({
            Evaluation_Template__c: row.Evaluation_Template__c,
            SourceLibraryCriterion__c: row.SourceLibraryCriterion__c,
            IsCustom__c: row.isCustom,
            Section_Name__c: row.Section_Name__c,
            Section_Order__c: row.Section_Order__c === '' ? null : row.Section_Order__c,
            Section_Key__c: row.Section_Key__c,
            Label__c: row.Label__c,
            Description__c: row.Description__c,
            Weight__c: row.Weight__c === '' ? null : row.Weight__c,
            Required__c: row.Required__c,
            Display_Order__c: row.Display_Order__c === '' ? null : row.Display_Order__c,
            Criterion_Key__c: row.Criterion_Key__c
        }));

        this.criteriaJsonOut = JSON.stringify(payload);
    }
}
