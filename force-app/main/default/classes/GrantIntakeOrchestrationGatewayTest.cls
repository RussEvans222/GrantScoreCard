@IsTest
private class GrantIntakeOrchestrationGatewayTest {
    private static Integer fundingFinderCalls = 0;
    private static Integer saveDraftCalls = 0;
    private static Integer submitCalls = 0;
    private static Integer initEvaluationCalls = 0;

    private class StubGatewayDelegate implements GrantIntakeOrchestrationGateway.GatewayDelegate {
        public GrantIntakeOrchestrationGateway.FundingFinderResponse getFundingFinderResults(
            GrantIntakeOrchestrationGateway.FundingFinderRequest requestData
        ) {
            fundingFinderCalls++;
            GrantIntakeOrchestrationGateway.FundingFinderResponse response =
                new GrantIntakeOrchestrationGateway.FundingFinderResponse();
            response.success = true;
            response.message = requestData == null ? 'none' : requestData.searchText;
            response.rows = new List<GrantIntakeOrchestrationGateway.FundingFinderRow>();
            return response;
        }

        public GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse saveDraftApplication(
            GrantIntakeOrchestrationGateway.GrantApplicationDraftRequest requestData
        ) {
            saveDraftCalls++;
            GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse response =
                new GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse();
            response.success = true;
            response.status = 'Draft Saved';
            response.message = requestData == null ? null : requestData.applicationPayload;
            response.draftApplicationId = 'draft-1';
            return response;
        }

        public GrantIntakeOrchestrationGateway.GrantSubmissionResponse submitApplication(
            GrantIntakeOrchestrationGateway.GrantSubmissionRequest requestData
        ) {
            submitCalls++;
            GrantIntakeOrchestrationGateway.GrantSubmissionResponse response =
                new GrantIntakeOrchestrationGateway.GrantSubmissionResponse();
            response.success = true;
            response.status = 'Submitted';
            response.message = requestData == null ? null : requestData.applicationPayload;
            response.applicationId = 'app-1';
            return response;
        }

        public GrantIntakeOrchestrationGateway.EvaluationInitializationResponse initializeEvaluation(
            GrantIntakeOrchestrationGateway.EvaluationInitializationRequest requestData
        ) {
            initEvaluationCalls++;
            GrantIntakeOrchestrationGateway.EvaluationInitializationResponse response =
                new GrantIntakeOrchestrationGateway.EvaluationInitializationResponse();
            response.success = true;
            response.status = 'Initialized';
            response.message = requestData == null ? null : String.valueOf(requestData.applicationId);
            response.evaluationId = null;
            return response;
        }
    }

    @IsTest
    static void gatewayMethods_delegateWhenOverrideIsSet() {
        fundingFinderCalls = 0;
        saveDraftCalls = 0;
        submitCalls = 0;
        initEvaluationCalls = 0;
        GrantIntakeOrchestrationGateway.delegateOverride = new StubGatewayDelegate();

        try {
            Test.startTest();
            GrantIntakeOrchestrationGateway.FundingFinderResponse finderResponse =
                GrantIntakeOrchestrationGateway.getFundingFinderResults('community');
            GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse draftResponse =
                GrantIntakeOrchestrationGateway.saveDraftApplication('{"draft":true}');
            GrantIntakeOrchestrationGateway.GrantSubmissionResponse submitResponse =
                GrantIntakeOrchestrationGateway.submitApplication('{"submit":true}');
            GrantIntakeOrchestrationGateway.EvaluationInitializationResponse initResponse =
                GrantIntakeOrchestrationGateway.initializeEvaluation('001Hp0000000001IAA');
            Test.stopTest();

            System.assertEquals(true, finderResponse.success);
            System.assertEquals('community', finderResponse.message);
            System.assertEquals(true, draftResponse.success);
            System.assertEquals('Draft Saved', draftResponse.status);
            System.assertEquals(true, submitResponse.success);
            System.assertEquals('Submitted', submitResponse.status);
            System.assertEquals(true, initResponse.success);
            System.assertEquals('Initialized', initResponse.status);

            System.assertEquals(1, fundingFinderCalls);
            System.assertEquals(1, saveDraftCalls);
            System.assertEquals(1, submitCalls);
            System.assertEquals(1, initEvaluationCalls);
        } finally {
            GrantIntakeOrchestrationGateway.delegateOverride = null;
        }
    }

    @IsTest
    static void fundingFinder_defaultDelegate_returnsContractShape() {
        Test.startTest();
        GrantIntakeOrchestrationGateway.FundingFinderResponse response =
            GrantIntakeOrchestrationGateway.getFundingFinderResults(null);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should be initialized.');
        System.assertNotEquals(null, response.rows, 'Rows should be initialized.');
        System.assertNotEquals(null, response.success, 'Success flag should be explicit.');
        System.assertNotEquals(null, response.pageSize, 'Page size should be present.');
        System.assertNotEquals(null, response.pageNumber, 'Page number should be present.');
    }

    @IsTest
    static void dtoSerialization_roundTripsForOmniContract() {
        GrantIntakeOrchestrationGateway.FundingFinderRequest requestData =
            new GrantIntakeOrchestrationGateway.FundingFinderRequest();
        requestData.searchText = 'transportation';
        requestData.pageSize = 50;
        requestData.pageNumber = 2;
        requestData.sortBy = 'recordName';
        requestData.sortDirection = 'asc';

        String asJson = JSON.serialize(requestData);
        GrantIntakeOrchestrationGateway.FundingFinderRequest hydrated =
            (GrantIntakeOrchestrationGateway.FundingFinderRequest) JSON.deserialize(
                asJson,
                GrantIntakeOrchestrationGateway.FundingFinderRequest.class
            );

        System.assertEquals('transportation', hydrated.searchText);
        System.assertEquals(50, hydrated.pageSize);
        System.assertEquals(2, hydrated.pageNumber);
        System.assertEquals('recordName', hydrated.sortBy);
        System.assertEquals('asc', hydrated.sortDirection);
    }

    @IsTest
    static void saveDraft_defaultDelegate_invalidPayloadReturnsErrorContract() {
        Test.startTest();
        GrantIntakeOrchestrationGateway.GrantApplicationDraftResponse response =
            GrantIntakeOrchestrationGateway.saveDraftApplication('not-json');
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(false, response.success);
        System.assertEquals('Error', response.status);
        System.assert(response.message != null && response.message.contains('payload'));
    }

    @IsTest
    static void submit_defaultDelegate_invalidPayloadReturnsErrorContract() {
        Test.startTest();
        GrantIntakeOrchestrationGateway.GrantSubmissionResponse response =
            GrantIntakeOrchestrationGateway.submitApplication('{"application":{}}');
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(false, response.success);
        System.assertEquals('Error', response.status);
        System.assert(
            response.message != null && response.message.contains('application id'),
            'Submission should fail with missing application id.'
        );
    }

    @IsTest
    static void initialize_defaultDelegate_missingIdReturnsErrorContract() {
        Test.startTest();
        GrantIntakeOrchestrationGateway.EvaluationInitializationResponse response =
            GrantIntakeOrchestrationGateway.initializeEvaluation(null);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(false, response.success);
        System.assertEquals('Error', response.status);
        System.assert(
            response.message != null && response.message.contains('Application id'),
            'Initialization should require a valid application id.'
        );
    }
}
