public with sharing class EvaluationTemplateWizardSaveAction {
    // Activation is allowed only at exactly 100 total weight to preserve runtime scoring assumptions.
    private static final Decimal REQUIRED_TOTAL_WEIGHT = 100;

    public class Request {
        @InvocableVariable(required=true)
        public Id fundingOpportunityId;

        @InvocableVariable(required=true)
        public Id workingTemplateId;

        @InvocableVariable(required=true)
        public String criteriaJson;

        @InvocableVariable
        public Boolean activateTemplate;
    }

    public class Response {
        @InvocableVariable public Id templateId;
        @InvocableVariable public Integer savedCriteriaCount;
        @InvocableVariable public Decimal totalWeight;
        @InvocableVariable public Boolean weightValid;
        @InvocableVariable public Boolean activated;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Save Evaluation Template Criteria')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response resp = new Response();
            resp.templateId = req == null ? null : req.workingTemplateId;
            resp.savedCriteriaCount = 0;
            resp.totalWeight = 0;
            resp.weightValid = false;
            resp.activated = false;

            if (req == null || req.workingTemplateId == null || String.isBlank(req.criteriaJson)) {
                resp.message = 'Missing template or criteria payload.';
                responses.add(resp);
                continue;
            }

            List<Object> parsedRows;
            try {
                parsedRows = (List<Object>) JSON.deserializeUntyped(req.criteriaJson);
            } catch (Exception ex) {
                resp.message = 'Criteria payload is invalid JSON.';
                responses.add(resp);
                continue;
            }

            Map<Id, Criterion_Library__c> sourceCriteriaMap = loadSourceCriteria(parsedRows);
            Map<Integer, String> generatedKeys = allocateGeneratedKeys(req.workingTemplateId, parsedRows);

            List<Evaluation_Template_Criterion__c> toInsert = new List<Evaluation_Template_Criterion__c>();
            Integer index = 0;
            Decimal weightTotal = 0;

            for (Object rowObj : parsedRows) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                String label = asString(row.get('Label__c'));
                if (String.isBlank(label)) {
                    index++;
                    continue;
                }

                Decimal weight = asDecimal(row.get('Weight__c'));
                if (weight != null) {
                    weightTotal += weight;
                }

                Id sourceId = asId(row.get('SourceLibraryCriterion__c'));
                Criterion_Library__c source = sourceCriteriaMap.get(sourceId);
                String sectionKey = asString(row.get('Section_Key__c'));
                String sectionName = asString(row.get('Section_Name__c'));
                Decimal sectionOrder = asDecimal(row.get('Section_Order__c'));
                // When a criterion comes from library, inherit section metadata unless explicitly overridden.
                if (source != null && source.Section_Library__r != null) {
                    if (String.isBlank(sectionKey)) {
                        sectionKey = source.Section_Library__r.DeveloperKey__c;
                    }
                    if (String.isBlank(sectionName)) {
                        sectionName = source.Section_Library__r.Label__c;
                    }
                    if (sectionOrder == null) {
                        sectionOrder = source.Section_Library__r.DisplayOrder__c;
                    }
                }
                if (String.isBlank(sectionName)) {
                    sectionName = 'General';
                }
                if (sectionOrder == null) {
                    sectionOrder = 999;
                }

                String criterionKey = asString(row.get('Criterion_Key__c'));
                // Criterion keys are durable identifiers used by runtime joins; always generate deterministic fallback.
                if (String.isBlank(criterionKey)) {
                    criterionKey = generatedKeys.get(index);
                }
                if (String.isBlank(criterionKey) && source != null && !String.isBlank(source.DeveloperKey__c)) {
                    criterionKey = source.DeveloperKey__c + '-' + String.valueOf(req.workingTemplateId).right(6);
                }
                if (String.isBlank(criterionKey)) {
                    criterionKey = 'CR-' + String.valueOf(req.workingTemplateId).right(6) + '-' + String.valueOf(index + 1);
                }

                Evaluation_Template_Criterion__c outRow = new Evaluation_Template_Criterion__c();
                outRow.Evaluation_Template__c = req.workingTemplateId;
                outRow.SourceLibraryCriterion__c = sourceId;
                outRow.IsCustom__c = sourceId == null;
                outRow.Section_Key__c = sectionKey;
                outRow.Section_Name__c = sectionName;
                outRow.Section_Order__c = sectionOrder;
                outRow.Label__c = label;
                outRow.Description__c = asString(row.get('Description__c'));
                outRow.Weight__c = weight == null ? 0 : weight;
                outRow.Required__c = asBoolean(row.get('Required__c'));
                outRow.Display_Order__c = asDecimal(row.get('Display_Order__c'));
                outRow.Criterion_Key__c = criterionKey;
                toInsert.add(outRow);
                index++;
            }

            resp.totalWeight = weightTotal.setScale(2);
            resp.weightValid = resp.totalWeight == REQUIRED_TOTAL_WEIGHT;

            // For the working draft template, replace the criterion set atomically from editor payload.
            // Historical evaluations remain safe because published/in-use templates are cloned before editing.
            delete [
                SELECT Id
                FROM Evaluation_Template_Criterion__c
                WHERE Evaluation_Template__c = :req.workingTemplateId
            ];
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            resp.savedCriteriaCount = toInsert.size();

            if (req.activateTemplate == true) {
                if (!resp.weightValid) {
                    resp.message = 'Total evaluation weight must equal 100 before activation.';
                    responses.add(resp);
                    continue;
                }

                update new Evaluation_Template__c(
                    Id = req.workingTemplateId,
                    Status__c = 'Published',
                    Active__c = true
                );

                if (req.fundingOpportunityId != null) {
                    update new FundingOpportunity(
                        Id = req.fundingOpportunityId,
                        Evaluation_Template__c = req.workingTemplateId
                    );
                }
                resp.activated = true;
                resp.message = 'Template published and linked to Funding Opportunity.';
            } else {
                update new Evaluation_Template__c(
                    Id = req.workingTemplateId,
                    Status__c = 'Draft',
                    Active__c = false
                );
                resp.message = 'Draft saved.';
            }

            responses.add(resp);
        }

        return responses;
    }

    private static Map<Id, Criterion_Library__c> loadSourceCriteria(List<Object> rows) {
        Set<Id> ids = new Set<Id>();
        for (Object rowObj : rows) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            Id sourceId = asId(row.get('SourceLibraryCriterion__c'));
            if (sourceId != null) {
                ids.add(sourceId);
            }
        }

        Map<Id, Criterion_Library__c> result = new Map<Id, Criterion_Library__c>();
        if (ids.isEmpty()) {
            return result;
        }
        for (Criterion_Library__c c : [
            SELECT Id, DeveloperKey__c,
                   Section_Library__r.DeveloperKey__c, Section_Library__r.Label__c, Section_Library__r.DisplayOrder__c
            FROM Criterion_Library__c
            WHERE Id IN :ids
        ]) {
            result.put(c.Id, c);
        }
        return result;
    }

    private static Map<Integer, String> allocateGeneratedKeys(Id templateId, List<Object> rows) {
        Integer needed = 0;
        Integer index = 0;
        List<Integer> positions = new List<Integer>();
        for (Object rowObj : rows) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            if (!String.isBlank(asString(row.get('Label__c'))) && String.isBlank(asString(row.get('Criterion_Key__c')))) {
                needed++;
                positions.add(index);
            }
            index++;
        }

        Map<Integer, String> out = new Map<Integer, String>();
        if (needed == 0) {
            return out;
        }
        List<String> generated = RubricTemplateService.generateCustomKeys(templateId, needed);
        for (Integer i = 0; i < positions.size() && i < generated.size(); i++) {
            out.put(positions[i], generated[i]);
        }
        return out;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Decimal asDecimal(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean asBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).toLowerCase() == 'true';
    }

    private static Id asId(Object value) {
        String v = asString(value);
        if (String.isBlank(v)) {
            return null;
        }
        try {
            return (Id) v;
        } catch (Exception ex) {
            return null;
        }
    }
}
