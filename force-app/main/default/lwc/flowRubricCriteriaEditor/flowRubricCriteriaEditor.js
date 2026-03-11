import { api, LightningElement } from 'lwc';

export default class FlowRubricCriteriaEditor extends LightningElement {
    @api criteriaJsonIn;
    @api criteriaJsonOut;
    @api isValid = false;
    @api validationMessage = '';
    @api totalWeight = '0';
    @api isWeightTotalValid = false;

    rows = [];

    connectedCallback() {
        this.parseInput();
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
            rowTypeLabel: row.IsCustom__c === true || !row.SourceLibraryCriterion__c ? 'Custom' : 'Library',
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

    handleAddRow() {
        this.rows = [
            ...this.rows,
            {
                localId: `custom-${Date.now()}`,
                Evaluation_Template__c: null,
                SourceLibraryCriterion__c: null,
                IsCustom__c: true,
                isCustom: true,
                rowTypeLabel: 'Custom',
                Section_Name__c: 'General',
                Section_Order__c: null,
                Section_Key__c: '',
                Label__c: '',
                Description__c: '',
                Weight__c: null,
                Required__c: false,
                Display_Order__c: null,
                Criterion_Key__c: ''
            }
        ];
        this.publishState();
    }

    handleRemoveRow(event) {
        const rowId = event.currentTarget?.dataset?.id;
        if (!rowId) {
            return;
        }
        this.rows = this.rows.filter((row) => row.localId !== rowId);
        this.publishState();
    }

    handleFieldChange(event) {
        const { id, field } = event.target.dataset;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.rows = this.rows.map((row) => {
            if (row.localId !== id) {
                return row;
            }
            return { ...row, [field]: value };
        });
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

        const payload = this.rows.map(({ localId, ...rest }) => ({
            ...rest,
            // Preserve existing flow/Apex contracts and field names expected by the save action.
            IsCustom__c: rest.isCustom,
            Weight__c: rest.Weight__c === '' ? null : rest.Weight__c,
            Section_Order__c: rest.Section_Order__c === '' ? null : rest.Section_Order__c,
            Display_Order__c: rest.Display_Order__c === '' ? null : rest.Display_Order__c
        }));

        this.criteriaJsonOut = JSON.stringify(payload);
    }
}
