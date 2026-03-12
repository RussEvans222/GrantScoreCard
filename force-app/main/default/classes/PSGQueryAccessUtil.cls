public with sharing class PSGQueryAccessUtil {
    @TestVisible
    public static Map<String, Set<String>> TEST_FORCED_REMOVED_FIELDS_BY_OBJECT;

    private static Map<String, Schema.SObjectType> cachedGlobalDescribe;

    public static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (cachedGlobalDescribe == null) {
            cachedGlobalDescribe = Schema.getGlobalDescribe();
        }
        return cachedGlobalDescribe;
    }

    public static Schema.DescribeSObjectResult safeDescribeLookup(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        Schema.SObjectType objectToken = getGlobalDescribe().get(objectApiName);
        return objectToken == null ? null : objectToken.getDescribe();
    }

    public static Boolean isSearchableField(Schema.DescribeFieldResult fieldDescribe) {
        return fieldDescribe != null && fieldDescribe.isAccessible() && fieldDescribe.isFilterable();
    }

    public static Integer normalizePageSize(Integer pageSize) {
        Integer normalized = pageSize == null || pageSize <= 0 ? 25 : pageSize;
        return Math.min(normalized, 200);
    }

    public static Integer normalizePageNumber(Integer pageNumber) {
        return pageNumber == null || pageNumber <= 0 ? 1 : pageNumber;
    }

    public static Boolean hasRemovedFieldsForObject(
        Map<String, Set<String>> removedFieldsByObject,
        String objectApiName
    ) {
        if (removedFieldsByObject != null && !removedFieldsByObject.isEmpty()) {
            for (String objectKey : removedFieldsByObject.keySet()) {
                if (String.isBlank(objectKey)) {
                    continue;
                }
                if (objectKey.equalsIgnoreCase(objectApiName)) {
                    Set<String> removedFields = removedFieldsByObject.get(objectKey);
                    if (removedFields != null && !removedFields.isEmpty()) {
                        return true;
                    }
                }
            }
        }

        if (Test.isRunningTest() && TEST_FORCED_REMOVED_FIELDS_BY_OBJECT != null) {
            Set<String> forcedFields = TEST_FORCED_REMOVED_FIELDS_BY_OBJECT.get(objectApiName);
            return forcedFields != null && !forcedFields.isEmpty();
        }

        return false;
    }

    @TestVisible
    public static void clearTestOverrides() {
        TEST_FORCED_REMOVED_FIELDS_BY_OBJECT = null;
    }
}
