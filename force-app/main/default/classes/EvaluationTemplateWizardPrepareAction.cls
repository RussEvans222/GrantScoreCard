public with sharing class EvaluationTemplateWizardPrepareAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id fundingOpportunityId;

        @InvocableVariable
        public Id cloneFromFundingOpportunityId;
    }

    public class Response {
        @InvocableVariable public Id workingTemplateId;
        @InvocableVariable public String preselectedCriterionIdsCsv;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Prepare Evaluation Template Draft')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response resp = new Response();
            if (req == null || req.fundingOpportunityId == null) {
                resp.message = 'Funding Opportunity is required.';
                responses.add(resp);
                continue;
            }

            // Wizard always works against a mutable draft template, never a published in-use version.
            Id workingTemplateId;
            if (req.cloneFromFundingOpportunityId != null) {
                workingTemplateId = cloneFromFundingOpportunity(req.cloneFromFundingOpportunityId);
                if (workingTemplateId == null) {
                    workingTemplateId = RubricTemplateService.createInitialTemplate(req.fundingOpportunityId);
                    resp.message = 'Source Funding Opportunity had no template. A new draft was created.';
                } else {
                    resp.message = 'Draft cloned from source Funding Opportunity template.';
                }
            } else {
                workingTemplateId = resolveOrCreateWorkingTemplate(req.fundingOpportunityId);
            }

            if (workingTemplateId != null) {
                Evaluation_Template__c working = [
                    SELECT Id, Root_Template__c
                    FROM Evaluation_Template__c
                    WHERE Id = :workingTemplateId
                    LIMIT 1
                ];
                Evaluation_Template__c t = new Evaluation_Template__c(
                    Id = workingTemplateId,
                    Status__c = 'Draft',
                    Active__c = false
                );
                // Heal legacy bad data where root points to itself; this causes hierarchy violations.
                if (working.Root_Template__c == working.Id) {
                    t.Root_Template__c = null;
                }
                update t;
            }

            resp.workingTemplateId = workingTemplateId;
            resp.preselectedCriterionIdsCsv = buildPreselectedIdsCsv(workingTemplateId);
            if (String.isBlank(resp.message)) {
                resp.message = 'Draft template ready.';
            }
            responses.add(resp);
        }
        return responses;
    }

    private static Id resolveOrCreateWorkingTemplate(Id fundingOpportunityId) {
        FundingOpportunity fo = [
            SELECT Id, Evaluation_Template__c
            FROM FundingOpportunity
            WHERE Id = :fundingOpportunityId
            LIMIT 1
        ];

        if (fo.Evaluation_Template__c == null) {
            return RubricTemplateService.createInitialTemplate(fundingOpportunityId);
        }

        Evaluation_Template__c current = [
            SELECT Id, Status__c
            FROM Evaluation_Template__c
            WHERE Id = :fo.Evaluation_Template__c
            LIMIT 1
        ];

        if (current.Status__c == 'Draft' && !hasEvaluations(current.Id)) {
            // Reuse mutable drafts only when they are not yet referenced by evaluations.
            return current.Id;
        }
        if (current.Status__c == 'Published' || hasEvaluations(current.Id)) {
            // Published or in-use templates are treated as immutable; edits happen on clones.
            return RubricTemplateService.cloneTemplate(current.Id);
        }
        return RubricTemplateService.createInitialTemplate(fundingOpportunityId);
    }

    private static Id cloneFromFundingOpportunity(Id sourceFundingOpportunityId) {
        List<FundingOpportunity> sourceRows = [
            SELECT Id, Evaluation_Template__c
            FROM FundingOpportunity
            WHERE Id = :sourceFundingOpportunityId
            LIMIT 1
        ];
        if (sourceRows.isEmpty() || sourceRows[0].Evaluation_Template__c == null) {
            return null;
        }
        return RubricTemplateService.cloneTemplate(sourceRows[0].Evaluation_Template__c);
    }

    private static Boolean hasEvaluations(Id templateId) {
        if (templateId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM ApplicationFormEvaluation
            WHERE Evaluation_Template__c = :templateId
        ] > 0;
    }

    private static String buildPreselectedIdsCsv(Id workingTemplateId) {
        if (workingTemplateId == null) {
            return null;
        }
        List<String> ids = new List<String>();
        for (Evaluation_Template_Criterion__c row : [
            SELECT SourceLibraryCriterion__c
            FROM Evaluation_Template_Criterion__c
            WHERE Evaluation_Template__c = :workingTemplateId
            AND SourceLibraryCriterion__c != null
        ]) {
            ids.add(String.valueOf(row.SourceLibraryCriterion__c));
        }
        return String.join(ids, ';');
    }
}