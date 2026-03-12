@IsTest
private class PSGReadControllerTest {
    private static List<Criterion_Library__c> createCriteria(Integer count, String keyPrefix) {
        List<Criterion_Library__c> rows = new List<Criterion_Library__c>();
        for (Integer i = 0; i < count; i++) {
            String suffix = String.valueOf(i).leftPad(3, '0');
            rows.add(new Criterion_Library__c(
                Label__c = keyPrefix + ' Criterion ' + suffix,
                Description__c = 'Test criterion ' + suffix,
                DeveloperKey__c = (keyPrefix + '_criterion_' + suffix).toLowerCase(),
                Active__c = true
            ));
        }
        insert rows;
        return rows;
    }

    @IsTest
    static void pagination_pageOneReturnsExpectedRows() {
        createCriteria(30, 'PageOne');

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse response =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                10,
                1,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(10, response.rows.size(), 'Page 1 should return page size rows.');
        System.assertEquals(10, response.pageSize);
        System.assertEquals(1, response.pageNumber);
        System.assertEquals(30, response.totalCount);
        System.assertEquals(true, response.hasMore);
        System.assertEquals(false, response.securityFiltered);
    }

    @IsTest
    static void pagination_middlePageWorks() {
        createCriteria(25, 'Middle');

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse page1 =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                10,
                1,
                'recordName',
                'asc'
            );
        PublicSectorGrantmakingReadController.WorkspaceResponse page2 =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                10,
                2,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertEquals(10, page2.rows.size(), 'Middle page should return full row count.');
        System.assertEquals(2, page2.pageNumber);
        System.assertNotEquals(
            page1.rows[0].recordId,
            page2.rows[0].recordId,
            'Page 2 should not start with page 1 first row.'
        );
    }

    @IsTest
    static void pagination_lastPageHasMoreFalse() {
        createCriteria(21, 'Last');

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse response =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                10,
                3,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertEquals(1, response.rows.size(), 'Last page should return remaining rows.');
        System.assertEquals(false, response.hasMore, 'Last page should not have more rows.');
        System.assertEquals(3, response.pageNumber);
    }

    @IsTest
    static void pagination_invalidPageNumberAndPageSizeAreNormalized() {
        createCriteria(5, 'Normalize');

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse response =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                999,
                0,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertEquals(200, response.pageSize, 'Page size should clamp to server max.');
        System.assertEquals(1, response.pageNumber, 'Page number should normalize to page 1.');
        System.assertEquals(5, response.rows.size(), 'Normalized page should still return rows.');
    }

    @IsTest
    static void sort_invalidSortFieldFallsBackToDefault() {
        List<Criterion_Library__c> rows = createCriteria(12, 'SortFallback');
        rows[0].Description__c = 'Updated to force latest LastModifiedDate ordering';
        update rows[0];

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse invalidSortResponse =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                5,
                1,
                'notAllowedSort',
                'asc'
            );
        PublicSectorGrantmakingReadController.WorkspaceResponse defaultSortResponse =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                5,
                1,
                'primaryDate',
                'desc'
            );
        Test.stopTest();

        System.assertEquals(5, invalidSortResponse.rows.size());
        System.assertEquals(5, defaultSortResponse.rows.size());
        System.assertEquals(
            defaultSortResponse.rows[0].recordId,
            invalidSortResponse.rows[0].recordId,
            'Invalid sort should fallback to default sort.'
        );
    }

    @IsTest
    static void searchAndPaging_contractRemainsStable() {
        createCriteria(15, 'SearchReset');

        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse unfilteredPageTwo =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                null,
                5,
                2,
                'recordName',
                'asc'
            );
        PublicSectorGrantmakingReadController.WorkspaceResponse filteredPageOne =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'criteriaLibrary',
                'SearchReset Criterion 00',
                5,
                1,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertEquals(2, unfilteredPageTwo.pageNumber);
        System.assertEquals(1, filteredPageOne.pageNumber);
        System.assertEquals(true, filteredPageOne.totalCount > 0, 'Filtered call should return matching rows.');
    }

    @IsTest
    static void securityFiltered_noteAppearsWithForcedRemovedFields() {
        createCriteria(3, 'Secure');
        PublicSectorGrantmakingReadController.TEST_FORCED_REMOVED_FIELDS_BY_OBJECT =
            new Map<String, Set<String>>{
                'Criterion_Library__c' => new Set<String>{ 'Label__c' }
            };

        try {
            Test.startTest();
            PublicSectorGrantmakingReadController.WorkspaceResponse response =
                PublicSectorGrantmakingReadController.getWorkspaceRows(
                    'criteriaLibrary',
                    null,
                    10,
                    1,
                    'recordName',
                    'asc'
                );
            Test.stopTest();

            System.assertEquals(true, response.securityFiltered);
            System.assert(
                response.helperNote != null && response.helperNote.contains('field-level security'),
                'Helper note should include FLS context when fields are filtered.'
            );
        } finally {
            PublicSectorGrantmakingReadController.clearTestOverrides();
        }
    }

    @IsTest
    static void homePayload_resilientAndSecurityFlagPresent() {
        PublicSectorGrantmakingReadController.TEST_FORCED_REMOVED_FIELDS_BY_OBJECT =
            new Map<String, Set<String>>{
                'ApplicationForm' => new Set<String>{ 'Title' }
            };

        try {
            Test.startTest();
            PublicSectorGrantmakingReadController.HomeDashboardData data =
                PublicSectorGrantmakingReadController.getHomeDashboardData();
            Test.stopTest();

            System.assertNotEquals(null, data);
            System.assertNotEquals(null, data.recentApplicationForms);
            System.assertNotEquals(null, data.recentEvaluations);
            System.assertEquals(true, data.securityFiltered);
            System.assert(
                data.helperNote != null && data.helperNote.contains('field-level security'),
                'Home helper note should indicate FLS filtering.'
            );
        } finally {
            PublicSectorGrantmakingReadController.clearTestOverrides();
        }
    }

    @IsTest
    static void unknownWorkspaceKey_defaultsSafely() {
        Test.startTest();
        PublicSectorGrantmakingReadController.WorkspaceResponse response =
            PublicSectorGrantmakingReadController.getWorkspaceRows(
                'not-real-key',
                null,
                25,
                1,
                'recordName',
                'asc'
            );
        Test.stopTest();

        System.assertEquals('not-real-key', response.workspaceKey);
        System.assertEquals('Funding Opportunities', response.title);
        System.assertEquals('FundingOpportunity', response.objectApiName);
        System.assertNotEquals(null, response.rows);
    }
}