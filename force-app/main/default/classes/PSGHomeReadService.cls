public with sharing class PSGHomeReadService {
    public static PublicSectorGrantmakingReadController.HomeDashboardData getHomeDashboardData() {
        PublicSectorGrantmakingReadController.HomeDashboardData out =
            new PublicSectorGrantmakingReadController.HomeDashboardData();
        out.securityFiltered = false;

        Schema.DescribeSObjectResult fundingDescribe = PSGQueryAccessUtil.safeDescribeLookup('FundingOpportunity');
        Schema.DescribeSObjectResult appFormDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationForm');
        Schema.DescribeSObjectResult evaluationDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationFormEvaluation');
        Schema.DescribeSObjectResult templateDescribe = PSGQueryAccessUtil.safeDescribeLookup('Evaluation_Template__c');
        Schema.DescribeSObjectResult criterionDescribe = PSGQueryAccessUtil.safeDescribeLookup('Criterion_Library__c');

        out.activeFundingOpportunities = safeCount('FundingOpportunity', 'Status = \'Active\'', fundingDescribe);
        out.openApplicationForms = safeCount('ApplicationForm', null, appFormDescribe);
        out.inReviewEvaluations = safeCount('ApplicationFormEvaluation', 'Status = \'In Progress\'', evaluationDescribe);
        out.publishedTemplates = safeCount('Evaluation_Template__c', 'Status__c = \'Published\'', templateDescribe);
        out.activeCriteria = safeCount('Criterion_Library__c', 'Active__c = true', criterionDescribe);

        out.tableauEmbedUrl = String.isBlank(Label.PSG_Tableau_Home_Dashboard_URL)
            ? null
            : Label.PSG_Tableau_Home_Dashboard_URL.trim();

        PublicSectorGrantmakingReadController.WorkspaceResponse recentApps =
            PSGWorkspaceReadService.getWorkspaceRows('applicationForms', null, 5, 1, 'primaryDate', 'desc');
        PublicSectorGrantmakingReadController.WorkspaceResponse recentEvaluations =
            PSGWorkspaceReadService.getWorkspaceRows('evaluations', null, 5, 1, 'primaryDate', 'desc');

        out.recentApplicationForms = recentApps.rows;
        out.recentEvaluations = recentEvaluations.rows;
        out.securityFiltered = recentApps.securityFiltered || recentEvaluations.securityFiltered;

        out.helperNote = 'Counts and rows use read-only queries from core grantmaking objects.';
        if (out.securityFiltered) {
            out.helperNote += ' Some values are hidden due to field-level security.';
        }
        return out;
    }

    private static Integer safeCount(
        String objectApiName,
        String whereClause,
        Schema.DescribeSObjectResult objectDescribe
    ) {
        if (objectDescribe == null || !objectDescribe.isAccessible()) {
            return 0;
        }
        try {
            String soql = 'SELECT COUNT() FROM ' + objectApiName;
            if (!String.isBlank(whereClause)) {
                soql += ' WHERE ' + whereClause;
            }
            return (Integer) Database.countQuery(soql);
        } catch (Exception ex) {
            return 0;
        }
    }
}
