@IsTest
private class EvaluationFrameworkReviewServiceTest {
    // Test strategy:
    // - Replace live prompt calls with stub JSON payloads.
    // - Validate parsing, optional writes, and edge-case handling.
    private class StubPromptInvoker implements System.Callable {
        private String payload;

        StubPromptInvoker(String payload) {
            this.payload = payload;
        }

        public Object call(String action, Map<String, Object> args) {
            return payload;
        }
    }

    @IsTest
    static void analyzeFramework_previewMode_successfullyParses() {
        // Preview mode should parse AI output but skip criterion library writes.
        Id templateId = createTemplateWithCriteria(2);
        String payload = '{' +
            '"frameworkHealthScore": 7.8,' +
            '"dimensionScores": {"clarity": 8, "balance": 7, "coverage": 8, "redundancy": 6},' +
            '"issues": [{"type":"ambiguity", "message":"Criterion wording is broad."}],' +
            '"recommendations": [' +
                '{"type":"newCriterion","name":"Community Partnerships","description":"Measure local partners.","suggestedWeight":15},' +
                '{"type":"unknownType","name":"Ignored","description":"Ignore me","suggestedWeight":3}' +
            '],' +
            '"improvements": [{"criterion":"Community Impact", "message":"Clarify expected outcomes."}]' +
        '}';

        Test.startTest();
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(payload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse response =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        Test.stopTest();

        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(true, response.success, 'Expected successful prompt parse.');
        System.assertEquals('EvaluationFrameworkReview', response.promptTemplateApiName);
        System.assertEquals(false, response.applyLibraryActions);
        System.assertEquals(2, response.criteriaCount);
        System.assertNotEquals(null, response.review);
        System.assertEquals(1, response.review.issues.size());
        System.assertEquals(2, response.review.recommendations.size());
        System.assertEquals(1, response.review.improvements.size());
        System.assert(response.libraryActionSummary.notes[0].contains('Preview mode'), 'Expected preview mode note.');

        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        if (templateFields.containsKey('Framework_Health_Score__c')) {
            List<SObject> reloaded = Database.query(
                'SELECT Framework_Health_Score__c FROM Evaluation_Template__c WHERE Id = :templateId LIMIT 1'
            );
            System.assertEquals(7.8, reloaded[0].get('Framework_Health_Score__c'));
        }
    }

    @IsTest
    static void analyzeFramework_applyActions_createsAndFlagsCriteriaWhenAvailable() {
        // Apply mode should perform writes based on recommendation types.
        Id templateId = createTemplateWithCriteria(1);
        insert new Criterion_Library__c(
            Label__c = 'Existing Criterion',
            Description__c = 'Original description',
            DeveloperKey__c = 'existing_criterion',
            Active__c = true
        );

        String payload = '{' +
            '"frameworkHealthScore": 6.5,' +
            '"dimensionScores": {"clarity": 6, "balance": 6, "coverage": 7, "redundancy": 5},' +
            '"issues": [],' +
            '"recommendations": [' +
                '{"type":"newCriterion","name":"Data Integrity","description":"Evaluate data controls.","suggestedWeight":10},' +
                '{"type":"modifyCriterion","name":"Existing Criterion","description":"Mark for review","suggestedWeight":null},' +
                '{"type":"adjustWeight","name":"Existing Criterion","description":"Adjust recommendation","suggestedWeight":22}' +
            '],' +
            '"improvements": []' +
        '}';

        Test.startTest();
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(payload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse response =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, true, false);
        Test.stopTest();

        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(true, response.success, 'Expected successful analyze with actioning. ' + response.message);
        System.assertEquals(true, response.applyLibraryActions);
        System.assertEquals(1, response.libraryActionSummary.createdCount, 'Expected one criterion created from newCriterion.');

        List<Criterion_Library__c> created = [
            SELECT Id, Label__c, Description__c, Active__c
            FROM Criterion_Library__c
            WHERE Label__c = 'Data Integrity'
            LIMIT 1
        ];
        System.assertEquals(1, created.size(), 'Expected created criterion library record.');
        System.assertEquals(false, created[0].Active__c, 'AI-created criteria should start inactive/draft-safe.');
    }

    @IsTest
    static void analyzeFramework_handlesMalformedPayload() {
        // Invalid JSON should fail gracefully with a handled response.
        Id templateId = createTemplateWithCriteria(1);

        Test.startTest();
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker('not-json-output');
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse response =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        Test.stopTest();

        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(false, response.success);
        System.assert(response.message.contains('failed'), 'Expected handled failure message.');
    }

    @IsTest
    static void analyzeFramework_handlesEmptyCriteriaList() {
        Evaluation_Template__c template = new Evaluation_Template__c(
            Active__c = true,
            Status__c = 'Draft',
            Version__c = 1
        );
        insert template;

        String payload = '{"frameworkHealthScore":5,"dimensionScores":{},"issues":[],"recommendations":[],"improvements":[]}';

        Test.startTest();
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(payload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse response =
            EvaluationFrameworkReviewService.analyzeFramework(template.Id, false, true);
        Test.stopTest();

        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(true, response.success);
        System.assertEquals(0, response.criteriaCount);
        System.assertEquals(0, response.review.recommendations.size());
    }

    @IsTest
    static void analyzeFramework_handlesNullAndMissingTemplateInputs() {
        Test.startTest();
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse nullResponse =
            EvaluationFrameworkReviewService.analyzeFramework(null, false, true);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse missingResponse =
            EvaluationFrameworkReviewService.analyzeFramework(UserInfo.getUserId(), false, true);
        Test.stopTest();

        System.assertEquals(false, nullResponse.success);
        System.assert(nullResponse.message.contains('Select an evaluation template'));
        System.assertEquals(false, missingResponse.success);
        System.assert(missingResponse.message.contains('not found'));
    }

    @IsTest
    static void analyzeFramework_handlesEmptyPromptTextAndComplexRecommendationShapes() {
        Id templateId = createTemplateWithCriteria(1);

        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(null);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse emptyTextResponse =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(false, emptyTextResponse.success);

        String mixedPayload = '{' +
            '\"frameworkHealthScore\":\"9.0\",' +
            '\"dimensionScores\":{\"clarity\":8,\"balance\":\"7.5\",\"coverage\":6.0,\"redundancy\":\"\"},' +
            '\"issues\":[\"badRow\", {\"type\":\"overlap\",\"message\":\"Overlapping criteria.\"}],' +
            '\"recommendations\":[' +
                '{\"type\":\"newCriterion\",\"name\":\"*** New / Criterion ***\",\"description\":\"\",\"suggestedWeight\":\"5\"},' +
                '{\"type\":\"modifyCriterion\",\"name\":\"Missing Criterion\",\"description\":\"Needs work\",\"suggestedWeight\":\"12\"},' +
                '{\"type\":\"adjustWeight\",\"name\":\"Missing Criterion\",\"description\":\"bad weight\",\"suggestedWeight\":\"oops\"},' +
                '{\"type\":\"\",\"name\":\"\",\"description\":\"\",\"suggestedWeight\":null}' +
            '],' +
            '\"improvements\":[\"ignore\", {\"criterion\":\"Community Impact\",\"message\":\"Clarify scoring language.\"}]' +
        '}';

        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(mixedPayload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse mixedResponse =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, true, false);
        EvaluationFrameworkReviewService.promptInvokerOverride = null;

        System.assertEquals(true, mixedResponse.success, mixedResponse.message);
        System.assertEquals(true, mixedResponse.applyLibraryActions);
        System.assertEquals(1, mixedResponse.review.issues.size());
        System.assertEquals(4, mixedResponse.review.recommendations.size());
        System.assertEquals(1, mixedResponse.review.improvements.size());
        System.assert(mixedResponse.libraryActionSummary.skippedCount > 0);
    }

    @IsTest
    static void analyzeFramework_coversParserFallbackBranches() {
        Id templateId = createTemplateWithCriteria(1);

        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker('[]');
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse nonObjectResponse =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        EvaluationFrameworkReviewService.promptInvokerOverride = null;
        System.assertEquals(false, nonObjectResponse.success);

        String nonListPayload = '{' +
            '\"frameworkHealthScore\":5,' +
            '\"dimensionScores\":{},' +
            '\"issues\":{},' +
            '\"recommendations\":{},' +
            '\"improvements\":{}' +
        '}';
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(nonListPayload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse nonListResponse =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        EvaluationFrameworkReviewService.promptInvokerOverride = null;
        System.assertEquals(true, nonListResponse.success, nonListResponse.message);
        System.assertEquals(0, nonListResponse.review.issues.size());
        System.assertEquals(0, nonListResponse.review.recommendations.size());
        System.assertEquals(0, nonListResponse.review.improvements.size());

        String mixedRecommendationsPayload = '{' +
            '\"frameworkHealthScore\":6,' +
            '\"dimensionScores\":{},' +
            '\"issues\":[],' +
            '\"recommendations\":[1,{\"type\":\"newCriterion\",\"name\":\"Parser Coverage\",\"description\":\"Coverage row\",\"suggestedWeight\":3}],' +
            '\"improvements\":[]' +
        '}';
        EvaluationFrameworkReviewService.promptInvokerOverride = new StubPromptInvoker(mixedRecommendationsPayload);
        EvaluationFrameworkReviewService.AnalyzeFrameworkResponse mixedRecommendationsResponse =
            EvaluationFrameworkReviewService.analyzeFramework(templateId, false, true);
        EvaluationFrameworkReviewService.promptInvokerOverride = null;
        System.assertEquals(true, mixedRecommendationsResponse.success, mixedRecommendationsResponse.message);
        System.assertEquals(1, mixedRecommendationsResponse.review.recommendations.size());
    }

    private static Id createTemplateWithCriteria(Integer count) {
        // Shared data factory for tests in this class.
        Evaluation_Template__c template = new Evaluation_Template__c(
            Active__c = true,
            Status__c = 'Draft',
            Version__c = 1
        );
        insert template;

        List<Evaluation_Template_Criterion__c> criteria = new List<Evaluation_Template_Criterion__c>();
        for (Integer i = 0; i < count; i++) {
            criteria.add(new Evaluation_Template_Criterion__c(
                Evaluation_Template__c = template.Id,
                Criterion_Key__c = 'CRIT-' + i,
                Label__c = 'Criterion ' + i,
                Description__c = 'Description ' + i,
                Weight__c = 20,
                Display_Order__c = i + 1,
                Section_Name__c = 'General'
            ));
        }
        if (!criteria.isEmpty()) {
            insert criteria;
        }
        return template.Id;
    }
}
