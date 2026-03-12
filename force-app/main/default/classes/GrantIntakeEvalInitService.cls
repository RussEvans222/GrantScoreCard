/*
Grant Intake Evaluation Init Service

Creates an ApplicationFormEvaluation record after submission using the
FundingOpportunity -> Evaluation_Template__c link.
*/
public with sharing class GrantIntakeEvalInitService {
    private static final String AFE_IN_PROGRESS_STATUS = 'In Progress';

    public static GrantIntakeOrchestrationGateway.EvaluationInitializationResponse initializeEvaluation(
        GrantIntakeOrchestrationGateway.EvaluationInitializationRequest requestData
    ) {
        GrantIntakeOrchestrationGateway.EvaluationInitializationResponse response =
            new GrantIntakeOrchestrationGateway.EvaluationInitializationResponse();
        response.success = false;
        response.status = 'Error';

        Id applicationId = requestData == null ? null : requestData.applicationId;
        if (applicationId == null) {
            response.message = 'Application id is required.';
            return response;
        }

        Schema.DescribeSObjectResult afeDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationFormEvaluation');
        if (afeDescribe == null || !afeDescribe.isAccessible() || !afeDescribe.isCreateable()) {
            response.message = 'ApplicationFormEvaluation is not createable for this user.';
            return response;
        }

        Id templateId = resolveTemplateId(applicationId);
        if (templateId == null) {
            response.message = 'No published evaluation template link was found for the selected application.';
            return response;
        }

        SObject afeRecord = afeDescribe.getSObjectType().newSObject();
        Map<String, Schema.SObjectField> afeFields = afeDescribe.fields.getMap();
        putIfCreateable(afeRecord, afeFields, 'ApplicationFormId', applicationId);
        putIfCreateable(afeRecord, afeFields, 'Evaluation_Template__c', templateId);
        putIfCreateable(afeRecord, afeFields, 'Date', Date.today());
        putIfCreateable(afeRecord, afeFields, 'Status', resolveStatusValue(afeFields));

        Database.SaveResult insertResult = Database.insert(afeRecord, false);
        if (insertResult == null || !insertResult.isSuccess()) {
            response.message = firstError(insertResult, 'Unable to initialize evaluation.');
            return response;
        }

        response.success = true;
        response.status = 'Initialized';
        response.evaluationId = (Id) insertResult.getId();
        response.message = 'Evaluation record initialized.';
        return response;
    }

    private static Id resolveTemplateId(Id applicationId) {
        Schema.DescribeSObjectResult relationDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationFormRelation');
        if (relationDescribe == null || !relationDescribe.isAccessible()) {
            return null;
        }

        List<ApplicationFormRelation> relations = new List<ApplicationFormRelation>();
        try {
            relations = [
                SELECT ReferenceRecordId
                FROM ApplicationFormRelation
                WHERE ApplicationFormId = :applicationId
                AND ReferenceObjectName = 'FundingOpportunity'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } catch (Exception ignored) {
            return null;
        }
        if (relations.isEmpty() || relations[0].ReferenceRecordId == null) {
            return null;
        }

        Schema.DescribeSObjectResult fundingDescribe = PSGQueryAccessUtil.safeDescribeLookup('FundingOpportunity');
        if (fundingDescribe == null || !fundingDescribe.isAccessible()) {
            return null;
        }
        Map<String, Schema.SObjectField> fundingFields = fundingDescribe.fields.getMap();
        if (!fundingFields.containsKey('Evaluation_Template__c')) {
            return null;
        }

        Id fundingOpportunityId = relations[0].ReferenceRecordId;
        try {
            List<SObject> opportunities = Database.query(
                'SELECT Id, Evaluation_Template__c FROM FundingOpportunity WHERE Id = :fundingOpportunityId LIMIT 1'
            );
            if (opportunities.isEmpty()) {
                return null;
            }
            return (Id) opportunities[0].get('Evaluation_Template__c');
        } catch (Exception ex) {
            return null;
        }
    }

    private static void putIfCreateable(
        SObject target,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName,
        Object value
    ) {
        if (target == null || fields == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }
        if (!fields.containsKey(fieldApiName)) {
            return;
        }
        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();
        if (describe.isCreateable()) {
            target.put(fieldApiName, value);
        }
    }

    private static String resolveStatusValue(Map<String, Schema.SObjectField> afeFields) {
        if (afeFields == null || !afeFields.containsKey('Status')) {
            return null;
        }
        List<Schema.PicklistEntry> values = afeFields.get('Status').getDescribe().getPicklistValues();
        for (Schema.PicklistEntry option : values) {
            if (option != null && option.isActive() && option.getValue() == AFE_IN_PROGRESS_STATUS) {
                return option.getValue();
            }
        }
        for (Schema.PicklistEntry option : values) {
            if (option != null && option.isActive()) {
                return option.getValue();
            }
        }
        return null;
    }

    private static String firstError(Database.SaveResult result, String fallback) {
        if (result != null && result.getErrors() != null && !result.getErrors().isEmpty()) {
            Database.Error first = result.getErrors()[0];
            return String.isBlank(first.getMessage()) ? fallback : first.getMessage();
        }
        return fallback;
    }
}
