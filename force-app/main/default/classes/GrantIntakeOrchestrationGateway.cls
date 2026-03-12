/*
OmniStudio Intake Contract Gateway

Purpose:
- Provide a stable contract layer for OmniScript / Integration Procedure callers.
- Keep orchestration contracts versioned while backend services evolve.

This class intentionally contains contract methods and delegation only.
Business logic for persistence/orchestration will be added in future phases.
*/
public with sharing class GrantIntakeOrchestrationGateway {
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
