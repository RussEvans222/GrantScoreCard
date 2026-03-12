public with sharing class PSGWorkspaceConfig {
    public String workspaceKey;
    public String title;
    public String objectApiName;
    public Map<String, String> columns;
    public List<String> searchFields;
    public Set<String> sortableFields;
    public String defaultSortField;
    public String defaultSortDirection;
    public String defaultWhereClause;

    public String getFieldApiName(String logicalColumnName) {
        if (columns == null || String.isBlank(logicalColumnName)) {
            return null;
        }
        return columns.get(logicalColumnName);
    }

    public static PSGWorkspaceConfig resolve(String workspaceKey) {
        String safeKey = String.isBlank(workspaceKey) ? 'fundingOpportunities' : workspaceKey;
        if (safeKey == 'applicationForms') {
            return buildConfig(
                safeKey,
                'Application Forms',
                'ApplicationForm',
                'Name',
                'Stage',
                'CreatedDate',
                'RequestedAmount',
                'Title'
            );
        }
        if (safeKey == 'evaluations') {
            return buildConfig(
                safeKey,
                'Evaluations',
                'ApplicationFormEvaluation',
                'Name',
                'Status',
                'CreatedDate',
                'Decision',
                'Recommendation'
            );
        }
        if (safeKey == 'evaluationTemplates') {
            return buildConfig(
                safeKey,
                'Evaluation Templates',
                'Evaluation_Template__c',
                findPreferredTemplateLabelField(),
                'Status__c',
                'LastModifiedDate',
                'Version__c',
                'Description__c'
            );
        }
        if (safeKey == 'criteriaLibrary') {
            return buildConfig(
                safeKey,
                'Criteria Library',
                'Criterion_Library__c',
                'Label__c',
                'Active__c',
                'LastModifiedDate',
                'DefaultWeight__c',
                'Description__c'
            );
        }

        return buildConfig(
            safeKey,
            'Funding Opportunities',
            'FundingOpportunity',
            'Name',
            'Status',
            'StartDate',
            'GrantType',
            'Description'
        );
    }

    private static PSGWorkspaceConfig buildConfig(
        String workspaceKey,
        String title,
        String objectApiName,
        String nameField,
        String statusField,
        String primaryDateField,
        String secondaryField,
        String detailField
    ) {
        PSGWorkspaceConfig cfg = new PSGWorkspaceConfig();
        cfg.workspaceKey = workspaceKey;
        cfg.title = title;
        cfg.objectApiName = objectApiName;
        cfg.columns = new Map<String, String>{
            'recordName' => nameField,
            'status' => statusField,
            'ownerName' => 'Owner.Name',
            'primaryDate' => primaryDateField,
            'secondaryValue' => secondaryField,
            'detail' => detailField
        };
        cfg.searchFields = new List<String>{ nameField, detailField };
        cfg.sortableFields = new Set<String>{ 'recordName', 'status', 'ownerName', 'primaryDate', 'secondaryValue' };
        cfg.defaultSortField = 'primaryDate';
        cfg.defaultSortDirection = 'desc';
        cfg.defaultWhereClause = null;
        return cfg;
    }

    private static String findPreferredTemplateLabelField() {
        Schema.DescribeSObjectResult describe = PSGQueryAccessUtil.safeDescribeLookup('Evaluation_Template__c');
        if (describe == null) {
            return 'Name';
        }
        Map<String, Schema.SObjectField> fields = describe.fields.getMap();
        List<String> candidates = new List<String>{
            'Display_Name__c',
            'Template_Display_Name__c',
            'User_Facing_Name__c',
            'Label__c',
            'Name'
        };
        for (String apiName : candidates) {
            if (fields.containsKey(apiName)) {
                return apiName;
            }
        }
        return 'Name';
    }
}
