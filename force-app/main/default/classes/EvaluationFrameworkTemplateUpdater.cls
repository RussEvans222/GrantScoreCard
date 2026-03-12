/*
This helper class persists AI framework review metrics back to
Evaluation_Template__c when fields exist and are writable.

Important design choice:
- Uses dynamic describe checks before writing fields.
- This keeps deployments safe across orgs with slightly different schema.
*/
public with sharing class EvaluationFrameworkTemplateUpdater {
    public class PersistResult {
        public Boolean updated;
        public String jsonFieldUsed;
    }

    public static Boolean applyFrameworkMetricsToTemplate(
        Id templateId,
        EvaluationFrameworkReviewService.FrameworkReviewResult result
    ) {
        PersistResult persisted = applyFrameworkMetricsToTemplate(templateId, result, null);
        return persisted == null ? false : persisted.updated;
    }

    public static PersistResult applyFrameworkMetricsToTemplate(
        Id templateId,
        EvaluationFrameworkReviewService.FrameworkReviewResult result,
        String serializedReviewJson
    ) {
        // PersistResult tells callers exactly what happened during save.
        PersistResult out = new PersistResult();
        out.updated = false;
        out.jsonFieldUsed = null;

        if (templateId == null || result == null) {
            return out;
        }

        // Dynamic field map lets us write only fields that are available in this org.
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        SObject updateRow = new Evaluation_Template__c(Id = templateId);
        Boolean hasChanges = false;

        hasChanges = putIfWritable(updateRow, fields, 'Framework_Health_Score__c', result.frameworkHealthScore) || hasChanges;
        hasChanges = putIfWritable(updateRow, fields, 'Framework_Clarity_Score__c', result.dimensionScores == null ? null : result.dimensionScores.clarity) || hasChanges;
        hasChanges = putIfWritable(updateRow, fields, 'Framework_Balance_Score__c', result.dimensionScores == null ? null : result.dimensionScores.balance) || hasChanges;
        hasChanges = putIfWritable(updateRow, fields, 'Framework_Coverage_Score__c', result.dimensionScores == null ? null : result.dimensionScores.coverage) || hasChanges;
        hasChanges = putIfWritable(updateRow, fields, 'Framework_Redundancy_Score__c', result.dimensionScores == null ? null : result.dimensionScores.redundancy) || hasChanges;
        hasChanges = putReviewedDate(updateRow, fields) || hasChanges;
        if (!String.isBlank(serializedReviewJson)) {
            String jsonFieldApiName = putReviewJsonIfAvailable(updateRow, fields, serializedReviewJson);
            if (!String.isBlank(jsonFieldApiName)) {
                out.jsonFieldUsed = jsonFieldApiName;
                hasChanges = true;
            }
        }

        if (hasChanges) {
            update updateRow;
            out.updated = true;
        }
        return out;
    }

    private static Boolean putIfWritable(SObject row, Map<String, Schema.SObjectField> fieldMap, String fieldApiName, Object value) {
        // Safety check pattern:
        // 1) field exists
        // 2) running user can update it
        if (!fieldMap.containsKey(fieldApiName)) {
            return false;
        }
        Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName).getDescribe();
        if (describe == null || !describe.isUpdateable()) {
            return false;
        }
        row.put(fieldApiName, value);
        return true;
    }

    private static Boolean putReviewedDate(SObject row, Map<String, Schema.SObjectField> fieldMap) {
        String fieldApiName = 'Framework_Last_Reviewed__c';
        if (!fieldMap.containsKey(fieldApiName)) {
            return false;
        }
        Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName).getDescribe();
        if (describe == null || !describe.isUpdateable()) {
            return false;
        }

        if (describe.getType() == Schema.DisplayType.Date) {
            row.put(fieldApiName, Date.today());
        } else {
            row.put(fieldApiName, DateTime.now());
        }
        return true;
    }

    private static String putReviewJsonIfAvailable(
        SObject row,
        Map<String, Schema.SObjectField> fieldMap,
        String serializedReviewJson
    ) {
        // Candidate list supports multiple org naming variants
        // without hard-failing when one field is absent.
        List<String> candidateFields = new List<String>{
            'Framework_Review_JSON__c',
            'AI_Framework_Insights__c',
            'Framework_Insights__c'
        };
        for (String apiName : candidateFields) {
            if (!fieldMap.containsKey(apiName)) {
                continue;
            }
            Schema.DescribeFieldResult describe = fieldMap.get(apiName).getDescribe();
            if (describe == null || !describe.isUpdateable()) {
                continue;
            }
            row.put(apiName, serializedReviewJson);
            return apiName;
        }
        return null;
    }
}