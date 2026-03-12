/*
AI PROMPT INTEGRATION

This controller powers reviewer-facing scorecard AI features.
It invokes Prompt Builder templates for both single-row and bulk suggestions.

Prompt examples used here:
- AFE_Criterion_Scoring_Suggestion
- AFE_Scorecard

Other manager-focused prompts (for template governance) include:
- EvaluationFrameworkReview
- ETDisplayName

These prompts keep AI generation logic configurable in Salesforce Prompt Builder
while Apex handles validation, parsing, and safe persistence.
*/
public with sharing class AFEScorecardController {
    private static final String SCORE_VALIDATION_MESSAGE = 'Score must be a whole number between 0 and 5.';
    private static final String AI_FAILURE_MESSAGE = 'AI suggestion failed. Please try again.';
    private static final String AI_TEMPLATE_API_NAME = 'AFE_Criterion_Scoring_Suggestion';
    private static final String AI_BULK_TEMPLATE_API_NAME = 'AFE_Scorecard';
    private static final String AI_FALLBACK_WARNING = 'Prompt runtime unavailable in Apex; fallback applied.';
    private static final String AI_MISSING_SCORE_WARNING = 'AI did not return a score for this criterion.';
    private static final String AI_MODE_FILL_BLANKS = 'FILL_BLANKS';
    private static final String AI_MODE_OVERWRITE_ALL = 'OVERWRITE_ALL';
    private static final Integer MAX_CITATION_COUNT = 3;
    private static final Integer MAX_CITATION_LENGTH = 200;
    private static final Integer MAX_EVIDENCE_STORAGE_LENGTH = 32768;
    private static final String AFE_STATUS_READY_FOR_SUBMISSION = 'Ready for Submission';
    private static final String AFE_STATUS_NEEDS_CLARIFICATION = 'Needs Clarification';
    private static final Decimal LOW_SCORE_THRESHOLD = 80;
    private static final Set<String> TERMINAL_AFE_STATUSES = new Set<String>{ 'Submitted', 'Panel Reviewed', 'Finalized' };

    private interface PromptInvoker {
        String invokeTemplate(String templateApiName, Map<String, Object> inputParams);
    }

    @TestVisible
    private static System.Callable promptInvokerOverride;

    private class EvaluationContext {
        public ApplicationFormEvaluation evaluation;
        public ApplicationForm applicationForm;
    }

    // Non-cacheable: score rows are edited in-session and must reflect latest DML immediately.
    @AuraEnabled
    public static List<Evaluation_Criterion_Score__c> getScores(Id afeId) {
        if (afeId == null) {
            return new List<Evaluation_Criterion_Score__c>();
        }

        List<Evaluation_Criterion_Score__c> rows = [
            SELECT Id,
                   Section_Key__c,
                   Section_Name__c,
                   Section_Order__c,
                   Criterion_Key__c,
                   Label__c,
                   Weight__c,
                   Suggested_Score__c,
                   Final_Score__c,
                   Rationale__c,
                   AI_Evidence__c,
                   Display_Order__c,
                   CreatedDate
            FROM Evaluation_Criterion_Score__c
            WHERE ApplicationFormEvaluation__c = :afeId
            ORDER BY Section_Order__c ASC, Display_Order__c ASC, CreatedDate ASC
        ];
        return rows;
    }

    @AuraEnabled
    public static void saveScores(List<Evaluation_Criterion_Score__c> updates) {
        if (updates == null || updates.isEmpty()) {
            return;
        }

        List<Evaluation_Criterion_Score__c> sanitized = new List<Evaluation_Criterion_Score__c>();
        Set<Id> updatedScoreIds = new Set<Id>();
        for (Evaluation_Criterion_Score__c incoming : updates) {
            if (incoming == null || incoming.Id == null) {
                continue;
            }
            updatedScoreIds.add(incoming.Id);

            Decimal score = incoming.Final_Score__c;
            if (score != null && (score < 0 || score > 5 || score != score.setScale(0))) {
                AuraHandledException ex = new AuraHandledException(SCORE_VALIDATION_MESSAGE);
                ex.setMessage(SCORE_VALIDATION_MESSAGE);
                throw ex;
            }
            Decimal suggestedScore = incoming.Suggested_Score__c;
            if (suggestedScore != null && (suggestedScore < 0 || suggestedScore > 5 || suggestedScore != suggestedScore.setScale(0))) {
                AuraHandledException ex = new AuraHandledException(SCORE_VALIDATION_MESSAGE);
                ex.setMessage(SCORE_VALIDATION_MESSAGE);
                throw ex;
            }

            sanitized.add(new Evaluation_Criterion_Score__c(
                Id = incoming.Id,
                Suggested_Score__c = suggestedScore,
                Final_Score__c = score,
                Rationale__c = incoming.Rationale__c,
                AI_Evidence__c = normalizeEvidenceStorageText(incoming.AI_Evidence__c)
            ));
        }

        if (!sanitized.isEmpty()) {
            update sanitized;
            updateAiConfidenceForEvaluations(updatedScoreIds);
        }
    }

    private static void updateAiConfidenceForEvaluations(Set<Id> updatedScoreIds) {
        if (updatedScoreIds == null || updatedScoreIds.isEmpty()) {
            return;
        }
        if (!Schema.SObjectType.ApplicationFormEvaluation.fields.getMap().containsKey('AI_Confidence__c')) {
            return;
        }

        Set<Id> evaluationIds = new Set<Id>();
        for (Evaluation_Criterion_Score__c scoreRow : [
            SELECT ApplicationFormEvaluation__c
            FROM Evaluation_Criterion_Score__c
            WHERE Id IN :updatedScoreIds
        ]) {
            if (scoreRow.ApplicationFormEvaluation__c != null) {
                evaluationIds.add(scoreRow.ApplicationFormEvaluation__c);
            }
        }
        if (evaluationIds.isEmpty()) {
            return;
        }

        Map<Id, ApplicationFormEvaluation> evaluationById = new Map<Id, ApplicationFormEvaluation>([
            SELECT Id, Status, Final_Recommendation__c, Weighted_Total__c
            FROM ApplicationFormEvaluation
            WHERE Id IN :evaluationIds
        ]);

        Map<Id, List<Evaluation_Criterion_Score__c>> scoresByEvaluation = new Map<Id, List<Evaluation_Criterion_Score__c>>();
        for (Evaluation_Criterion_Score__c scoreRow : [
            SELECT ApplicationFormEvaluation__c, Weight__c, Suggested_Score__c, Final_Score__c
            FROM Evaluation_Criterion_Score__c
            WHERE ApplicationFormEvaluation__c IN :evaluationIds
        ]) {
            Id evaluationId = scoreRow.ApplicationFormEvaluation__c;
            if (!scoresByEvaluation.containsKey(evaluationId)) {
                scoresByEvaluation.put(evaluationId, new List<Evaluation_Criterion_Score__c>());
            }
            scoresByEvaluation.get(evaluationId).add(scoreRow);
        }

        List<ApplicationFormEvaluation> afeUpdates = new List<ApplicationFormEvaluation>();
        for (Id evaluationId : evaluationIds) {
            List<Evaluation_Criterion_Score__c> scoreRows = scoresByEvaluation.get(evaluationId);
            if (scoreRows == null || scoreRows.isEmpty()) {
                continue;
            }

            Boolean allFinalScoresPresent = true;
            Decimal weightedAgreement = 0;
            Decimal totalWeight = 0;
            for (Evaluation_Criterion_Score__c scoreRow : scoreRows) {
                if (scoreRow.Final_Score__c == null) {
                    allFinalScoresPresent = false;
                }
                if (scoreRow.Final_Score__c == null || scoreRow.Suggested_Score__c == null) {
                    continue;
                }

                // Weighted agreement compares reviewer final score vs AI suggestion on a normalized 0-1 scale.
                Decimal weight = (scoreRow.Weight__c == null || scoreRow.Weight__c <= 0) ? 1 : scoreRow.Weight__c;
                Decimal scoreDelta = (scoreRow.Final_Score__c - scoreRow.Suggested_Score__c).abs();
                Decimal agreementRatio = (5 - scoreDelta) / 5;
                if (agreementRatio < 0) {
                    agreementRatio = 0;
                }
                weightedAgreement += (agreementRatio * weight);
                totalWeight += weight;
            }

            ApplicationFormEvaluation afeUpdate = new ApplicationFormEvaluation(Id = evaluationId);
            if (!allFinalScoresPresent || totalWeight == 0) {
                // Keep confidence blank until the review has a complete scored rubric.
                setAiConfidenceFieldValue(afeUpdate, null);
            } else {
                Decimal confidencePercent = (weightedAgreement / totalWeight) * 100;
                setAiConfidenceFieldValue(afeUpdate, confidencePercent.setScale(2));
            }

            ApplicationFormEvaluation currentAfe = evaluationById.get(evaluationId);
            setEvaluationStatusAfterScoring(afeUpdate, currentAfe, allFinalScoresPresent);
            afeUpdates.add(afeUpdate);
        }

        if (!afeUpdates.isEmpty()) {
            update afeUpdates;
        }
    }

    private static void setEvaluationStatusAfterScoring(
        ApplicationFormEvaluation afeUpdate,
        ApplicationFormEvaluation currentAfe,
        Boolean allFinalScoresPresent
    ) {
        if (afeUpdate == null || currentAfe == null || allFinalScoresPresent != true) {
            return;
        }
        Schema.DescribeFieldResult statusDescribe =
            Schema.SObjectType.ApplicationFormEvaluation.fields.getMap().get('Status').getDescribe();
        if (statusDescribe == null || !statusDescribe.isUpdateable()) {
            return;
        }

        String currentStatus = currentAfe.Status;
        if (!String.isBlank(currentStatus) && TERMINAL_AFE_STATUSES.contains(currentStatus)) {
            // Do not move status backward once submitted/panel-reviewed/finalized.
            return;
        }

        String recommendation = currentAfe.Final_Recommendation__c == null
            ? ''
            : currentAfe.Final_Recommendation__c.toLowerCase();
        Decimal weightedTotal = currentAfe.Weighted_Total__c;
        Boolean isLowScore = weightedTotal == null || weightedTotal < LOW_SCORE_THRESHOLD;
        Boolean needsMoreInfoRecommendation =
            recommendation.contains('ask for revisions') ||
            recommendation.contains('more information') ||
            recommendation.contains('clarification');

        String targetStatus = (isLowScore && needsMoreInfoRecommendation)
            ? AFE_STATUS_NEEDS_CLARIFICATION
            : AFE_STATUS_READY_FOR_SUBMISSION;
        String resolvedStatus = resolvePicklistValue(
            statusDescribe.getPicklistValues(),
            targetStatus
        );
        if (!String.isBlank(resolvedStatus)) {
            afeUpdate.Status = resolvedStatus;
        }
    }

    private static void setAiConfidenceFieldValue(ApplicationFormEvaluation afeUpdate, Decimal confidencePercent) {
        if (afeUpdate == null) {
            return;
        }

        Schema.DescribeFieldResult confidenceDescribe =
            Schema.SObjectType.ApplicationFormEvaluation.fields.getMap().get('AI_Confidence__c').getDescribe();
        Schema.DisplayType confidenceType = confidenceDescribe == null ? null : confidenceDescribe.getType();
        if (confidenceDescribe == null || !confidenceDescribe.isUpdateable()) {
            return;
        }

        if (confidencePercent == null) {
            afeUpdate.put('AI_Confidence__c', null);
            return;
        }

        if (confidenceType == Schema.DisplayType.Double ||
            confidenceType == Schema.DisplayType.Currency ||
            confidenceType == Schema.DisplayType.Percent ||
            confidenceType == Schema.DisplayType.Integer ||
            confidenceType == Schema.DisplayType.Long) {
            afeUpdate.put('AI_Confidence__c', confidencePercent);
            return;
        }

        if (confidenceType == Schema.DisplayType.Picklist) {
            String mappedBand;
            if (confidencePercent >= 80) {
                mappedBand = 'High';
            } else if (confidencePercent >= 60) {
                mappedBand = 'Medium';
            } else {
                mappedBand = 'Low';
            }
            afeUpdate.put('AI_Confidence__c', resolvePicklistValue(confidenceDescribe.getPicklistValues(), mappedBand));
            return;
        }

        // Some org variants may define AI_Confidence__c as text; serialize numeric confidence for display.
        afeUpdate.put('AI_Confidence__c', String.valueOf(confidencePercent));
    }

    private static String resolvePicklistValue(List<Schema.PicklistEntry> entries, String preferredValue) {
        if (entries == null || entries.isEmpty()) {
            return null;
        }
        for (Schema.PicklistEntry entry : entries) {
            if (entry != null && entry.isActive() && entry.getValue() == preferredValue) {
                return entry.getValue();
            }
        }
        for (Schema.PicklistEntry entry : entries) {
            if (entry != null && entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    // Non-cacheable: summary values (weighted total/recommendation/status) change after score updates.
    @AuraEnabled
    public static ApplicationFormEvaluation getEvaluationSummary(Id afeId) {
        if (afeId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldsByApiName =
            Schema.SObjectType.ApplicationFormEvaluation.fields.getMap();

        String selectFields = 'Id, Weighted_Total__c, Final_Recommendation__c, CreatedDate';
        if (fieldsByApiName.containsKey('Status__c')) {
            selectFields += ', Status__c';
        }

        String soql =
            'SELECT ' + selectFields +
            ' FROM ApplicationFormEvaluation' +
            ' WHERE Id = :afeId' +
            ' LIMIT 1';

        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) {
            return null;
        }

        return (ApplicationFormEvaluation) rows[0];
    }

    // Non-cacheable: keep context panel aligned with current related record data.
    @AuraEnabled
    public static Map<String, Object> getApplicationContext(Id afeId) {
        Map<String, Object> response = new Map<String, Object>{
            'fundingOpportunity' => new Map<String, Object>(),
            'applicationForm' => new Map<String, Object>()
        };

        if (afeId == null) {
            return response;
        }

        List<ApplicationFormEvaluation> afeRows = [
            SELECT ApplicationFormId
            FROM ApplicationFormEvaluation
            WHERE Id = :afeId
            LIMIT 1
        ];
        if (afeRows.isEmpty() || afeRows[0].ApplicationFormId == null) {
            return response;
        }

        Id formId = afeRows[0].ApplicationFormId;
        String appFormSoql =
            'SELECT Id, Name, Purpose, RequestedAmount, ApplicationSummary, Stage, Type' +
            ' FROM ApplicationForm' +
            ' WHERE Id = :formId' +
            ' LIMIT 1';
        List<SObject> appFormRows = Database.query(appFormSoql);
        if (!appFormRows.isEmpty()) {
            SObject formRow = appFormRows[0];
            Map<String, Object> appFormMap = new Map<String, Object>{
                'id' => formRow.get('Id'),
                'name' => formRow.get('Name'),
                'purpose' => formRow.get('Purpose'),
                'requestedAmount' => formRow.get('RequestedAmount'),
                'applicationSummary' => formRow.get('ApplicationSummary'),
                'stage' => formRow.get('Stage'),
                'type' => formRow.get('Type')
            };
            response.put('applicationForm', appFormMap);
        }

        List<ApplicationFormRelation> relationRows = [
            SELECT ReferenceRecordId
            FROM ApplicationFormRelation
            WHERE ApplicationFormId = :formId
            AND ReferenceObjectName = 'FundingOpportunity'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!relationRows.isEmpty() && relationRows[0].ReferenceRecordId != null) {
            Id foId = relationRows[0].ReferenceRecordId;
            Map<String, Schema.SObjectField> foFields = Schema.SObjectType.FundingOpportunity.fields.getMap();
            List<String> foSelectFields = new List<String>{ 'Id', 'Name' };
            // Guard optional fields so this controller works across org/package variants.
            if (foFields.containsKey('MinimumFundingAmount')) {
                foSelectFields.add('MinimumFundingAmount');
            }
            if (foFields.containsKey('MaximumFundingAmount')) {
                foSelectFields.add('MaximumFundingAmount');
            }

            String foSoql =
                'SELECT ' + String.join(foSelectFields, ',') +
                ' FROM FundingOpportunity' +
                ' WHERE Id = :foId' +
                ' LIMIT 1';
            List<SObject> foRows = Database.query(foSoql);
            if (!foRows.isEmpty()) {
                SObject fo = foRows[0];
                Map<String, Object> foMap = new Map<String, Object>{
                    'id' => fo.get('Id'),
                    'name' => fo.get('Name'),
                    'programMin' => foFields.containsKey('MinimumFundingAmount') ? fo.get('MinimumFundingAmount') : null,
                    'programMax' => foFields.containsKey('MaximumFundingAmount') ? fo.get('MaximumFundingAmount') : null
                };
                response.put('fundingOpportunity', foMap);
            }
        }

        return response;
    }

    @AuraEnabled
    public static Map<String, Object> generateAISuggestion(Id evaluationId, Id criterionScoreId) {
        try {
            if (evaluationId == null || criterionScoreId == null) {
                throw buildAiFailureException();
            }

            EvaluationContext context = loadEvaluationContext(evaluationId);
            if (context == null || context.evaluation == null || context.applicationForm == null) {
                throw buildAiFailureException();
            }

            Map<String, Schema.SObjectField> criterionFieldsByApiName =
                Schema.SObjectType.Evaluation_Criterion_Score__c.fields.getMap();
            List<String> criterionSelectFields = new List<String>{
                'Id',
                'ApplicationFormEvaluation__c',
                'Label__c',
                'Weight__c'
            };
            Boolean hasCriterionDescription = criterionFieldsByApiName.containsKey('Description__c');
            if (hasCriterionDescription) {
                criterionSelectFields.add('Description__c');
            }

            String criterionSoql =
                'SELECT ' + String.join(criterionSelectFields, ',') +
                ' FROM Evaluation_Criterion_Score__c' +
                ' WHERE Id = :criterionScoreId' +
                ' LIMIT 1';
            List<SObject> criterionRows = Database.query(criterionSoql);
            if (criterionRows.isEmpty()) {
                throw buildAiFailureException();
            }

            SObject criterion = criterionRows[0];
            Id criterionEvaluationId = (Id) criterion.get('ApplicationFormEvaluation__c');
            if (criterionEvaluationId == null || criterionEvaluationId != evaluationId) {
                throw buildAiFailureException();
            }

            SObject applicationForm = context.applicationForm;

            Decimal fundingMin = null;
            Decimal fundingMax = null;
            List<ApplicationFormRelation> relationRows = [
                SELECT ReferenceRecordId
                FROM ApplicationFormRelation
                WHERE ApplicationFormId = :context.evaluation.ApplicationFormId
                AND ReferenceObjectName = 'FundingOpportunity'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!relationRows.isEmpty() && relationRows[0].ReferenceRecordId != null) {
                Id fundingOpportunityId = relationRows[0].ReferenceRecordId;
                Map<String, Schema.SObjectField> foFields = Schema.SObjectType.FundingOpportunity.fields.getMap();
                List<String> foSelectFields = new List<String>{ 'Id' };
                Boolean hasMinimumFundingAmount = foFields.containsKey('MinimumFundingAmount');
                Boolean hasMaximumFundingAmount = foFields.containsKey('MaximumFundingAmount');
                if (hasMinimumFundingAmount) {
                    foSelectFields.add('MinimumFundingAmount');
                }
                if (hasMaximumFundingAmount) {
                    foSelectFields.add('MaximumFundingAmount');
                }

                String fundingOpportunitySoql =
                    'SELECT ' + String.join(foSelectFields, ',') +
                    ' FROM FundingOpportunity' +
                    ' WHERE Id = :fundingOpportunityId' +
                    ' LIMIT 1';
                List<SObject> fundingRows = Database.query(fundingOpportunitySoql);
                if (!fundingRows.isEmpty()) {
                    SObject funding = fundingRows[0];
                    fundingMin = hasMinimumFundingAmount ? (Decimal) funding.get('MinimumFundingAmount') : null;
                    fundingMax = hasMaximumFundingAmount ? (Decimal) funding.get('MaximumFundingAmount') : null;
                }
            }

            Map<String, Object> inputParams = new Map<String, Object>{
                'ApplicationPurpose' => toPromptString(applicationForm.get('Purpose')),
                'RequestedAmount' => toPromptString(applicationForm.get('RequestedAmount')),
                'ApplicationStage' => toPromptString(applicationForm.get('Stage')),
                'CriterionLabel' => toPromptString(criterion.get('Label__c')),
                'CriterionDescription' => hasCriterionDescription ? toPromptString(criterion.get('Description__c')) : null
            };

            return tryAiSuggestion(inputParams);
        } catch (Exception aiException) {
            System.debug(
                LoggingLevel.WARN,
                'AFEScorecardController.generateAISuggestion fallback used; evaluationId=' + evaluationId +
                ', criterionScoreId=' + criterionScoreId +
                ', reason=' + aiException.getTypeName() + ': ' + aiException.getMessage()
            );
            try {
                // Try contextual fallback first when source records are available.
                List<Evaluation_Criterion_Score__c> criterionRows = [
                    SELECT Id, Label__c, Weight__c, ApplicationFormEvaluation__c
                    FROM Evaluation_Criterion_Score__c
                    WHERE Id = :criterionScoreId
                    LIMIT 1
                ];
                if (!criterionRows.isEmpty() && criterionRows[0].ApplicationFormEvaluation__c == evaluationId) {
                    List<ApplicationFormEvaluation> evalRows = [
                        SELECT Id, ApplicationFormId
                        FROM ApplicationFormEvaluation
                        WHERE Id = :evaluationId
                        LIMIT 1
                    ];
                    if (!evalRows.isEmpty() && evalRows[0].ApplicationFormId != null) {
                        List<ApplicationForm> appRows = [
                            SELECT Id, Stage, RequestedAmount
                            FROM ApplicationForm
                            WHERE Id = :evalRows[0].ApplicationFormId
                            LIMIT 1
                        ];
                        if (!appRows.isEmpty()) {
                            return buildFallbackSuggestion(
                                criterionRows[0],
                                appRows[0],
                                null,
                                null
                            );
                        }
                    }
                }
            } catch (Exception ignored) {
                // Generic fallback below handles any retrieval issues.
            }
            return buildGenericFallbackSuggestion(aiException);
        }
    }

    public class AISuggestionResult {
        @AuraEnabled public Id criterionScoreId;
        @AuraEnabled public Integer suggestedScore;
        @AuraEnabled public String suggestedRationale;
        @AuraEnabled public List<String> citations;
        @AuraEnabled public String source;
        @AuraEnabled public String warning;
        @AuraEnabled public Boolean skipped;
    }

    @AuraEnabled
    public static List<AISuggestionResult> generateAISuggestionsForEvaluation(Id evaluationId, String mode) {
        List<AISuggestionResult> results = new List<AISuggestionResult>();
        if (evaluationId == null) {
            return results;
        }

        String effectiveMode = normalizeMode(mode);
        List<Evaluation_Criterion_Score__c> criteria = [
            SELECT Id, Criterion_Key__c, Label__c, Description__c, Weight__c, Suggested_Score__c, Rationale__c, AI_Evidence__c
            FROM Evaluation_Criterion_Score__c
            WHERE ApplicationFormEvaluation__c = :evaluationId
            ORDER BY Section_Order__c ASC, Display_Order__c ASC, CreatedDate ASC
        ];

        List<Evaluation_Criterion_Score__c> targetCriteria = new List<Evaluation_Criterion_Score__c>();
        for (Evaluation_Criterion_Score__c criterion : criteria) {
            if (AI_MODE_FILL_BLANKS == effectiveMode && !shouldFillBlank(criterion)) {
                AISuggestionResult skippedResult = new AISuggestionResult();
                skippedResult.criterionScoreId = criterion.Id;
                skippedResult.skipped = true;
                results.add(skippedResult);
                continue;
            }
            targetCriteria.add(criterion);
        }

        if (targetCriteria.isEmpty()) {
            return results;
        }

        try {
            EvaluationContext context = loadEvaluationContext(evaluationId);
            if (context == null || context.evaluation == null || context.applicationForm == null) {
                throw buildAiFailureException();
            }
            Map<Id, Integer> maxScoreByCriterionId =
                resolveMaxScoreByCriterionId(targetCriteria, context.evaluation.Evaluation_Template__c);
            Map<Id, Map<String, Object>> suggestionByCriterionId =
                tryBulkAiSuggestion(context, targetCriteria, maxScoreByCriterionId);

            for (Evaluation_Criterion_Score__c criterion : targetCriteria) {
                Map<String, Object> suggestion = suggestionByCriterionId.get(criterion.Id);
                if (suggestion == null) {
                    AISuggestionResult missing = new AISuggestionResult();
                    missing.criterionScoreId = criterion.Id;
                    missing.skipped = true;
                    missing.warning = AI_MISSING_SCORE_WARNING;
                    results.add(missing);
                    continue;
                }
                results.add(toAiSuggestionResult(criterion.Id, suggestion));
            }
        } catch (Exception ex) {
            for (Evaluation_Criterion_Score__c criterion : targetCriteria) {
                results.add(toAiSuggestionResult(criterion.Id, buildGenericFallbackSuggestion(ex)));
            }
        }

        return results;
    }

    private static Map<String, Object> buildGenericFallbackSuggestion(Exception rootCause) {
        return new Map<String, Object>{
            'suggestedScore' => 3,
            'suggestedRationale' => 'Fallback suggestion applied: AI runtime or context retrieval was unavailable.',
            'citations' => new List<String>(),
            'source' => 'fallback',
            'warning' => AI_FALLBACK_WARNING + ' Reason: ' + rootCause.getMessage()
        };
    }

    private static Map<String, Object> tryAiSuggestion(Map<String, Object> inputParams) {
        String rawJson = getPromptInvoker().invokeTemplate(AI_TEMPLATE_API_NAME, inputParams);
        if (String.isBlank(rawJson)) {
            throw buildAiFailureException();
        }

        Object parsed = JSON.deserializeUntyped(rawJson);
        if (!(parsed instanceof Map<String, Object>)) {
            throw buildAiFailureException();
        }
        Map<String, Object> parsedMap = (Map<String, Object>) parsed;

        Integer score = clampScore(coerceToInteger(parsedMap.get('suggestedScore')));
        String rationale = parsedMap.get('suggestedRationale') == null
            ? ''
            : String.valueOf(parsedMap.get('suggestedRationale'));
        List<String> citations = extractAndNormalizeCitations(parsedMap);

        return new Map<String, Object>{
            'suggestedScore' => score,
            'suggestedRationale' => rationale,
            'citations' => citations,
            'source' => 'ai'
        };
    }

    private static Map<Id, Map<String, Object>> tryBulkAiSuggestion(
        EvaluationContext context,
        List<Evaluation_Criterion_Score__c> criteria,
        Map<Id, Integer> maxScoreByCriterionId
    ) {
        if (context == null || context.evaluation == null || context.applicationForm == null) {
            throw new AuraHandledException('AI scoring failed: missing evaluation or application context');
        }

        Set<Id> expectedIds = new Set<Id>();
        for (Evaluation_Criterion_Score__c criterion : criteria) {
            expectedIds.add(criterion.Id);
        }

        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();

        ConnectApi.WrappedValue evaluationInput = new ConnectApi.WrappedValue();
        evaluationInput.value = new Map<String, String>{ 'id' => String.valueOf(context.evaluation.Id) };
        inputParams.put('Input:ApplicationFormEvaluation', evaluationInput);

        Map<String, Object> invokeInputParams = new Map<String, Object>();
        for (String key : inputParams.keySet()) {
            invokeInputParams.put(key, inputParams.get(key).value);
        }

        System.debug(LoggingLevel.ERROR, 'AI BULK TEMPLATE NAME: ' + AI_BULK_TEMPLATE_API_NAME);
        System.debug(LoggingLevel.ERROR, 'AI INPUT PARAMS: ' + JSON.serialize(invokeInputParams));

        String rawJson;
        try {
            rawJson = getPromptInvoker().invokeTemplate(AI_BULK_TEMPLATE_API_NAME, invokeInputParams);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AI PROMPT FAILURE MESSAGE: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'AI PROMPT FAILURE TYPE: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'AI INPUT PARAMS AT FAILURE: ' + JSON.serialize(invokeInputParams));
            throw e;
        }

        System.debug(LoggingLevel.ERROR, 'AI RAW RESPONSE TEXT: ' + rawJson);
        if (String.isBlank(rawJson)) {
            throw buildAiFailureException();
        }

        // Prompt responses can include non-breaking spaces in pretty-printed JSON.
        String normalizedRawJson = rawJson.replace('\u00A0', ' ');
        Object parsed = JSON.deserializeUntyped(normalizedRawJson);
        if (!(parsed instanceof Map<String, Object>)) {
            throw buildAiFailureException();
        }

        Map<String, Object> parsedMap = (Map<String, Object>) parsed;
        Object scoresRaw = parsedMap.get('scores');
        if (!(scoresRaw instanceof List<Object>)) {
            throw buildAiFailureException();
        }

        Map<Id, Map<String, Object>> resultByCriterionId = new Map<Id, Map<String, Object>>();
        for (Object scoreItemRaw : (List<Object>) scoresRaw) {
            if (!(scoreItemRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> scoreItem = (Map<String, Object>) scoreItemRaw;
            Object criterionIdRaw = scoreItem.containsKey('criterionScoreId')
                ? scoreItem.get('criterionScoreId')
                : scoreItem.get('criterionId');
            Id criterionId = coerceToId(criterionIdRaw);
            if (criterionId == null || !expectedIds.contains(criterionId)) {
                continue;
            }

            Integer maxScore = maxScoreByCriterionId.containsKey(criterionId) ? maxScoreByCriterionId.get(criterionId) : 5;
            // Accept both legacy and current parser keys so prompt template updates remain backward compatible.
            Object suggestedScoreRaw = scoreItem.containsKey('suggestedScore')
                ? scoreItem.get('suggestedScore')
                : scoreItem.get('score');
            Integer parsedScore = tryCoerceToInteger(suggestedScoreRaw);
            if (parsedScore == null) {
                continue;
            }
            Integer boundedScore = clampScoreToRange(parsedScore, maxScore);

            Object suggestedRationaleRaw = scoreItem.containsKey('suggestedRationale')
                ? scoreItem.get('suggestedRationale')
                : scoreItem.get('reason');
            List<String> citations = extractAndNormalizeCitations(scoreItem);
            resultByCriterionId.put(criterionId, new Map<String, Object>{
                'suggestedScore' => boundedScore,
                'suggestedRationale' => suggestedRationaleRaw == null
                    ? ''
                    : String.valueOf(suggestedRationaleRaw),
                'citations' => citations,
                'source' => 'ai'
            });
        }

        return resultByCriterionId;
    }

    private static Map<String, Object> buildFallbackSuggestion(
        SObject criterion,
        SObject applicationForm,
        Decimal fundingMin,
        Decimal fundingMax
    ) {
        Integer score = 3;
        Decimal requestedAmount = (Decimal) applicationForm.get('RequestedAmount');
        if (requestedAmount != null && fundingMin != null && fundingMax != null &&
            requestedAmount >= fundingMin && requestedAmount <= fundingMax) {
            score += 1;
        }

        String stage = toPromptString(applicationForm.get('Stage')).toLowerCase();
        if (stage == 'submitted' || stage == 'under review' || stage == 'complete') {
            score += 1;
        }

        Integer fallbackScore = clampScore(score);
        String criterionLabel = toPromptString(criterion.get('Label__c'));
        String rationale =
            'Fallback suggestion for ' + criterionLabel + ': application stage is ' +
            toPromptString(applicationForm.get('Stage')) +
            '. Requested amount is ' + (requestedAmount == null ? 'not provided' : String.valueOf(requestedAmount)) +
            ' and funding range alignment is ' +
            ((fundingMin != null && fundingMax != null && requestedAmount != null &&
            requestedAmount >= fundingMin && requestedAmount <= fundingMax) ? 'within range.' : 'not confirmed.');

        return new Map<String, Object>{
            'suggestedScore' => fallbackScore,
            'suggestedRationale' => rationale,
            'citations' => new List<String>(),
            'source' => 'fallback',
            'warning' => AI_FALLBACK_WARNING
        };
    }

    private static PromptInvoker getPromptInvoker() {
        if (promptInvokerOverride != null) {
            return new CallablePromptInvoker(promptInvokerOverride);
        }
        return new ConnectApiPromptInvoker();
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

    private class ConnectApiPromptInvoker implements PromptInvoker {
        public String invokeTemplate(String templateApiName, Map<String, Object> inputParams) {
            Map<String, ConnectApi.WrappedValue> wrappedInputParams = new Map<String, ConnectApi.WrappedValue>();
            for (String key : inputParams.keySet()) {
                ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
                wrapped.value = inputParams.get(key);
                wrappedInputParams.put(key, wrapped);
            }

            ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            generationInput.inputParams = wrappedInputParams;
            generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            generationInput.additionalConfig.applicationName = 'PromptBuilderPreview';
            generationInput.isPreview = false;

            System.debug(LoggingLevel.ERROR,
                'AI PROMPT INVOKE template=' + templateApiName +
                ' applicationName=' + generationInput.additionalConfig.applicationName
            );

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, generationInput);

            if (generationOutput == null || generationOutput.generations == null || generationOutput.generations.isEmpty()) {
                throw buildAiFailureException();
            }

            ConnectApi.EinsteinLLMGenerationItemOutput firstGeneration = generationOutput.generations[0];
            if (firstGeneration == null) {
                throw buildAiFailureException();
            }
            String outputText = firstGeneration.text;
            if (String.isBlank(outputText)) {
                throw buildAiFailureException();
            }
            return outputText;
        }
    }

    private static Integer coerceToInteger(Object rawValue) {
        if (rawValue == null) {
            throw buildAiFailureException();
        }
        if (rawValue instanceof Integer) {
            return (Integer) rawValue;
        }
        if (rawValue instanceof Long) {
            return Integer.valueOf(String.valueOf(rawValue));
        }
        if (rawValue instanceof Decimal) {
            return ((Decimal) rawValue).intValue();
        }
        if (rawValue instanceof String) {
            return Decimal.valueOf((String) rawValue).intValue();
        }
        throw buildAiFailureException();
    }

    private static Integer tryCoerceToInteger(Object rawValue) {
        try {
            return coerceToInteger(rawValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id coerceToId(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        try {
            return Id.valueOf(String.valueOf(rawValue));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer clampScore(Integer score) {
        if (score == null) {
            throw buildAiFailureException();
        }
        return Math.max(0, Math.min(5, score));
    }

    private static Integer clampScoreToRange(Integer score, Integer maxScore) {
        if (score == null) {
            throw buildAiFailureException();
        }
        Integer safeMax = maxScore == null ? 5 : Math.max(0, Math.min(5, maxScore));
        return Math.max(0, Math.min(safeMax, score));
    }

    private static AuraHandledException buildAiFailureException() {
        AuraHandledException ex = new AuraHandledException(AI_FAILURE_MESSAGE);
        ex.setMessage(AI_FAILURE_MESSAGE);
        return ex;
    }

    private static String toPromptString(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static EvaluationContext loadEvaluationContext(Id evaluationId) {
        if (evaluationId == null) {
            return null;
        }
        List<ApplicationFormEvaluation> evaluationRows = [
            SELECT Id, ApplicationFormId, Evaluation_Template__c
            FROM ApplicationFormEvaluation
            WHERE Id = :evaluationId
            LIMIT 1
        ];
        if (evaluationRows.isEmpty() || evaluationRows[0].ApplicationFormId == null) {
            return null;
        }

        List<ApplicationForm> applicationRows = [
            SELECT Id, Name, Title, Purpose, RequestedAmount, ApplicationSummary, Stage, Type
            FROM ApplicationForm
            WHERE Id = :evaluationRows[0].ApplicationFormId
            LIMIT 1
        ];
        if (applicationRows.isEmpty()) {
            return null;
        }

        EvaluationContext context = new EvaluationContext();
        context.evaluation = evaluationRows[0];
        context.applicationForm = applicationRows[0];
        return context;
    }

    private static Map<Id, Integer> resolveMaxScoreByCriterionId(
        List<Evaluation_Criterion_Score__c> criteria,
        Id templateId
    ) {
        Map<Id, Integer> maxByCriterionId = new Map<Id, Integer>();
        Map<String, List<Id>> criterionIdsByKey = new Map<String, List<Id>>();
        for (Evaluation_Criterion_Score__c criterion : criteria) {
            maxByCriterionId.put(criterion.Id, 5);
            if (String.isBlank(criterion.Criterion_Key__c)) {
                continue;
            }
            if (!criterionIdsByKey.containsKey(criterion.Criterion_Key__c)) {
                criterionIdsByKey.put(criterion.Criterion_Key__c, new List<Id>());
            }
            criterionIdsByKey.get(criterion.Criterion_Key__c).add(criterion.Id);
        }

        if (templateId == null || criterionIdsByKey.isEmpty()) {
            return maxByCriterionId;
        }

        List<Evaluation_Template_Criterion__c> templateCriteria = [
            SELECT Criterion_Key__c, Max_Score__c
            FROM Evaluation_Template_Criterion__c
            WHERE Evaluation_Template__c = :templateId
            AND Criterion_Key__c IN :criterionIdsByKey.keySet()
        ];

        for (Evaluation_Template_Criterion__c templateCriterion : templateCriteria) {
            if (!criterionIdsByKey.containsKey(templateCriterion.Criterion_Key__c)) {
                continue;
            }
            Integer maxScore = templateCriterion.Max_Score__c == null
                ? 5
                : templateCriterion.Max_Score__c.intValue();
            for (Id criterionId : criterionIdsByKey.get(templateCriterion.Criterion_Key__c)) {
                maxByCriterionId.put(criterionId, maxScore);
            }
        }

        return maxByCriterionId;
    }

    private static String normalizeMode(String mode) {
        if (mode == AI_MODE_FILL_BLANKS) {
            return AI_MODE_FILL_BLANKS;
        }
        return AI_MODE_OVERWRITE_ALL;
    }

    private static Boolean shouldFillBlank(Evaluation_Criterion_Score__c criterion) {
        return criterion.Suggested_Score__c == null || String.isBlank(criterion.Rationale__c);
    }

    private static String normalizeEvidenceStorageText(String rawEvidence) {
        if (String.isBlank(rawEvidence)) {
            return null;
        }

        String normalized = rawEvidence.replace('\r\n', '\n').replace('\r', '\n').trim();
        if (String.isBlank(normalized)) {
            return null;
        }

        if (normalized.length() > MAX_EVIDENCE_STORAGE_LENGTH) {
            normalized = normalized.substring(0, MAX_EVIDENCE_STORAGE_LENGTH);
        }
        return normalized;
    }

    private static AISuggestionResult toAiSuggestionResult(Id criterionId, Map<String, Object> suggestion) {
        AISuggestionResult result = new AISuggestionResult();
        result.criterionScoreId = criterionId;
        result.skipped = false;
        result.source = suggestion == null ? null : (String) suggestion.get('source');
        result.warning = suggestion == null ? null : (String) suggestion.get('warning');
        Object scoreRaw = suggestion == null ? null : suggestion.get('suggestedScore');
        result.suggestedScore = scoreRaw == null ? null : Integer.valueOf(String.valueOf(scoreRaw));
        result.suggestedRationale = suggestion == null ? null : (String) suggestion.get('suggestedRationale');
        result.citations = coerceCitationList(suggestion == null ? null : suggestion.get('citations'));
        return result;
    }

    private static List<String> extractAndNormalizeCitations(Map<String, Object> scoreMap) {
        if (scoreMap == null) {
            return new List<String>();
        }

        Object rawCitations = null;
        if (scoreMap.containsKey('citations')) {
            rawCitations = scoreMap.get('citations');
        } else if (scoreMap.containsKey('evidence')) {
            rawCitations = scoreMap.get('evidence');
        } else if (scoreMap.containsKey('supportingEvidence')) {
            rawCitations = scoreMap.get('supportingEvidence');
        } else if (scoreMap.containsKey('citation')) {
            rawCitations = scoreMap.get('citation');
        }

        return coerceCitationList(rawCitations);
    }

    private static List<String> coerceCitationList(Object rawCitations) {
        List<String> normalized = new List<String>();
        if (rawCitations == null) {
            return normalized;
        }

        try {
            if (rawCitations instanceof List<Object>) {
                for (Object item : (List<Object>) rawCitations) {
                    addCitationIfValid(normalized, item);
                    if (normalized.size() >= MAX_CITATION_COUNT) {
                        break;
                    }
                }
                return normalized;
            }
            addCitationIfValid(normalized, rawCitations);
        } catch (Exception ex) {
            return new List<String>();
        }

        return normalized;
    }

    private static void addCitationIfValid(List<String> target, Object rawItem) {
        if (target == null || rawItem == null || target.size() >= MAX_CITATION_COUNT) {
            return;
        }

        String candidate;
        if (rawItem instanceof String) {
            candidate = (String) rawItem;
        } else if (rawItem instanceof Map<String, Object>) {
            Map<String, Object> itemMap = (Map<String, Object>) rawItem;
            if (itemMap.containsKey('text')) {
                candidate = String.valueOf(itemMap.get('text'));
            } else if (itemMap.containsKey('value')) {
                candidate = String.valueOf(itemMap.get('value'));
            } else if (itemMap.containsKey('quote')) {
                candidate = String.valueOf(itemMap.get('quote'));
            } else {
                candidate = String.valueOf(rawItem);
            }
        } else {
            candidate = String.valueOf(rawItem);
        }

        if (String.isBlank(candidate)) {
            return;
        }

        String trimmed = candidate.trim();
        if (String.isBlank(trimmed)) {
            return;
        }

        if (trimmed.length() > MAX_CITATION_LENGTH) {
            trimmed = trimmed.substring(0, MAX_CITATION_LENGTH);
        }
        target.add(trimmed.escapeHtml4());
    }

}