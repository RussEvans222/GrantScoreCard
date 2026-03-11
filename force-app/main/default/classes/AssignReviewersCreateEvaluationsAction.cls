public with sharing class AssignReviewersCreateEvaluationsAction {
    // These statuses are treated as "closed" for dedupe so reviewers can be reassigned after completion/cancel.
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Completed', 'Cancelled' };
    private static final Integer TASK_DUE_OFFSET_DAYS = -1;

    public class Request {
        @InvocableVariable(required=true)
        public Id applicationFormId;

        @InvocableVariable(required=true)
        public Id evaluationTemplateId;

        @InvocableVariable(required=true)
        public String reviewerIds;

        @InvocableVariable
        public Date dueDate;

        @InvocableVariable
        public String comments;
    }

    public class Response {
        @InvocableVariable
        public Integer createdCount;

        @InvocableVariable
        public Integer skippedCount;

        @InvocableVariable
        public Integer taskCount;

        @InvocableVariable
        public Integer emailCount;

        @InvocableVariable
        public Boolean stageUpdated;
    }

    @InvocableMethod(label='Assign Reviewers and Create Evaluations')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response resp = new Response();
            resp.createdCount = 0;
            resp.skippedCount = 0;
            resp.taskCount = 0;
            resp.emailCount = 0;
            resp.stageUpdated = false;

            if (req == null || req.applicationFormId == null || req.evaluationTemplateId == null || String.isBlank(req.reviewerIds)) {
                responses.add(resp);
                continue;
            }

            Set<Id> reviewerIds = parseReviewerIds(req.reviewerIds);
            if (reviewerIds.isEmpty()) {
                responses.add(resp);
                continue;
            }

            // Build reviewer dedupe map first so we create only net-new open AFEs.
            Map<Id, Boolean> reviewerHasOpenAfe = new Map<Id, Boolean>();
            for (Id reviewerId : reviewerIds) {
                reviewerHasOpenAfe.put(reviewerId, false);
            }

            String existingSoql =
                'SELECT Id, EvaluatorId, Status ' +
                'FROM ApplicationFormEvaluation ' +
                'WHERE ApplicationFormId = :appFormId ' +
                'AND EvaluatorId IN :reviewerIdSet';
            Id appFormId = req.applicationFormId;
            Set<Id> reviewerIdSet = reviewerIds;
            for (SObject existingRaw : Database.query(existingSoql)) {
                Id existingEvaluatorId = (Id) existingRaw.get('EvaluatorId');
                String existingStatus = (String) existingRaw.get('Status');
                // Dedupe only against open evaluations so completed/cancelled reviewers can be reassigned.
                if (existingEvaluatorId != null && isOpenStatus(existingStatus)) {
                    reviewerHasOpenAfe.put(existingEvaluatorId, true);
                }
            }

            List<ApplicationFormEvaluation> inserts = new List<ApplicationFormEvaluation>();
            for (Id reviewerId : reviewerIds) {
                if (reviewerHasOpenAfe.get(reviewerId) == true) {
                    resp.skippedCount++;
                    continue;
                }
                inserts.add(new ApplicationFormEvaluation(
                    ApplicationFormId = req.applicationFormId,
                    EvaluatorId = reviewerId,
                    OwnerId = reviewerId,
                    Date = req.dueDate == null ? Date.today() : req.dueDate,
                    Comments = req.comments,
                    Evaluation_Template__c = req.evaluationTemplateId
                ));
            }

            if (!inserts.isEmpty()) {
                insert inserts;
                resp.createdCount = inserts.size();

                String appName = fetchApplicationName(req.applicationFormId);
                Date evaluationDueDate = req.dueDate == null ? Date.today() : req.dueDate;
                String fundingOpportunityName = fetchFundingOpportunityName(req.applicationFormId);
                // Side effects run only when new AFEs are created to avoid duplicate activity/email noise.
                resp.stageUpdated = updateApplicationStageToInReview(req.applicationFormId);

                Set<Id> createdReviewerIds = new Set<Id>();
                for (ApplicationFormEvaluation insertedAfe : inserts) {
                    if (insertedAfe.EvaluatorId != null) {
                        createdReviewerIds.add(insertedAfe.EvaluatorId);
                    }
                }

                resp.taskCount = createReviewerTasks(
                    req.applicationFormId,
                    appName,
                    evaluationDueDate,
                    createdReviewerIds
                );
                resp.emailCount = sendReviewerEmails(
                    appName,
                    fundingOpportunityName,
                    req.applicationFormId,
                    evaluationDueDate,
                    createdReviewerIds
                );
            }

            responses.add(resp);
        }

        return responses;
    }

    private static Set<Id> parseReviewerIds(String reviewerIds) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(reviewerIds)) {
            return ids;
        }
        for (String token : reviewerIds.split(';')) {
            String trimmed = token == null ? null : token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            try {
                ids.add((Id) trimmed);
            } catch (Exception ignored) {
                // Ignore malformed reviewer ids from UI payload.
            }
        }
        return ids;
    }

    private static Boolean isOpenStatus(String statusValue) {
        if (String.isBlank(statusValue)) {
            return true;
        }
        return !CLOSED_STATUSES.contains(statusValue);
    }

    private static String fetchApplicationName(Id applicationFormId) {
        if (applicationFormId == null) {
            return null;
        }
        List<ApplicationForm> forms = [
            SELECT Id, Name
            FROM ApplicationForm
            WHERE Id = :applicationFormId
            LIMIT 1
        ];
        return forms.isEmpty() ? null : forms[0].Name;
    }

    private static String fetchFundingOpportunityName(Id applicationFormId) {
        if (applicationFormId == null) {
            return null;
        }
        List<ApplicationFormRelation> relations = [
            SELECT ReferenceRecordId
            FROM ApplicationFormRelation
            WHERE ApplicationFormId = :applicationFormId
            AND ReferenceObjectName = 'FundingOpportunity'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (relations.isEmpty() || relations[0].ReferenceRecordId == null) {
            return null;
        }
        List<FundingOpportunity> opportunities = [
            SELECT Name
            FROM FundingOpportunity
            WHERE Id = :relations[0].ReferenceRecordId
            LIMIT 1
        ];
        return opportunities.isEmpty() ? null : opportunities[0].Name;
    }

    private static Boolean updateApplicationStageToInReview(Id applicationFormId) {
        if (applicationFormId == null) {
            return false;
        }

        String inReviewValue = resolveTaskOrApplicationPicklistValue(
            ApplicationForm.Stage.getDescribe().getPicklistValues(),
            'In Review',
            null
        );
        if (String.isBlank(inReviewValue)) {
            return false;
        }

        Database.SaveResult result = Database.update(
            new ApplicationForm(Id = applicationFormId, Stage = inReviewValue),
            false
        );
        return result != null && result.isSuccess();
    }

    private static Integer createReviewerTasks(
        Id applicationFormId,
        String applicationName,
        Date evaluationDueDate,
        Set<Id> reviewerIds
    ) {
        if (applicationFormId == null || reviewerIds == null || reviewerIds.isEmpty()) {
            return 0;
        }

        String statusValue = resolveTaskOrApplicationPicklistValue(
            Task.Status.getDescribe().getPicklistValues(),
            'Not Started',
            true
        );
        String priorityValue = resolveTaskOrApplicationPicklistValue(
            Task.Priority.getDescribe().getPicklistValues(),
            'Normal',
            true
        );
        Date safeEvaluationDueDate = evaluationDueDate == null ? Date.today() : evaluationDueDate;
        Date activityDate = safeEvaluationDueDate.addDays(TASK_DUE_OFFSET_DAYS);

        List<Task> tasksToInsert = new List<Task>();
        for (Id reviewerId : reviewerIds) {
            Task t = new Task();
            t.OwnerId = reviewerId;
            t.WhatId = applicationFormId;
            t.Subject = 'Grant Application Review';
            t.ActivityDate = activityDate;
            if (!String.isBlank(statusValue)) {
                t.Status = statusValue;
            }
            if (!String.isBlank(priorityValue)) {
                t.Priority = priorityValue;
            }

            t.Description =
                'Please complete the evaluation for the assigned grant application before the review deadline.';
            tasksToInsert.add(t);
        }

        Database.SaveResult[] results = Database.insert(tasksToInsert, false);
        Integer created = 0;
        for (Database.SaveResult sr : results) {
            if (sr != null && sr.isSuccess()) {
                created++;
            }
        }
        return created;
    }

    private static Integer sendReviewerEmails(
        String applicationName,
        String fundingOpportunityName,
        Id applicationFormId,
        Date evaluationDueDate,
        Set<Id> reviewerIds
    ) {
        if (reviewerIds == null || reviewerIds.isEmpty()) {
            return 0;
        }

        String safeAppName = String.isBlank(applicationName) ? String.valueOf(applicationFormId) : applicationName;
        String safeFundingOpportunityName = String.isBlank(fundingOpportunityName)
            ? 'Not Available'
            : fundingOpportunityName;
        Date safeEvaluationDueDate = evaluationDueDate == null ? Date.today() : evaluationDueDate;

        Map<Id, String> reviewerNameById = new Map<Id, String>();
        for (User reviewer : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :reviewerIds
        ]) {
            reviewerNameById.put(reviewer.Id, reviewer.Name);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Id reviewerId : reviewerIds) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(reviewerId);
            email.setSaveAsActivity(true);
            email.setSubject('New Grant Application Review Assigned');

            String reviewerName = reviewerNameById.containsKey(reviewerId) ? reviewerNameById.get(reviewerId) : 'Reviewer';
            List<String> bodyLines = new List<String>{
                'Hello ' + reviewerName + ',',
                '',
                'You have been assigned to review a grant application.',
                '',
                'Application: ' + safeAppName,
                'Funding Opportunity: ' + safeFundingOpportunityName,
                'Review Due Date: ' + String.valueOf(safeEvaluationDueDate),
                '',
                'Please complete your review in Salesforce before the due date.',
                '',
                'Thank you.'
            };
            email.setPlainTextBody(String.join(bodyLines, '\n'));
            emails.add(email);
        }

        try {
            Messaging.sendEmail(emails, false);
        } catch (Exception e) {
            return 0;
        }
        return emails.size();
    }

    private static String resolveTaskOrApplicationPicklistValue(
        List<Schema.PicklistEntry> entries,
        String preferredValue,
        Boolean openOnlyForTaskStatus
    ) {
        if (entries == null || entries.isEmpty()) {
            return null;
        }

        for (Schema.PicklistEntry entry : entries) {
            if (entry != null && entry.isActive() && entry.getValue() == preferredValue) {
                return entry.getValue();
            }
        }

        // Fallback to the first active value when org picklists differ from expected defaults.
        for (Schema.PicklistEntry entry : entries) {
            if (entry == null || !entry.isActive()) {
                continue;
            }
            if (openOnlyForTaskStatus == true && CLOSED_STATUSES.contains(entry.getValue())) {
                continue;
            }
            return entry.getValue();
        }
        return null;
    }
}
