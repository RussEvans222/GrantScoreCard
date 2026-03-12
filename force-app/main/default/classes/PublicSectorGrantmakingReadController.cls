/*
Public Sector Grantmaking Read Controller

Thin facade for the workspace LWCs. This class intentionally keeps
public Apex method signatures stable while delegating all read/query
logic to dedicated services.
*/
public with sharing class PublicSectorGrantmakingReadController {
    @TestVisible
    private static Map<String, Set<String>> TEST_FORCED_REMOVED_FIELDS_BY_OBJECT;

    public class HomeDashboardData {
        @AuraEnabled public Integer activeFundingOpportunities;
        @AuraEnabled public Integer openApplicationForms;
        @AuraEnabled public Integer inReviewEvaluations;
        @AuraEnabled public Integer publishedTemplates;
        @AuraEnabled public Integer activeCriteria;
        @AuraEnabled public Boolean securityFiltered;
        @AuraEnabled public String tableauEmbedUrl;
        @AuraEnabled public String helperNote;
        @AuraEnabled public List<WorkspaceRow> recentApplicationForms;
        @AuraEnabled public List<WorkspaceRow> recentEvaluations;
    }

    public class WorkspaceResponse {
        @AuraEnabled public String workspaceKey;
        @AuraEnabled public String title;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Boolean securityFiltered;
        @AuraEnabled public String helperNote;
        @AuraEnabled public List<WorkspaceRow> rows;
    }

    public class WorkspaceRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public String recordName;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String primaryDate;
        @AuraEnabled public String secondaryValue;
        @AuraEnabled public String detail;
    }

    @AuraEnabled(cacheable=true)
    public static HomeDashboardData getHomeDashboardData() {
        syncTestOverrides();
        return PSGHomeReadService.getHomeDashboardData();
    }

    @AuraEnabled(cacheable=true)
    public static WorkspaceResponse getWorkspaceRows(
        String workspaceKey,
        String searchText,
        Integer pageSize,
        Integer pageNumber,
        String sortBy,
        String sortDirection
    ) {
        syncTestOverrides();
        return PSGWorkspaceReadService.getWorkspaceRows(
            workspaceKey,
            searchText,
            pageSize,
            pageNumber,
            sortBy,
            sortDirection
        );
    }

    private static void syncTestOverrides() {
        if (Test.isRunningTest()) {
            PSGQueryAccessUtil.TEST_FORCED_REMOVED_FIELDS_BY_OBJECT = TEST_FORCED_REMOVED_FIELDS_BY_OBJECT;
        }
    }

    @TestVisible
    private static void clearTestOverrides() {
        TEST_FORCED_REMOVED_FIELDS_BY_OBJECT = null;
        PSGQueryAccessUtil.clearTestOverrides();
    }
}