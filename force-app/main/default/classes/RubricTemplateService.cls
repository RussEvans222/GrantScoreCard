public with sharing class RubricTemplateService {
    private static final String TEMPLATE_STATUS_DRAFT = 'Draft';

    public static Id createInitialTemplate(Id fundingOpportunityId) {
        if (fundingOpportunityId == null) {
            return null;
        }

        Evaluation_Template__c template = new Evaluation_Template__c(
            Active__c = true,
            Status__c = TEMPLATE_STATUS_DRAFT,
            Version__c = 1
        );
        insert template;

        template.Version_Key__c = buildVersionKey(template.Id, 1);
        update template;
        return template.Id;
    }

    public static Id cloneTemplate(Id oldTemplateId) {
        if (oldTemplateId == null) {
            return null;
        }

        Evaluation_Template__c sourceTemplate = [
            SELECT Id, Root_Template__c
            FROM Evaluation_Template__c
            WHERE Id = :oldTemplateId
            LIMIT 1
        ];

        Id rootId = (sourceTemplate.Root_Template__c != null && sourceTemplate.Root_Template__c != sourceTemplate.Id)
            ? sourceTemplate.Root_Template__c
            : sourceTemplate.Id;
        // Lock the root template row to reduce concurrent version collisions when multiple admins clone at once.
        List<Evaluation_Template__c> lockedRoot = [
            SELECT Id
            FROM Evaluation_Template__c
            WHERE Id = :rootId
            LIMIT 1
            FOR UPDATE
        ];

        Integer nextVersion = getNextVersion(rootId);
        Evaluation_Template__c newTemplate = new Evaluation_Template__c(
            Active__c = true,
            Status__c = TEMPLATE_STATUS_DRAFT,
            Root_Template__c = rootId,
            Version__c = nextVersion,
            Version_Key__c = buildVersionKey(rootId, nextVersion)
        );

        try {
            insert newTemplate;
        } catch (DmlException dmlEx) {
            // Retry once if a concurrent insert grabbed the same Version_Key__c between MAX(version) and insert.
            if (!isVersionKeyCollision(dmlEx)) {
                throw dmlEx;
            }
            Integer retryVersion = getNextVersion(rootId);
            newTemplate.Version__c = retryVersion;
            newTemplate.Version_Key__c = buildVersionKey(rootId, retryVersion);
            insert newTemplate;
        }

        List<Evaluation_Template_Criterion__c> sourceCriteria = [
            SELECT Criterion_Key__c,
                   Section_Key__c,
                   Section_Name__c,
                   Section_Order__c,
                   Label__c,
                   Description__c,
                   Weight__c,
                   Required__c,
                   Display_Order__c,
                   Min_Score__c,
                   Max_Score__c,
                   IsCustom__c,
                   SourceLibraryCriterion__c
            FROM Evaluation_Template_Criterion__c
            WHERE Evaluation_Template__c = :sourceTemplate.Id
            ORDER BY Section_Order__c ASC NULLS LAST, Display_Order__c ASC NULLS LAST, CreatedDate ASC
        ];

        if (!sourceCriteria.isEmpty()) {
            List<Evaluation_Template_Criterion__c> clonedCriteria = new List<Evaluation_Template_Criterion__c>();
            Set<String> usedKeys = new Set<String>();
            for (Evaluation_Template_Criterion__c row : sourceCriteria) {
                String clonedCriterionKey = buildClonedCriterionKey(
                    row.Criterion_Key__c,
                    Integer.valueOf(newTemplate.Version__c),
                    usedKeys
                );
                clonedCriteria.add(new Evaluation_Template_Criterion__c(
                    Evaluation_Template__c = newTemplate.Id,
                    Criterion_Key__c = clonedCriterionKey,
                    Section_Key__c = row.Section_Key__c,
                    Section_Name__c = row.Section_Name__c,
                    Section_Order__c = row.Section_Order__c,
                    Label__c = row.Label__c,
                    Description__c = row.Description__c,
                    Weight__c = row.Weight__c,
                    Required__c = row.Required__c,
                    Display_Order__c = row.Display_Order__c,
                    Min_Score__c = row.Min_Score__c,
                    Max_Score__c = row.Max_Score__c,
                    IsCustom__c = row.IsCustom__c,
                    SourceLibraryCriterion__c = row.SourceLibraryCriterion__c
                ));
            }
            insert clonedCriteria;
        }

        return newTemplate.Id;
    }

    public static List<String> generateCustomKeys(Id templateId, Integer count) {
        if (templateId == null || count == null || count <= 0) {
            return new List<String>();
        }

        Evaluation_Template__c templateRow = [
            SELECT Id, Root_Template__c, Version__c
            FROM Evaluation_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        Id rootId = templateRow.Root_Template__c != null ? templateRow.Root_Template__c : templateRow.Id;
        Integer versionValue = templateRow.Version__c == null ? 1 : Integer.valueOf(templateRow.Version__c);
        String rootShort = String.valueOf(rootId).left(8);

        Set<String> uniqueKeys = new Set<String>();
        List<String> generated = new List<String>();
        Integer index = 1;
        while (generated.size() < count) {
            Long randomLong = Crypto.getRandomLong();
            String randomHex = EncodingUtil.convertToHex(Blob.valueOf(String.valueOf(randomLong))).right(8);
            // Include root/version/index/random segments so keys are human-traceable and collision resistant.
            String key = 'CUS-' + rootShort + '-v' + versionValue + '-i' + index + '-r' + randomHex;
            if (!uniqueKeys.contains(key)) {
                uniqueKeys.add(key);
                generated.add(key);
                index++;
            }
        }
        return generated;
    }

    public static String normalizeCriteriaJson(String criteriaJson) {
        if (String.isBlank(criteriaJson)) {
            return '[]';
        }
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(criteriaJson);
        return JSON.serialize(parsed);
    }

    private static Integer getNextVersion(Id rootId) {
        AggregateResult[] result = [
            SELECT MAX(Version__c) maxVersion
            FROM Evaluation_Template__c
            WHERE Root_Template__c = :rootId
            OR Id = :rootId
        ];
        Decimal maxVersion = (Decimal) result[0].get('maxVersion');
        return maxVersion == null ? 1 : Integer.valueOf(maxVersion) + 1;
    }

    private static String buildVersionKey(Id rootId, Integer versionValue) {
        return String.valueOf(rootId) + '-v' + String.valueOf(versionValue);
    }

    private static Boolean isVersionKeyCollision(DmlException ex) {
        String message = ex.getMessage();
        return message != null && message.contains('Version_Key__c');
    }

    private static String buildClonedCriterionKey(String sourceKey, Integer versionNumber, Set<String> usedKeys) {
        String base = String.isBlank(sourceKey) ? 'CRIT' : sourceKey;
        String versionSuffix = '-v' + String.valueOf(versionNumber);
        String keyCandidate = trimToLength(base + versionSuffix, 255);
        Integer counter = 1;
        while (usedKeys.contains(keyCandidate)) {
            keyCandidate = trimToLength(base + versionSuffix + '-' + String.valueOf(counter), 255);
            counter++;
        }
        usedKeys.add(keyCandidate);
        return keyCandidate;
    }

    private static String trimToLength(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        if (maxLen == null || value.length() <= maxLen) {
            return value;
        }
        return value.substring(0, maxLen);
    }
}
