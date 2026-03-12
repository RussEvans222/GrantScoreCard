/*
SYSTEM OVERVIEW

GrantScoreCard demonstrates an AI-assisted grant evaluation workflow.

Data Flow:
Funding Opportunity
    ->
Grant Application Intake
    ->
Evaluation Template + Criteria
    ->
Reviewer Scorecards
    ->
AI Framework Review (Prompt Builder)
    ->
Criteria Library Governance

This service runs the end-to-end framework review process.
It loads Salesforce data, calls Prompt Builder, parses JSON into Apex DTOs,
and returns a response object that LWCs can render.
*/
/*
AI PROMPT INTEGRATION

GrantScoreCard uses Salesforce Prompt Builder templates to add AI assistance
without hard-coding model behavior directly in Apex.

Examples used in this repository:
- EvaluationFrameworkReview
- ETDisplayName

ETDisplayName generates a short display name for an evaluation template
from template metadata and selected criteria context.

Prompt templates run through Salesforce Einstein Trust Layer controls.
The result can be used for UI display, workflow guidance, or safe field updates.
*/
public with sharing class EvaluationFrameworkReviewService {
    private static final String TEMPLATE_API_NAME = 'EvaluationFrameworkReview';
    private static final String AI_SOURCE_LABEL = 'AI Framework Review';
    private static final String DRAFT_STATUS_LABEL = 'Draft';

    private interface PromptInvoker {
        // Small abstraction to keep prompt invocation testable.
        // In tests, we replace this with a fake response.
        String invokeTemplate(String templateApiName, Map<String, Object> inputParams);
    }

    @TestVisible
    private static System.Callable promptInvokerOverride;

    public class AnalyzeFrameworkResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id evaluationTemplateId;
        @AuraEnabled public String evaluationTemplateName;
        @AuraEnabled public Integer criteriaCount;
        @AuraEnabled public String promptTemplateApiName;
        @AuraEnabled public Boolean templateFieldsUpdated;
        @AuraEnabled public String persistedFieldApiName;
        @AuraEnabled public Boolean applyLibraryActions;
        @AuraEnabled public FrameworkReviewResult review;
        @AuraEnabled public LibraryActionSummary libraryActionSummary;
        @AuraEnabled public List<AnalyzedCriterion> relatedCriteria;
        @AuraEnabled public String reviewJson;

        public AnalyzeFrameworkResponse() {
            this.success = false;
            this.message = '';
            this.criteriaCount = 0;
            this.promptTemplateApiName = TEMPLATE_API_NAME;
            this.templateFieldsUpdated = false;
            this.persistedFieldApiName = null;
            this.applyLibraryActions = false;
            this.review = new FrameworkReviewResult();
            this.libraryActionSummary = new LibraryActionSummary();
            this.relatedCriteria = new List<AnalyzedCriterion>();
            this.reviewJson = null;
        }
    }

    public class AnalyzedCriterion {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String bundle;
        @AuraEnabled public Decimal weight;
    }

    public class LibraryActionSummary {
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public Integer flaggedForReviewCount;
        @AuraEnabled public Integer suggestedWeightUpdates;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> notes;

        public LibraryActionSummary() {
            this.createdCount = 0;
            this.flaggedForReviewCount = 0;
            this.suggestedWeightUpdates = 0;
            this.skippedCount = 0;
            this.notes = new List<String>();
        }
    }

    public class FrameworkReviewResult {
        @AuraEnabled public Decimal frameworkHealthScore;
        @AuraEnabled public FrameworkDimensionScores dimensionScores;
        @AuraEnabled public List<FrameworkIssue> issues;
        @AuraEnabled public List<FrameworkRecommendation> recommendations;
        @AuraEnabled public List<FrameworkImprovement> improvements;

        public FrameworkReviewResult() {
            this.dimensionScores = new FrameworkDimensionScores();
            this.issues = new List<FrameworkIssue>();
            this.recommendations = new List<FrameworkRecommendation>();
            this.improvements = new List<FrameworkImprovement>();
        }
    }

    public class FrameworkDimensionScores {
        @AuraEnabled public Decimal clarity;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public Decimal coverage;
        @AuraEnabled public Decimal redundancy;
    }

    public class FrameworkIssue {
        @AuraEnabled public String type;
        @AuraEnabled public String message;
    }

    public class FrameworkRecommendation {
        @AuraEnabled public String type;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal suggestedWeight;
    }

    public class FrameworkImprovement {
        @AuraEnabled public String criterion;
        @AuraEnabled public String message;
    }

    public class RecommendationActionResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public LibraryActionSummary summary;

        public RecommendationActionResponse() {
            this.success = false;
            this.message = '';
            this.summary = new LibraryActionSummary();
        }
    }

    @AuraEnabled
    public static AnalyzeFrameworkResponse analyzeFramework(
        Id evaluationTemplateId,
        Boolean applyLibraryActions,
        Boolean applyTemplateFieldUpdates
    ) {
        // This wrapper is sent back to the LWC so the UI gets both
        // machine-readable data and user-friendly status text.
        AnalyzeFrameworkResponse response = new AnalyzeFrameworkResponse();
        response.evaluationTemplateId = evaluationTemplateId;
        response.applyLibraryActions = applyLibraryActions == true;

        try {
            if (evaluationTemplateId == null) {
                response.message = 'Select an evaluation template before running framework analysis.';
                return response;
            }

            Evaluation_Template__c templateRow = [
                SELECT Id, Name, Description__c, Score_Scale_Max__c
                FROM Evaluation_Template__c
                WHERE Id = :evaluationTemplateId
                LIMIT 1
            ];
            response.evaluationTemplateName = resolveTemplateDisplayName(templateRow.Id, templateRow.Name);

            List<Evaluation_Template_Criterion__c> criteriaRows = [
                SELECT Id,
                       Evaluation_Template__c,
                       Criterion_Key__c,
                       Label__c,
                       Description__c,
                       Weight__c,
                       Section_Name__c,
                       Display_Order__c
                FROM Evaluation_Template_Criterion__c
                WHERE Evaluation_Template__c = :evaluationTemplateId
                ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC
            ];
            response.criteriaCount = criteriaRows.size();
            response.relatedCriteria = mapAnalyzedCriteria(criteriaRows);

            // Call Prompt Builder with prepared inputs.
            // The output must be JSON for downstream parsing.
            String rawOutput = getPromptInvoker().invokeTemplate(TEMPLATE_API_NAME, buildPromptInputs(templateRow, criteriaRows));
            FrameworkReviewResult parsed = parseFrameworkReview(rawOutput);
            response.review = parsed;
            response.reviewJson = JSON.serialize(parsed);

            // Default behavior: update template metrics unless caller opts out.
            Boolean shouldApplyTemplateUpdates = (applyTemplateFieldUpdates == null) ? true : applyTemplateFieldUpdates;
            if (shouldApplyTemplateUpdates) {
                EvaluationFrameworkTemplateUpdater.PersistResult persisted =
                    EvaluationFrameworkTemplateUpdater.applyFrameworkMetricsToTemplate(
                        evaluationTemplateId,
                        parsed,
                        response.reviewJson
                    );
                response.templateFieldsUpdated = persisted == null ? false : persisted.updated;
                response.persistedFieldApiName = persisted == null ? null : persisted.jsonFieldUsed;
            }

            if (response.applyLibraryActions) {
                response.libraryActionSummary = applyRecommendationActions(parsed.recommendations);
            } else {
                response.libraryActionSummary.notes.add('Preview mode enabled. Library actions were not applied.');
            }

            response.success = true;
            response.message = 'Framework analysis completed.';
            return response;
        } catch (QueryException qe) {
            response.message = 'Evaluation template not found.';
            return response;
        } catch (Exception ex) {
            response.message = 'Framework analysis failed: ' + ex.getMessage();
            return response;
        }
    }

    @AuraEnabled
    public static RecommendationActionResponse applySingleRecommendation(
        Id evaluationTemplateId,
        String recommendationType,
        String recommendationName,
        String recommendationDescription,
        Decimal suggestedWeight
    ) {
        RecommendationActionResponse response = new RecommendationActionResponse();
        try {
            if (evaluationTemplateId == null) {
                response.message = 'Evaluation template is required.';
                return response;
            }
            if (String.isBlank(recommendationType) || String.isBlank(recommendationName)) {
                response.message = 'Recommendation type and name are required.';
                return response;
            }

            FrameworkRecommendation recommendation = new FrameworkRecommendation();
            recommendation.type = recommendationType;
            recommendation.name = recommendationName;
            recommendation.description = recommendationDescription;
            recommendation.suggestedWeight = suggestedWeight;

            response.summary = applyRecommendationActions(new List<FrameworkRecommendation>{ recommendation });
            response.success = true;
            response.message = 'Recommendation action applied.';
            return response;
        } catch (Exception ex) {
            response.message = 'Failed to apply recommendation: ' + ex.getMessage();
            return response;
        }
    }

    private static Map<String, Object> buildPromptInputs(
        Evaluation_Template__c templateRow,
        List<Evaluation_Template_Criterion__c> criteriaRows
    ) {
        // Prompt Builder input map:
        // - template id as primary context
        // - criterion snapshot list as secondary context
        Map<String, Object> inputs = new Map<String, Object>();
        inputs.put('Input:Evaluation_Template', new Map<String, String>{ 'id' => String.valueOf(templateRow.Id) });
        inputs.put('Input:Evaluation_Template_Criterion', buildCriterionSnapshotInput(criteriaRows));
        return inputs;
    }

    // Resolves a user-facing template label so Insights UI does not fall back to raw auto-number when
    // a display-name field exists and has a value.
    private static String resolveTemplateDisplayName(Id templateId, String fallbackName) {
        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        List<String> candidates = new List<String>{
            'Display_Name__c',
            'Template_Display_Name__c',
            'User_Facing_Name__c',
            'Label__c'
        };

        String preferredField = null;
        for (String apiName : candidates) {
            if (templateFields.containsKey(apiName)) {
                preferredField = apiName;
                break;
            }
        }

        if (templateId == null) {
            return fallbackName;
        }

        String selectPreferred = String.isBlank(preferredField) ? '' : (preferredField + ', ');
        SObject row = Database.query(
            'SELECT Name, Status__c, Version__c, ' + selectPreferred +
            'Id FROM Evaluation_Template__c WHERE Id = :templateId LIMIT 1'
        );
        if (!String.isBlank(preferredField)) {
            String preferred = asText(row.get(preferredField));
            if (!String.isBlank(preferred)) {
                return preferred;
            }
        }

        String status = asText(row.get('Status__c'));
        String version = asText(row.get('Version__c'));
        if (!String.isBlank(version)) {
            String prefix = String.isBlank(status) ? 'Evaluation Rubric' : status + ' Rubric';
            return prefix + ' v' + version;
        }
        String fallback = asText(row.get('Name'));
        return String.isBlank(fallback) ? fallbackName : fallback;
    }

    private static List<Map<String, Object>> buildCriterionSnapshotInput(List<Evaluation_Template_Criterion__c> criteriaRows) {
        List<Map<String, Object>> snapshot = new List<Map<String, Object>>();
        for (Evaluation_Template_Criterion__c row : criteriaRows) {
            snapshot.add(new Map<String, Object>{
                'id' => String.valueOf(row.Id),
                'label' => row.Label__c,
                'description' => row.Description__c,
                'weight' => row.Weight__c,
                'sectionName' => row.Section_Name__c,
                'displayOrder' => row.Display_Order__c,
                'criterionKey' => row.Criterion_Key__c
            });
        }
        return snapshot;
    }

    private static List<AnalyzedCriterion> mapAnalyzedCriteria(List<Evaluation_Template_Criterion__c> criteriaRows) {
        List<AnalyzedCriterion> out = new List<AnalyzedCriterion>();
        for (Evaluation_Template_Criterion__c row : criteriaRows) {
            AnalyzedCriterion item = new AnalyzedCriterion();
            item.id = row.Id;
            item.name = row.Label__c;
            item.bundle = row.Section_Name__c;
            item.weight = row.Weight__c;
            out.add(item);
        }
        return out;
    }

    private static FrameworkReviewResult parseFrameworkReview(String rawOutput) {
        if (String.isBlank(rawOutput)) {
            throw new AuraHandledException('Prompt returned an empty response.');
        }

        // Use untyped parsing first so we can safely handle
        // missing keys or unexpected model output formats.
        String normalized = rawOutput.replace('\u00A0', ' ').trim();
        Object parsed = JSON.deserializeUntyped(normalized);
        if (!(parsed instanceof Map<String, Object>)) {
            throw new AuraHandledException('Prompt response was not valid JSON object output.');
        }

        Map<String, Object> payload = (Map<String, Object>) parsed;
        // DTO objects convert raw JSON into typed Apex structures
        // that are easier for UI components to consume.
        FrameworkReviewResult out = new FrameworkReviewResult();
        out.frameworkHealthScore = parseDecimal(payload.get('frameworkHealthScore'));

        Object dimensionRaw = payload.get('dimensionScores');
        if (dimensionRaw instanceof Map<String, Object>) {
            Map<String, Object> dims = (Map<String, Object>) dimensionRaw;
            out.dimensionScores.clarity = parseDecimal(dims.get('clarity'));
            out.dimensionScores.balance = parseDecimal(dims.get('balance'));
            out.dimensionScores.coverage = parseDecimal(dims.get('coverage'));
            out.dimensionScores.redundancy = parseDecimal(dims.get('redundancy'));
        }

        out.issues = parseIssues(payload.get('issues'));
        out.recommendations = parseRecommendations(payload.get('recommendations'));
        out.improvements = parseImprovements(payload.get('improvements'));
        return out;
    }

    private static List<FrameworkIssue> parseIssues(Object rawIssues) {
        List<FrameworkIssue> out = new List<FrameworkIssue>();
        if (!(rawIssues instanceof List<Object>)) {
            return out;
        }

        for (Object issueRaw : (List<Object>) rawIssues) {
            if (!(issueRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> issueMap = (Map<String, Object>) issueRaw;
            FrameworkIssue issue = new FrameworkIssue();
            issue.type = asText(issueMap.get('type'));
            issue.message = asText(issueMap.get('message'));
            out.add(issue);
        }
        return out;
    }

    private static List<FrameworkRecommendation> parseRecommendations(Object rawRecommendations) {
        List<FrameworkRecommendation> out = new List<FrameworkRecommendation>();
        if (!(rawRecommendations instanceof List<Object>)) {
            return out;
        }

        for (Object recommendationRaw : (List<Object>) rawRecommendations) {
            if (!(recommendationRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> recommendationMap = (Map<String, Object>) recommendationRaw;
            FrameworkRecommendation rec = new FrameworkRecommendation();
            rec.type = asText(recommendationMap.get('type')).toLowerCase();
            rec.name = asText(recommendationMap.get('name'));
            rec.description = asText(recommendationMap.get('description'));
            rec.suggestedWeight = parseDecimal(recommendationMap.get('suggestedWeight'));
            out.add(rec);
        }
        return out;
    }

    private static List<FrameworkImprovement> parseImprovements(Object rawImprovements) {
        List<FrameworkImprovement> out = new List<FrameworkImprovement>();
        if (!(rawImprovements instanceof List<Object>)) {
            return out;
        }

        for (Object improvementRaw : (List<Object>) rawImprovements) {
            if (!(improvementRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> improvementMap = (Map<String, Object>) improvementRaw;
            FrameworkImprovement improvement = new FrameworkImprovement();
            improvement.criterion = asText(improvementMap.get('criterion'));
            improvement.message = asText(improvementMap.get('message'));
            out.add(improvement);
        }
        return out;
    }

    private static LibraryActionSummary applyRecommendationActions(List<FrameworkRecommendation> recommendations) {
        LibraryActionSummary summary = new LibraryActionSummary();
        if (recommendations == null || recommendations.isEmpty()) {
            summary.notes.add('No AI recommendations were returned for criteria actions.');
            return summary;
        }

        Map<String, Schema.SObjectField> criterionFields = Schema.SObjectType.Criterion_Library__c.fields.getMap();

        Set<String> recommendationNames = new Set<String>();
        for (FrameworkRecommendation rec : recommendations) {
            if (String.isBlank(rec.name)) {
                continue;
            }
            recommendationNames.add(rec.name.trim().toLowerCase());
        }

        Map<String, Criterion_Library__c> existingByLabelLower = new Map<String, Criterion_Library__c>();
        if (!recommendationNames.isEmpty()) {
            for (Criterion_Library__c existing : [
                SELECT Id, Name, Label__c
                FROM Criterion_Library__c
                WHERE Label__c IN :recommendationNames OR Name IN :recommendationNames
            ]) {
                if (!String.isBlank(existing.Label__c)) {
                    existingByLabelLower.put(existing.Label__c.trim().toLowerCase(), existing);
                }
                if (!String.isBlank(existing.Name)) {
                    existingByLabelLower.put(existing.Name.trim().toLowerCase(), existing);
                }
            }
        }

        List<SObject> inserts = new List<SObject>();
        List<String> insertCriterionNames = new List<String>();
        List<SObject> updates = new List<SObject>();
        List<String> updateActionTypes = new List<String>();
        List<String> updateCriterionNames = new List<String>();
        for (FrameworkRecommendation rec : recommendations) {
            String normalizedType = String.isBlank(rec.type) ? '' : rec.type.toLowerCase();
            String recName = String.isBlank(rec.name) ? '' : rec.name.trim();
            String key = recName.toLowerCase();

            if (normalizedType == 'newcriterion') {
                if (String.isBlank(recName)) {
                    summary.skippedCount++;
                    summary.notes.add('Skipped newCriterion recommendation with missing name.');
                    continue;
                }
                if (existingByLabelLower.containsKey(key)) {
                    summary.skippedCount++;
                    summary.notes.add('Skipped newCriterion for existing criterion: ' + recName + '.');
                    continue;
                }

                SObject newCriterion = new Criterion_Library__c();
                if (criterionFields.containsKey('Label__c') && criterionFields.get('Label__c').getDescribe().isCreateable()) {
                    newCriterion.put('Label__c', recName);
                }
                if (criterionFields.containsKey('Description__c') && criterionFields.get('Description__c').getDescribe().isCreateable()) {
                    newCriterion.put('Description__c', emptyToNull(rec.description));
                }
                if (criterionFields.containsKey('DeveloperKey__c') && criterionFields.get('DeveloperKey__c').getDescribe().isCreateable()) {
                    newCriterion.put('DeveloperKey__c', buildDeveloperKey(recName));
                }
                if (criterionFields.containsKey('DefaultWeight__c') && criterionFields.get('DefaultWeight__c').getDescribe().isCreateable()) {
                    newCriterion.put('DefaultWeight__c', rec.suggestedWeight);
                }
                if (criterionFields.containsKey('Active__c') && criterionFields.get('Active__c').getDescribe().isCreateable()) {
                    newCriterion.put('Active__c', false);
                }
                dynamicSetIfAvailable(newCriterion, criterionFields, new List<String>{ 'Source__c', 'Source' }, AI_SOURCE_LABEL, true);
                dynamicSetIfAvailable(newCriterion, criterionFields, new List<String>{ 'Status__c', 'Status' }, DRAFT_STATUS_LABEL, true);

                inserts.add(newCriterion);
                insertCriterionNames.add(recName);
                continue;
            }

            if (normalizedType == 'modifycriterion' || normalizedType == 'adjustweight') {
                if (String.isBlank(recName) || !existingByLabelLower.containsKey(key)) {
                    summary.skippedCount++;
                    summary.notes.add('Skipped ' + normalizedType + ' for unmatched criterion: ' + recName + '.');
                    continue;
                }

                Criterion_Library__c existingCriterion = existingByLabelLower.get(key);
                SObject updateRow = new Criterion_Library__c(Id = existingCriterion.Id);
                Boolean hasChange = false;

                if (normalizedType == 'modifycriterion') {
                    hasChange = dynamicSetIfAvailable(updateRow, criterionFields, new List<String>{ 'Requires_Review__c' }, true, false) || hasChange;
                }

                if (normalizedType == 'adjustweight') {
                    hasChange = dynamicSetIfAvailable(
                        updateRow,
                        criterionFields,
                        new List<String>{ 'Suggested_Weight_Adjustment__c' },
                        rec.suggestedWeight,
                        false
                    ) || hasChange;
                }

                if (hasChange) {
                    updates.add(updateRow);
                    updateActionTypes.add(normalizedType);
                    updateCriterionNames.add(recName);
                } else {
                    summary.skippedCount++;
                    summary.notes.add('Skipped ' + normalizedType + ' for ' + recName + ' because optional fields are unavailable.');
                }
                continue;
            }

            summary.skippedCount++;
            summary.notes.add('Ignored unsupported recommendation type: ' + rec.type);
        }

        if (!inserts.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(inserts, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    summary.createdCount++;
                    continue;
                }
                summary.skippedCount++;
                summary.notes.add(
                    'Failed to create criterion ' + insertCriterionNames[i] + ': ' +
                    insertResults[i].getErrors()[0].getMessage()
                );
            }
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(updates, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    if (updateActionTypes[i] == 'modifycriterion') {
                        summary.flaggedForReviewCount++;
                    } else if (updateActionTypes[i] == 'adjustweight') {
                        summary.suggestedWeightUpdates++;
                    }
                    continue;
                }
                summary.skippedCount++;
                summary.notes.add(
                    'Failed to apply ' + updateActionTypes[i] + ' for ' + updateCriterionNames[i] + ': ' +
                    updateResults[i].getErrors()[0].getMessage()
                );
            }
        }

        if (summary.notes.isEmpty()) {
            summary.notes.add('Recommendation actions completed successfully.');
        }
        return summary;
    }

    private static Boolean dynamicSetIfAvailable(
        SObject row,
        Map<String, Schema.SObjectField> fieldMap,
        List<String> fieldCandidates,
        Object value,
        Boolean forCreate
    ) {
        if (fieldCandidates == null) {
            return false;
        }
        for (String fieldApiName : fieldCandidates) {
            if (!fieldMap.containsKey(fieldApiName)) {
                continue;
            }
            Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName).getDescribe();
            if (describe == null) {
                continue;
            }
            if (forCreate && !describe.isCreateable()) {
                continue;
            }
            if (!forCreate && !describe.isUpdateable()) {
                continue;
            }
            row.put(fieldApiName, value);
            return true;
        }
        return false;
    }

    private static String emptyToNull(String value) {
        return String.isBlank(value) ? null : value;
    }

    private static String buildDeveloperKey(String label) {
        String base = String.isBlank(label) ? 'ai_criterion' : label.toLowerCase();
        String normalized = base.replaceAll('[^a-z0-9]+', '_');
        while (normalized.startsWith('_')) {
            normalized = normalized.substring(1);
        }
        while (normalized.endsWith('_')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (String.isBlank(normalized)) {
            normalized = 'ai_criterion';
        }
        if (normalized.length() > 80) {
            normalized = normalized.substring(0, 80);
        }
        return normalized;
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            if (value instanceof Decimal) {
                return (Decimal) value;
            }
            if (value instanceof Integer) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (value instanceof Long) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (value instanceof Double) {
                return Decimal.valueOf(String.valueOf(value));
            }
            String asString = String.valueOf(value);
            if (String.isBlank(asString)) {
                return null;
            }
            return Decimal.valueOf(asString);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String asText(Object value) {
        return value == null ? '' : String.valueOf(value).trim();
    }

    private static PromptInvoker getPromptInvoker() {
        if (promptInvokerOverride != null) {
            return new CallablePromptInvoker(promptInvokerOverride);
        }
        return new RuntimePromptInvoker();
    }

    private class CallablePromptInvoker implements PromptInvoker {
        private System.Callable callableInvoker;

        CallablePromptInvoker(System.Callable callableInvoker) {
            this.callableInvoker = callableInvoker;
        }

        public String invokeTemplate(String templateApiName, Map<String, Object> inputParams) {
            Object result = callableInvoker.call('invokeTemplate', new Map<String, Object>{
                'templateApiName' => templateApiName,
                'inputParams' => inputParams
            });
            return result == null ? null : String.valueOf(result);
        }
    }

    private class RuntimePromptInvoker implements PromptInvoker {
        public String invokeTemplate(String templateApiName, Map<String, Object> inputParams) {
            return EvaluationFrameworkPromptInvoker.invokeTemplate(templateApiName, inputParams);
        }
    }
}