public with sharing class EvalTemplateWizardBuildAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id workingTemplateId;

        @InvocableVariable(required=true)
        public String selectedCriterionIdsCsv;
    }

    public class Response {
        @InvocableVariable public String criteriaJson;
        @InvocableVariable public Integer selectedCount;
    }

    @InvocableMethod(label='Build Criteria JSON From Library Selection')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response resp = new Response();
            if (req == null || req.workingTemplateId == null) {
                resp.criteriaJson = '[]';
                resp.selectedCount = 0;
                responses.add(resp);
                continue;
            }

            Set<Id> selectedIds = parseIds(req.selectedCriterionIdsCsv);
            if (selectedIds.isEmpty()) {
                resp.criteriaJson = '[]';
                resp.selectedCount = 0;
                responses.add(resp);
                continue;
            }

            Map<Id, Evaluation_Template_Criterion__c> existingBySource = new Map<Id, Evaluation_Template_Criterion__c>();
            for (Evaluation_Template_Criterion__c row : [
                SELECT Id, SourceLibraryCriterion__c, Section_Name__c, Section_Order__c, Section_Key__c,
                       Label__c, Description__c, Weight__c, Required__c, Display_Order__c, Criterion_Key__c
                FROM Evaluation_Template_Criterion__c
                WHERE Evaluation_Template__c = :req.workingTemplateId
                AND SourceLibraryCriterion__c IN :selectedIds
            ]) {
                if (row.SourceLibraryCriterion__c != null) {
                    existingBySource.put(row.SourceLibraryCriterion__c, row);
                }
            }

            List<Object> payload = new List<Object>();
            for (Criterion_Library__c lib : [
                SELECT Id, Label__c, Description__c, DefaultWeight__c, DefaultRequired__c, DisplayOrder__c, DeveloperKey__c,
                       Section_Library__r.DeveloperKey__c, Section_Library__r.Label__c, Section_Library__r.DisplayOrder__c
                FROM Criterion_Library__c
                WHERE Id IN :selectedIds
                ORDER BY Section_Library__r.DisplayOrder__c ASC NULLS LAST, DisplayOrder__c ASC NULLS LAST, Label__c ASC
            ]) {
                Evaluation_Template_Criterion__c existing = existingBySource.get(lib.Id);
                Map<String, Object> item = new Map<String, Object>();
                item.put('Evaluation_Template__c', req.workingTemplateId);
                item.put('SourceLibraryCriterion__c', lib.Id);
                item.put('IsCustom__c', false);
                // Preserve previously edited section metadata when re-opening the wizard, else fall back to library defaults.
                item.put('Section_Key__c', existing != null && !String.isBlank(existing.Section_Key__c)
                    ? existing.Section_Key__c
                    : (lib.Section_Library__r == null ? null : lib.Section_Library__r.DeveloperKey__c));
                item.put('Section_Name__c', existing != null && !String.isBlank(existing.Section_Name__c)
                    ? existing.Section_Name__c
                    : (lib.Section_Library__r == null ? 'General' : lib.Section_Library__r.Label__c));
                item.put('Section_Order__c', existing != null && existing.Section_Order__c != null
                    ? existing.Section_Order__c
                    : (lib.Section_Library__r == null ? 999 : lib.Section_Library__r.DisplayOrder__c));
                item.put('Label__c', existing != null && !String.isBlank(existing.Label__c) ? existing.Label__c : lib.Label__c);
                item.put('Description__c', existing != null && !String.isBlank(existing.Description__c) ? existing.Description__c : lib.Description__c);
                item.put('Weight__c', existing != null && existing.Weight__c != null ? existing.Weight__c : lib.DefaultWeight__c);
                item.put('Required__c', existing != null ? existing.Required__c : lib.DefaultRequired__c);
                item.put('Display_Order__c', existing != null && existing.Display_Order__c != null ? existing.Display_Order__c : lib.DisplayOrder__c);
                // Existing records keep their key; new rows get a key later in the save pipeline.
                item.put('Criterion_Key__c', existing == null ? null : existing.Criterion_Key__c);
                payload.add(item);
            }

            resp.criteriaJson = JSON.serialize(payload);
            resp.selectedCount = payload.size();
            responses.add(resp);
        }
        return responses;
    }

    private static Set<Id> parseIds(String csv) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(csv)) {
            return ids;
        }
        for (String token : csv.split(';')) {
            String val = token == null ? null : token.trim();
            if (String.isBlank(val)) {
                continue;
            }
            try {
                ids.add((Id) val);
            } catch (Exception ignored) {
            }
        }
        return ids;
    }
}
