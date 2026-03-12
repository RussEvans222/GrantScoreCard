/*
Grant Intake Application Service

Handles draft-save and submit orchestration for OmniStudio intake payloads.
*/
public with sharing class GrantIntakeAppService {
    @TestVisible
    private class IntakePayload {
        Id applicationFormId;
        Id fundingOpportunityId;
        String title;
        String purpose;
        Decimal requestedAmount;
        String stage;
        String email;
        String phone;
        Id contactId;
    }

    public static GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse saveDraft(
        GrantIntakeOrchestrationGateway.GrantApplicationDraftRequest requestData
    ) {
        GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse response =
            new GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse();
        response.success = false;
        response.status = 'Error';

        IntakePayload payload = parsePayload(requestData == null ? null : requestData.applicationPayload);
        if (payload == null) {
            response.message = 'Invalid or empty draft payload.';
            return response;
        }

        Schema.DescribeSObjectResult appDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationForm');
        if (appDescribe == null || !appDescribe.isAccessible()) {
            response.message = 'ApplicationForm is not accessible.';
            return response;
        }

        SObject appRecord;
        Boolean isUpdate = payload.applicationFormId != null;
        if (isUpdate) {
            if (!appDescribe.isUpdateable()) {
                response.message = 'No update access to ApplicationForm.';
                return response;
            }
            appRecord = newSObject('ApplicationForm');
            appRecord.put('Id', payload.applicationFormId);
        } else {
            if (!appDescribe.isCreateable()) {
                response.message = 'No create access to ApplicationForm.';
                return response;
            }
            appRecord = newSObject('ApplicationForm');
        }

        Map<String, Schema.SObjectField> appFields = appDescribe.fields.getMap();
        putIfWriteable(appRecord, appFields, 'Title', payload.title, isUpdate);
        putIfWriteable(appRecord, appFields, 'Purpose', payload.purpose, isUpdate);
        putIfWriteable(appRecord, appFields, 'RequestedAmount', payload.requestedAmount, isUpdate);
        putIfWriteable(appRecord, appFields, 'Stage', resolveDraftStage(appFields), isUpdate);
        putIfWriteable(appRecord, appFields, 'Email', payload.email, isUpdate);
        putIfWriteable(appRecord, appFields, 'Phone', payload.phone, isUpdate);
        putIfWriteable(appRecord, appFields, 'ContactId', payload.contactId, isUpdate);

        Database.SaveResult appSave = isUpdate
            ? Database.update(appRecord, false)
            : Database.insert(appRecord, false);

        if (appSave == null || !appSave.isSuccess()) {
            response.message = firstError(appSave, 'Unable to save application draft.');
            return response;
        }

        Id savedApplicationId = (Id) appSave.getId();
        saveFundingOpportunityRelation(savedApplicationId, payload.fundingOpportunityId);

        response.success = true;
        response.status = 'Draft Saved';
        response.draftApplicationId = String.valueOf(savedApplicationId);
        response.message = 'Application draft saved successfully.';
        return response;
    }

    public static GrantIntakeOrchestrationGateway.GrantSubmissionResponse submit(
        GrantIntakeOrchestrationGateway.GrantSubmissionRequest requestData
    ) {
        GrantIntakeOrchestrationGateway.GrantSubmissionResponse response =
            new GrantIntakeOrchestrationGateway.GrantSubmissionResponse();
        response.success = false;
        response.status = 'Error';

        IntakePayload payload = parsePayload(requestData == null ? null : requestData.applicationPayload);
        if (payload == null || payload.applicationFormId == null) {
            response.message = 'Submission payload must include application id.';
            return response;
        }

        Schema.DescribeSObjectResult appDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationForm');
        if (appDescribe == null || !appDescribe.isAccessible() || !appDescribe.isUpdateable()) {
            response.message = 'No access to submit ApplicationForm records.';
            return response;
        }

        SObject appUpdate = newSObject('ApplicationForm');
        appUpdate.put('Id', payload.applicationFormId);
        Map<String, Schema.SObjectField> appFields = appDescribe.fields.getMap();
        putIfWriteable(appUpdate, appFields, 'Stage', resolveSubmittedStage(appFields), true);

        Database.SaveResult saveResult = Database.update(appUpdate, false);
        if (saveResult == null || !saveResult.isSuccess()) {
            response.message = firstError(saveResult, 'Unable to submit application.');
            return response;
        }

        response.success = true;
        response.status = 'Submitted';
        response.applicationId = String.valueOf(payload.applicationFormId);
        response.message = 'Application submitted successfully.';
        return response;
    }

    private static void saveFundingOpportunityRelation(Id applicationId, Id fundingOpportunityId) {
        if (applicationId == null || fundingOpportunityId == null) {
            return;
        }
        Schema.DescribeSObjectResult relationDescribe = PSGQueryAccessUtil.safeDescribeLookup('ApplicationFormRelation');
        if (relationDescribe == null || !relationDescribe.isAccessible()) {
            return;
        }
        Map<String, Schema.SObjectField> relationFields = relationDescribe.fields.getMap();
        if (!relationFields.containsKey('ApplicationFormId') || !relationFields.containsKey('ReferenceRecordId')) {
            return;
        }

        Id existingRelationId = null;
        try {
            List<ApplicationFormRelation> existing = [
                SELECT Id
                FROM ApplicationFormRelation
                WHERE ApplicationFormId = :applicationId
                AND ReferenceObjectName = 'FundingOpportunity'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                existingRelationId = existing[0].Id;
            }
        } catch (Exception ignored) {
            return;
        }

        SObject relationRecord = newSObject('ApplicationFormRelation');
        Boolean isUpdate = existingRelationId != null;
        if (isUpdate) {
            if (!relationDescribe.isUpdateable()) {
                return;
            }
            relationRecord.put('Id', existingRelationId);
        } else {
            if (!relationDescribe.isCreateable()) {
                return;
            }
        }

        putIfWriteable(relationRecord, relationFields, 'ApplicationFormId', applicationId, isUpdate);
        putIfWriteable(relationRecord, relationFields, 'ReferenceRecordId', fundingOpportunityId, isUpdate);
        putIfWriteable(relationRecord, relationFields, 'ReferenceObjectName', 'FundingOpportunity', isUpdate);

        if (isUpdate) {
            Database.update(relationRecord, false);
        } else {
            Database.insert(relationRecord, false);
        }
    }

    @TestVisible
    private static IntakePayload parsePayload(String rawPayload) {
        if (String.isBlank(rawPayload)) {
            return null;
        }
        try {
            Object deserialized = JSON.deserializeUntyped(rawPayload);
            if (!(deserialized instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> payload = (Map<String, Object>) deserialized;
            IntakePayload out = new IntakePayload();
            out.fundingOpportunityId = parseId(getNodeValue(payload, new List<String>{ 'context', 'fundingOpportunityId' }));
            out.applicationFormId = parseId(
                coalesce(
                    getNodeValue(payload, new List<String>{ 'application', 'applicationFormId' }),
                    getNodeValue(payload, new List<String>{ 'submission', 'submittedApplicationId' }),
                    getNodeValue(payload, new List<String>{ 'applicationId' })
                )
            );
            out.title = asString(getNodeValue(payload, new List<String>{ 'application', 'title' }));
            out.purpose = asString(getNodeValue(payload, new List<String>{ 'application', 'purpose' }));
            out.requestedAmount = asDecimal(getNodeValue(payload, new List<String>{ 'application', 'requestedAmount' }));
            out.stage = asString(getNodeValue(payload, new List<String>{ 'application', 'stage' }));
            out.email = asString(getNodeValue(payload, new List<String>{ 'applicant', 'email' }));
            out.phone = asString(getNodeValue(payload, new List<String>{ 'applicant', 'phone' }));
            out.contactId = parseId(getNodeValue(payload, new List<String>{ 'applicant', 'contactId' }));
            return out;
        } catch (Exception ex) {
            return null;
        }
    }

    private static SObject newSObject(String objectApiName) {
        Schema.DescribeSObjectResult describe = PSGQueryAccessUtil.safeDescribeLookup(objectApiName);
        return describe == null ? null : describe.getSObjectType().newSObject();
    }

    private static String resolveDraftStage(Map<String, Schema.SObjectField> appFields) {
        if (appFields == null || !appFields.containsKey('Stage')) {
            return null;
        }
        return picklistValue(appFields.get('Stage').getDescribe().getPicklistValues(), new List<String>{ 'Draft', 'In Progress' });
    }

    private static String resolveSubmittedStage(Map<String, Schema.SObjectField> appFields) {
        if (appFields == null || !appFields.containsKey('Stage')) {
            return null;
        }
        return picklistValue(
            appFields.get('Stage').getDescribe().getPicklistValues(),
            new List<String>{ 'Submitted', 'Complete', 'Completed' }
        );
    }

    private static String picklistValue(List<Schema.PicklistEntry> values, List<String> preferredValues) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        if (preferredValues != null) {
            for (String preferred : preferredValues) {
                for (Schema.PicklistEntry option : values) {
                    if (option != null && option.isActive() && option.getValue() == preferred) {
                        return option.getValue();
                    }
                }
            }
        }
        for (Schema.PicklistEntry option : values) {
            if (option != null && option.isActive()) {
                return option.getValue();
            }
        }
        return null;
    }

    private static void putIfWriteable(
        SObject target,
        Map<String, Schema.SObjectField> fields,
        String fieldApiName,
        Object value,
        Boolean isUpdate
    ) {
        if (target == null || fields == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }
        if (!fields.containsKey(fieldApiName)) {
            return;
        }
        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();
        Boolean canWrite = isUpdate ? describe.isUpdateable() : describe.isCreateable();
        if (canWrite) {
            target.put(fieldApiName, value);
        }
    }

    private static String firstError(Database.SaveResult result, String fallback) {
        if (result != null && result.getErrors() != null && !result.getErrors().isEmpty()) {
            Database.Error first = result.getErrors()[0];
            return String.isBlank(first.getMessage()) ? fallback : first.getMessage();
        }
        return fallback;
    }

    private static Object getNodeValue(Map<String, Object> source, List<String> path) {
        if (source == null || path == null || path.isEmpty()) {
            return null;
        }
        Object current = source;
        for (String key : path) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(key);
        }
        return current;
    }

    private static Object coalesce(Object first, Object second, Object third) {
        if (first != null) {
            return first;
        }
        if (second != null) {
            return second;
        }
        return third;
    }

    private static String asString(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value);
        return String.isBlank(text) ? null : text.trim();
    }

    private static Decimal asDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            if (value instanceof Decimal) {
                return (Decimal) value;
            }
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id parseId(Object value) {
        String idText = asString(value);
        if (String.isBlank(idText)) {
            return null;
        }
        try {
            return (Id) idText;
        } catch (Exception ex) {
            return null;
        }
    }
}