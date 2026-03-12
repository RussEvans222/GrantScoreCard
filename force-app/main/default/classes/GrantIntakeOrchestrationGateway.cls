/*
OmniStudio Intake Contract Gateway

Purpose:
- Provide a stable contract layer for OmniScript / Integration Procedure callers.
- Keep orchestration contracts versioned while backend services evolve.

This class intentionally contains contract methods and delegation only.
Business logic for persistence/orchestration will be added in future phases.
*/
public with sharing class GrantIntakeOrchestrationGateway implements System.Callable {
    private static final String FUNDING_ANALYSIS_TEMPLATE = 'Grant_Project_Funding_Analysis';

    public interface GatewayDelegate {
        FundingFinderResponse getFundingFinderResults(FundingFinderRequest requestData);
        GrantApplicationDraftResponse saveDraftApplication(GrantApplicationDraftRequest requestData);
        GrantSubmissionResponse submitApplication(GrantSubmissionRequest requestData);
        EvaluationInitializationResponse initializeEvaluation(EvaluationInitializationRequest requestData);
    }

    @TestVisible
    private static GatewayDelegate delegateOverride;

    public class FundingFinderRequest {
        @AuraEnabled public String searchText;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public String sortBy;
        @AuraEnabled public String sortDirection;
    }

    public class FundingFinderRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public String status;
        @AuraEnabled public String primaryDate;
        @AuraEnabled public String detail;
    }

    public class FundingFinderResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean securityFiltered;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public List<FundingFinderRow> rows;
    }

    public class AnalyzeProjectResponse {
        @AuraEnabled public String aiSummary;
        @AuraEnabled public List<String> recommendedFundingTypes;
        @AuraEnabled public List<String> keywords;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public List<FundingOpportunityRecommendation> fundingOpportunities;
    }

    public class FundingOpportunityRecommendation {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id evaluationTemplateId;
        @AuraEnabled public Decimal relevanceScore;
        @AuraEnabled public String ProgramArea;
        @AuraEnabled public String EligibilitySummary;
        @AuraEnabled public Decimal MaxAwardAmount;
        @AuraEnabled public Date OpenDate;
        @AuraEnabled public Date CloseDate;
        @AuraEnabled public String RelevanceTier;
        @AuraEnabled public String RelevanceLabel;
        @AuraEnabled public String RelevanceColor;
    }

    public class GrantApplicationDraftRequest {
        @AuraEnabled public String applicationPayload;
    }

    public class GrantApplicationDraftResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String draftApplicationId;
        @AuraEnabled public String status;
    }

    public class GrantSubmissionRequest {
        @AuraEnabled public String applicationPayload;
    }

    public class GrantSubmissionResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String status;
    }

    public class EvaluationInitializationRequest {
        @AuraEnabled public Id applicationId;
    }

    public class EvaluationInitializationResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id evaluationId;
        @AuraEnabled public String status;
    }

    public Object call(String action, Map<String, Object> args) {
        String normalizedAction = String.isBlank(action) ? '' : action.trim();

        if (normalizedAction == 'analyzeProject') {
            return analyzeProject(extractStringArg(args, 'searchText'));
        }
        if (normalizedAction == 'analyzeProjectForFunding') {
            return analyzeProjectForFunding(extractStringArg(args, 'searchText'));
        }
        if (normalizedAction == 'getFundingFinderResults') {
            return getFundingFinderResults(extractStringArg(args, 'searchText'));
        }
        if (normalizedAction == 'saveDraftApplication') {
            return saveDraftApplication(extractStringArg(args, 'applicationPayload'));
        }
        if (normalizedAction == 'submitApplication') {
            return submitApplication(extractStringArg(args, 'applicationPayload'));
        }
        if (normalizedAction == 'initializeEvaluation') {
            return initializeEvaluation(extractStringArg(args, 'applicationId'));
        }

        throw new AuraHandledException('Unsupported action for GrantIntakeOrchestrationGateway: ' + normalizedAction);
    }

    @AuraEnabled
    public static FundingFinderResponse getFundingFinderResults(String searchText) {
        FundingFinderRequest requestData = new FundingFinderRequest();
        requestData.searchText = searchText;
        requestData.pageSize = 25;
        requestData.pageNumber = 1;
        requestData.sortBy = 'primaryDate';
        requestData.sortDirection = 'desc';
        return getDelegate().getFundingFinderResults(requestData);
    }

    @AuraEnabled
    public static AnalyzeProjectResponse analyzeProject(String searchText) {
        AnalyzeProjectResponse response = new AnalyzeProjectResponse();
        String normalizedSearchText = String.isBlank(searchText) ? '' : searchText.trim();

        try {
            response = invokePromptBuilderAnalysis(normalizedSearchText);
        } catch (Exception ex) {
            response = buildFallbackAnalysis(normalizedSearchText);
        }

        return response;
    }

    @AuraEnabled
    public static AnalyzeProjectResponse analyzeProjectForFunding(String searchText) {
        return analyzeProject(searchText);
    }

    private static AnalyzeProjectResponse invokePromptBuilderAnalysis(String searchText) {
        String rawOutput = invokeFundingPromptTemplate(searchText);
        if (String.isBlank(rawOutput)) {
            return buildFallbackAnalysis(searchText);
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawOutput);

        AnalyzeProjectResponse response = new AnalyzeProjectResponse();
        response.aiSummary = normalizeString(parsed.get('summary'));
        response.recommendedFundingTypes = toStringList(parsed.get('recommendedFundingTypes'));
        response.keywords = toStringList(parsed.get('keywords'));
        response.confidenceScore = toDecimalValue(parsed.get('confidenceScore'));

        if (String.isBlank(response.aiSummary)) {
            response.aiSummary = 'Analysis completed. Add more detail to improve funding recommendations.';
        }
        if (response.recommendedFundingTypes == null) {
            response.recommendedFundingTypes = new List<String>();
        }
        if (response.keywords == null) {
            response.keywords = new List<String>();
        }
        if (response.confidenceScore == null) {
            response.confidenceScore = 0.55;
        }
        response.fundingOpportunities = getRelatedFundingOpportunities(
            searchText,
            response.recommendedFundingTypes,
            response.keywords
        );
        return response;
    }

    private static String invokeFundingPromptTemplate(String projectDescription) {
        try {
            Map<String, ConnectApi.WrappedValue> wrappedInputParams = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue wrappedDescription = new ConnectApi.WrappedValue();
            wrappedDescription.value = projectDescription;
            wrappedInputParams.put('projectDescription', wrappedDescription);

            ConnectApi.EinsteinPromptTemplateGenerationsInput generationInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            generationInput.inputParams = wrappedInputParams;
            generationInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            generationInput.additionalConfig.applicationName = 'PromptBuilderPreview';
            generationInput.isPreview = false;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationOutput =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(FUNDING_ANALYSIS_TEMPLATE, generationInput);
            if (generationOutput == null || generationOutput.generations == null || generationOutput.generations.isEmpty()) {
                return null;
            }

            ConnectApi.EinsteinLLMGenerationItemOutput firstGeneration = generationOutput.generations[0];
            return firstGeneration == null ? null : normalizeString(firstGeneration.text);
        } catch (Exception ex) {
            return null;
        }
    }

    private static AnalyzeProjectResponse buildFallbackAnalysis(String searchText) {
        FundingFinderResponse finderResponse = getFundingFinderResults(searchText);
        AnalyzeProjectResponse response = new AnalyzeProjectResponse();

        Integer recommendationCount = finderResponse == null || finderResponse.rows == null
            ? 0
            : Math.min(3, finderResponse.rows.size());

        List<String> recommendedNames = new List<String>();
        if (finderResponse != null && finderResponse.rows != null) {
            for (Integer i = 0; i < recommendationCount; i++) {
                if (!String.isBlank(finderResponse.rows[i].recordName)) {
                    recommendedNames.add(finderResponse.rows[i].recordName);
                }
            }
        }

        response.aiSummary = recommendationCount > 0
            ? 'Based on the project description, we identified matching active funding opportunities.'
            : 'Analysis completed. Add more detail to improve funding recommendations.';
        response.recommendedFundingTypes = recommendedNames;
        response.keywords = extractKeywordFallback(searchText);
        response.confidenceScore = recommendationCount > 0 ? 0.82 : 0.55;
        response.fundingOpportunities = getRelatedFundingOpportunities(
            searchText,
            response.recommendedFundingTypes,
            response.keywords
        );
        return response;
    }

    @AuraEnabled
    public static GrantApplicationDraftResponse saveDraftApplication(String applicationPayload) {
        GrantApplicationDraftRequest requestData = new GrantApplicationDraftRequest();
        requestData.applicationPayload = applicationPayload;
        return getDelegate().saveDraftApplication(requestData);
    }

    @AuraEnabled
    public static GrantSubmissionResponse submitApplication(String applicationPayload) {
        GrantSubmissionRequest requestData = new GrantSubmissionRequest();
        requestData.applicationPayload = applicationPayload;
        return getDelegate().submitApplication(requestData);
    }

    @AuraEnabled
    public static EvaluationInitializationResponse initializeEvaluation(String applicationId) {
        EvaluationInitializationRequest requestData = new EvaluationInitializationRequest();
        if (!String.isBlank(applicationId)) {
            try {
                requestData.applicationId = (Id) applicationId;
            } catch (Exception ex) {
                requestData.applicationId = null;
            }
        }
        return getDelegate().initializeEvaluation(requestData);
    }

    private static GatewayDelegate getDelegate() {
        return delegateOverride == null ? new DefaultGatewayDelegate() : delegateOverride;
    }

    private static String extractStringArg(Map<String, Object> args, String key) {
        if (args == null || String.isBlank(key)) {
            return null;
        }
        if (args.containsKey(key)) {
            return normalizeString(args.get(key));
        }
        if (args.containsKey('input')) {
            Object nestedInput = args.get('input');
            if (nestedInput instanceof Map<String, Object>) {
                Map<String, Object> nestedMap = (Map<String, Object>) nestedInput;
                if (nestedMap.containsKey(key)) {
                    return normalizeString(nestedMap.get(key));
                }
            }
        }
        return null;
    }

    private static String normalizeString(Object value) {
        if (value == null) {
            return null;
        }
        String asText = String.valueOf(value);
        return String.isBlank(asText) ? null : asText.trim();
    }

    private static Decimal toDecimalValue(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<String> toStringList(Object value) {
        List<String> parsedValues = new List<String>();
        if (value == null) {
            return parsedValues;
        }

        if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                String normalized = normalizeString(item);
                if (!String.isBlank(normalized)) {
                    parsedValues.add(normalized);
                }
            }
            return parsedValues;
        }

        String asText = normalizeString(value);
        if (String.isBlank(asText)) {
            return parsedValues;
        }

        for (String token : asText.split(';|,')) {
            String normalized = token == null ? null : token.trim();
            if (!String.isBlank(normalized)) {
                parsedValues.add(normalized);
            }
        }
        return parsedValues;
    }

    private static List<String> extractKeywordFallback(String searchText) {
        List<String> results = new List<String>();
        if (String.isBlank(searchText)) {
            return results;
        }
        Set<String> seen = new Set<String>();
        for (String token : searchText.toLowerCase().split('[^a-z0-9]+')) {
            if (String.isBlank(token) || token.length() < 4) {
                continue;
            }
            if (!seen.contains(token)) {
                seen.add(token);
                results.add(token);
            }
            if (results.size() >= 6) {
                break;
            }
        }
        return results;
    }

    private class ScoredFundingOpportunity implements Comparable {
        public FundingOpportunity source;
        public Integer score;

        public Integer compareTo(Object otherObject) {
            ScoredFundingOpportunity other = (ScoredFundingOpportunity) otherObject;
            Integer thisScore = score == null ? 0 : score;
            Integer otherScore = other == null || other.score == null ? 0 : other.score;
            if (thisScore == otherScore) {
                String thisName = source == null || String.isBlank(source.Name) ? '' : source.Name;
                String otherName = other == null || other.source == null || String.isBlank(other.source.Name)
                    ? ''
                    : other.source.Name;
                return thisName.toLowerCase().compareTo(otherName.toLowerCase());
            }
            return thisScore > otherScore ? -1 : 1;
        }
    }

    private static List<FundingOpportunityRecommendation> getRelatedFundingOpportunities(
        String projectDescription,
        List<String> recommendedFundingTypes,
        List<String> keywords
    ) {
        List<FundingOpportunityRecommendation> output = new List<FundingOpportunityRecommendation>();
        List<String> searchTerms = collectSearchTerms(projectDescription, recommendedFundingTypes, keywords);

        List<FundingOpportunity> activeOpportunities = [
            SELECT Id, Name, ProgramId, Program.Name, Evaluation_Template__c, Description, gps_Funding_Eligibility__c, MaximumFundingAmount, StartDate, EndDate
            FROM FundingOpportunity
            WHERE Status = 'Active'
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ];

        List<ScoredFundingOpportunity> scored = new List<ScoredFundingOpportunity>();
        for (FundingOpportunity opportunity : activeOpportunities) {
            Integer currentScore = scoreOpportunity(opportunity, searchTerms);
            if (currentScore > 0) {
                ScoredFundingOpportunity wrapped = new ScoredFundingOpportunity();
                wrapped.source = opportunity;
                wrapped.score = currentScore;
                scored.add(wrapped);
            }
        }
        scored.sort();

        Integer maxResults = 8;
        if (!scored.isEmpty()) {
            Integer rankedLimit = Math.min(maxResults, scored.size());
            Integer maxScore = scored[0].score == null ? 0 : scored[0].score;
            for (Integer idx = 0; idx < rankedLimit; idx++) {
                output.add(toOpportunityRecommendation(scored[idx].source, scored[idx].score, maxScore));
            }
            return output;
        }

        Integer fallbackLimit = Math.min(5, activeOpportunities.size());
        for (Integer idx = 0; idx < fallbackLimit; idx++) {
            output.add(toOpportunityRecommendation(activeOpportunities[idx], 1, 3));
        }
        return output;
    }

    private static FundingOpportunityRecommendation toOpportunityRecommendation(
        FundingOpportunity source,
        Integer rawScore,
        Integer maxScore
    ) {
        FundingOpportunityRecommendation row = new FundingOpportunityRecommendation();
        row.id = source.Id;
        row.name = source.Name;
        row.evaluationTemplateId = (Id) source.get('Evaluation_Template__c');
        row.ProgramArea = source.Program == null ? String.valueOf(source.ProgramId) : source.Program.Name;
        row.EligibilitySummary = String.isBlank(source.gps_Funding_Eligibility__c)
            ? source.Description
            : source.gps_Funding_Eligibility__c;
        row.MaxAwardAmount = source.MaximumFundingAmount;
        row.OpenDate = source.StartDate == null ? null : source.StartDate.date();
        row.CloseDate = source.EndDate == null ? null : source.EndDate.date();
        Integer normalizedMax = maxScore == null || maxScore <= 0 ? 1 : maxScore;
        Integer normalizedRaw = rawScore == null || rawScore < 0 ? 0 : rawScore;
        Integer scorePercent = Integer.valueOf(Math.round((Decimal.valueOf(normalizedRaw) / normalizedMax) * 100));
        row.relevanceScore = Decimal.valueOf(scorePercent) / 100;
        setRelevanceFields(row, scorePercent);
        return row;
    }

    private static void setRelevanceFields(FundingOpportunityRecommendation row, Integer scorePercent) {
        if (row == null) {
            return;
        }

        Integer normalizedScore = scorePercent == null ? 0 : Math.max(0, Math.min(100, scorePercent));
        if (normalizedScore >= 75) {
            row.RelevanceTier = 'High';
            row.RelevanceLabel = 'High relevance';
            row.RelevanceColor = '#1E8449';
        } else if (normalizedScore >= 45) {
            row.RelevanceTier = 'Medium';
            row.RelevanceLabel = 'Moderate relevance';
            row.RelevanceColor = '#B76E00';
        } else {
            row.RelevanceTier = 'Low';
            row.RelevanceLabel = 'Lower relevance';
            row.RelevanceColor = '#A63A3A';
        }
    }

    private static Integer scoreOpportunity(FundingOpportunity source, List<String> searchTerms) {
        if (source == null || searchTerms == null || searchTerms.isEmpty()) {
            return 0;
        }

        String corpus = String.join(
            new List<String>{
                source.Name == null ? '' : source.Name,
                source.Program == null || source.Program.Name == null ? '' : source.Program.Name,
                source.Description == null ? '' : source.Description,
                source.gps_Funding_Eligibility__c == null ? '' : source.gps_Funding_Eligibility__c
            },
            ' '
        ).toLowerCase();

        Integer score = 0;
        for (String term : searchTerms) {
            if (String.isBlank(term)) {
                continue;
            }
            String normalizedTerm = term.toLowerCase();
            if (corpus.contains(normalizedTerm)) {
                score += normalizedTerm.length() >= 8 ? 3 : 2;
            }
        }
        return score;
    }

    private static List<String> collectSearchTerms(
        String projectDescription,
        List<String> recommendedFundingTypes,
        List<String> keywords
    ) {
        List<String> terms = new List<String>();
        Set<String> seen = new Set<String>();

        if (recommendedFundingTypes != null) {
            for (String typeLabel : recommendedFundingTypes) {
                addSearchTerm(typeLabel, seen, terms, 3);
            }
        }
        if (keywords != null) {
            for (String keyword : keywords) {
                addSearchTerm(keyword, seen, terms, 3);
            }
        }
        if (!String.isBlank(projectDescription)) {
            for (String token : projectDescription.toLowerCase().split('[^a-z0-9]+')) {
                addSearchTerm(token, seen, terms, 4);
            }
        }
        return terms;
    }

    private static void addSearchTerm(String rawTerm, Set<String> seen, List<String> terms, Integer minLength) {
        if (String.isBlank(rawTerm) || seen == null || terms == null) {
            return;
        }
        String normalized = rawTerm.trim().toLowerCase();
        Integer threshold = minLength == null ? 1 : minLength;
        if (normalized.length() < threshold || seen.contains(normalized)) {
            return;
        }
        seen.add(normalized);
        terms.add(normalized);
    }

    private class DefaultGatewayDelegate implements GatewayDelegate {
        public FundingFinderResponse getFundingFinderResults(FundingFinderRequest requestData) {
            Integer pageSize = requestData == null ? 25 : requestData.pageSize;
            Integer pageNumber = requestData == null ? 1 : requestData.pageNumber;
            String sortBy = requestData == null ? 'primaryDate' : requestData.sortBy;
            String sortDirection = requestData == null ? 'desc' : requestData.sortDirection;
            String searchText = requestData == null ? null : requestData.searchText;

            PublicSectorGrantmakingReadController.WorkspaceResponse workspaceData =
                PSGWorkspaceReadService.getWorkspaceRows(
                    'fundingOpportunities',
                    searchText,
                    pageSize,
                    pageNumber,
                    sortBy,
                    sortDirection
                );

            FundingFinderResponse response = new FundingFinderResponse();
            response.success = true;
            response.message = workspaceData.helperNote;
            response.securityFiltered = workspaceData.securityFiltered;
            response.totalCount = workspaceData.totalCount;
            response.pageSize = workspaceData.pageSize;
            response.pageNumber = workspaceData.pageNumber;
            response.hasMore = workspaceData.hasMore;
            response.rows = new List<FundingFinderRow>();

            for (PublicSectorGrantmakingReadController.WorkspaceRow sourceRow : workspaceData.rows) {
                FundingFinderRow row = new FundingFinderRow();
                row.recordId = sourceRow.recordId;
                row.recordName = sourceRow.recordName;
                row.recordUrl = sourceRow.recordUrl;
                row.status = sourceRow.status;
                row.primaryDate = sourceRow.primaryDate;
                row.detail = sourceRow.detail;
                response.rows.add(row);
            }
            return response;
        }

        public GrantApplicationDraftResponse saveDraftApplication(GrantApplicationDraftRequest requestData) {
            return GrantIntakeAppService.saveDraft(requestData);
        }

        public GrantSubmissionResponse submitApplication(GrantSubmissionRequest requestData) {
            return GrantIntakeAppService.submit(requestData);
        }

        public EvaluationInitializationResponse initializeEvaluation(EvaluationInitializationRequest requestData) {
            return GrantIntakeEvalInitService.initializeEvaluation(requestData);
        }
    }
}
