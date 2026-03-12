public with sharing class PSGWorkspaceReadService {
    private class QueryRowsResult {
        List<PublicSectorGrantmakingReadController.WorkspaceRow> rows = new List<PublicSectorGrantmakingReadController.WorkspaceRow>();
        Boolean securityFiltered = false;
    }

    public static PublicSectorGrantmakingReadController.WorkspaceResponse getWorkspaceRows(
        String workspaceKey,
        String searchText,
        Integer pageSize,
        Integer pageNumber,
        String sortBy,
        String sortDirection
    ) {
        Integer normalizedPageSize = PSGQueryAccessUtil.normalizePageSize(pageSize);
        Integer normalizedPageNumber = PSGQueryAccessUtil.normalizePageNumber(pageNumber);

        PublicSectorGrantmakingReadController.WorkspaceResponse response =
            new PublicSectorGrantmakingReadController.WorkspaceResponse();
        response.workspaceKey = String.isBlank(workspaceKey) ? 'fundingOpportunities' : workspaceKey;
        response.rows = new List<PublicSectorGrantmakingReadController.WorkspaceRow>();
        response.securityFiltered = false;
        response.pageSize = normalizedPageSize;
        response.pageNumber = normalizedPageNumber;

        PSGWorkspaceConfig config = PSGWorkspaceConfig.resolve(response.workspaceKey);
        response.title = config.title;
        response.objectApiName = config.objectApiName;

        Schema.DescribeSObjectResult objectDescribe = PSGQueryAccessUtil.safeDescribeLookup(config.objectApiName);
        if (objectDescribe == null) {
            response.totalCount = 0;
            response.hasMore = false;
            response.helperNote = 'Object ' + config.objectApiName + ' is not available in this org.';
            return response;
        }
        if (!objectDescribe.isAccessible()) {
            response.totalCount = 0;
            response.hasMore = false;
            response.helperNote = 'Object ' + config.objectApiName + ' is not accessible for this user.';
            return response;
        }

        Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
        String whereClause = buildWhereClause(config, searchText, fields);
        String orderByClause = resolveSortClause(config, fields, sortBy, sortDirection);

        response.totalCount = safeCount(config.objectApiName, whereClause, objectDescribe);

        QueryRowsResult queryResult = queryRows(
            config,
            whereClause,
            objectDescribe,
            normalizedPageSize,
            normalizedPageNumber,
            orderByClause
        );

        response.rows = queryResult.rows;
        response.securityFiltered = queryResult.securityFiltered;
        response.hasMore = (normalizedPageNumber * normalizedPageSize) < response.totalCount;
        response.helperNote =
            'Showing page ' + normalizedPageNumber + ' (' + response.rows.size() + ' rows) of ' + response.totalCount + ' records.';
        if (response.securityFiltered) {
            response.helperNote += ' Some values are hidden due to field-level security.';
        }

        return response;
    }

    private static QueryRowsResult queryRows(
        PSGWorkspaceConfig config,
        String whereClause,
        Schema.DescribeSObjectResult objectDescribe,
        Integer pageSize,
        Integer pageNumber,
        String orderByClause
    ) {
        QueryRowsResult result = new QueryRowsResult();
        Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id' };

        addSelectFieldIfValid(selectFields, config.getFieldApiName('recordName'), fields);
        addSelectFieldIfValid(selectFields, config.getFieldApiName('status'), fields);
        addSelectFieldIfValid(selectFields, config.getFieldApiName('primaryDate'), fields);
        addSelectFieldIfValid(selectFields, config.getFieldApiName('secondaryValue'), fields);
        addSelectFieldIfValid(selectFields, config.getFieldApiName('detail'), fields);

        if (fields.containsKey('OwnerId')) {
            selectFields.add('Owner.Name');
        }
        if (!selectFields.contains('LastModifiedDate') && fields.containsKey('LastModifiedDate')) {
            selectFields.add('LastModifiedDate');
        }

        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM ' + config.objectApiName;
        if (!String.isBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        soql += ' ORDER BY ' + orderByClause;

        Integer normalizedPageSize = PSGQueryAccessUtil.normalizePageSize(pageSize);
        Integer normalizedPageNumber = PSGQueryAccessUtil.normalizePageNumber(pageNumber);
        Integer rowOffset = (normalizedPageNumber - 1) * normalizedPageSize;
        soql += ' LIMIT ' + normalizedPageSize;
        soql += ' OFFSET ' + rowOffset;

        List<SObject> queriedRecords = Database.query(soql);
        SObjectAccessDecision accessDecision = Security.stripInaccessible(System.AccessType.READABLE, queriedRecords);
        List<SObject> readableRecords = accessDecision.getRecords();
        result.securityFiltered = PSGQueryAccessUtil.hasRemovedFieldsForObject(
            accessDecision.getRemovedFields(),
            config.objectApiName
        );

        for (SObject rowSource : readableRecords) {
            PublicSectorGrantmakingReadController.WorkspaceRow row =
                new PublicSectorGrantmakingReadController.WorkspaceRow();
            row.recordId = (Id) rowSource.get('Id');
            row.recordUrl = '/' + row.recordId;
            row.recordName = toDisplay(getFieldValue(rowSource, config.getFieldApiName('recordName')));
            row.status = toDisplay(getFieldValue(rowSource, config.getFieldApiName('status')));
            row.primaryDate = toDisplay(getFieldValue(rowSource, config.getFieldApiName('primaryDate')));
            row.secondaryValue = toDisplay(getFieldValue(rowSource, config.getFieldApiName('secondaryValue')));
            row.detail = toDisplay(getFieldValue(rowSource, config.getFieldApiName('detail')));
            row.ownerName = toDisplay(getFieldValue(rowSource, 'Owner.Name'));
            result.rows.add(row);
        }

        return result;
    }

    private static void addSelectFieldIfValid(
        List<String> selectFields,
        String fieldApiName,
        Map<String, Schema.SObjectField> fields
    ) {
        if (String.isBlank(fieldApiName) || fieldApiName.contains('.')) {
            return;
        }
        if (fields.containsKey(fieldApiName) && !selectFields.contains(fieldApiName)) {
            selectFields.add(fieldApiName);
        }
    }

    private static String buildWhereClause(
        PSGWorkspaceConfig config,
        String searchText,
        Map<String, Schema.SObjectField> fields
    ) {
        List<String> clauses = new List<String>();
        if (!String.isBlank(config.defaultWhereClause)) {
            clauses.add(config.defaultWhereClause);
        }

        if (!String.isBlank(searchText)) {
            String searchLike = '%' + String.escapeSingleQuotes(searchText.trim()) + '%';
            List<String> searchClauses = new List<String>();
            for (String searchField : config.searchFields) {
                if (String.isBlank(searchField) || searchField.contains('.')) {
                    continue;
                }
                if (!fields.containsKey(searchField)) {
                    continue;
                }
                Schema.DescribeFieldResult fieldDescribe = fields.get(searchField).getDescribe();
                if (PSGQueryAccessUtil.isSearchableField(fieldDescribe)) {
                    searchClauses.add(searchField + ' LIKE \'' + searchLike + '\'');
                }
            }
            if (!searchClauses.isEmpty()) {
                clauses.add('(' + String.join(searchClauses, ' OR ') + ')');
            }
        }

        return clauses.isEmpty() ? null : String.join(clauses, ' AND ');
    }

    private static String resolveSortClause(
        PSGWorkspaceConfig config,
        Map<String, Schema.SObjectField> fields,
        String sortBy,
        String sortDirection
    ) {
        String safeSortBy = config.sortableFields != null && config.sortableFields.contains(sortBy)
            ? sortBy
            : config.defaultSortField;
        String direction = (sortDirection != null && sortDirection.toLowerCase() == 'asc') ? 'ASC' : 'DESC';
        String requestedField = config.getFieldApiName(safeSortBy);
        String fallbackField = config.getFieldApiName(config.defaultSortField);

        if (String.isBlank(fallbackField) || !isSortableFieldPath(fallbackField, fields)) {
            fallbackField = fields.containsKey('LastModifiedDate') ? 'LastModifiedDate' : 'Id';
        }

        if (String.isBlank(requestedField) || !isSortableFieldPath(requestedField, fields)) {
            return fallbackField + ' DESC NULLS LAST, Id DESC';
        }

        String orderBy = requestedField + ' ' + direction;
        if (direction == 'DESC') {
            orderBy += ' NULLS LAST';
        }
        return orderBy + ', Id DESC';
    }

    private static Boolean isSortableFieldPath(String fieldPath, Map<String, Schema.SObjectField> fields) {
        if (String.isBlank(fieldPath)) {
            return false;
        }
        if (fieldPath == 'Owner.Name') {
            return fields.containsKey('OwnerId');
        }
        if (!fields.containsKey(fieldPath)) {
            return false;
        }
        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldPath).getDescribe();
        return fieldDescribe.isAccessible() && fieldDescribe.isSortable();
    }

    private static Object getFieldValue(SObject source, String fieldPath) {
        if (source == null || String.isBlank(fieldPath)) {
            return null;
        }
        if (!fieldPath.contains('.')) {
            return source.get(fieldPath);
        }

        List<String> parts = fieldPath.split('\\.');
        if (parts.size() != 2) {
            return null;
        }

        SObject related = source.getSObject(parts[0]);
        return related == null ? null : related.get(parts[1]);
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

    private static String toDisplay(Object value) {
        if (value == null) {
            return '--';
        }
        if (value instanceof Boolean) {
            return ((Boolean) value) ? 'Active' : 'Inactive';
        }
        String text = String.valueOf(value);
        return String.isBlank(text) ? '--' : text;
    }
}