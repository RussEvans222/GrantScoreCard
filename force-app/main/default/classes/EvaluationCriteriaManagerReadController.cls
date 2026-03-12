/*
SYSTEM OVERVIEW

This controller provides read-heavy data for the Evaluation Criteria Manager app.
It is designed for admin workspaces where Lightning Web Components need:
- dashboard metrics,
- criteria library rows,
- template usage mappings,
- bundle options,
- criterion detail drill-down.

Data flow pattern:
LWC -> @AuraEnabled Apex method -> SOQL/aggregate queries -> lightweight DTOs -> LWC render.
*/
public with sharing class EvaluationCriteriaManagerReadController {
    public class HomeMetrics {
        @AuraEnabled public Integer activeCriteria;
        @AuraEnabled public Integer templatesUsingCriteria;
        @AuraEnabled public Integer totalTemplates;
        @AuraEnabled public Integer criteriaNeedingReview;
    }

    public class HomeRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String detail;
    }

    public class HomeDashboardData {
        @AuraEnabled public HomeMetrics metrics;
        @AuraEnabled public List<HomeRow> recentCriteriaUpdates;
        @AuraEnabled public List<HomeRow> topUsedCriteria;
        @AuraEnabled public String aiInsightText;
        @AuraEnabled public String aiInsightSecondaryText;
        @AuraEnabled public Boolean hasFrameworkAnalysis;
        @AuraEnabled public Id latestAnalyzedTemplateId;
        @AuraEnabled public String helperNote;
    }

    public class CriteriaRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Id bundleId;
        @AuraEnabled public String bundleName;
        @AuraEnabled public Decimal defaultWeight;
        @AuraEnabled public String status;
        @AuraEnabled public String version;
        @AuraEnabled public Integer templatesUsing;
        @AuraEnabled public String description;
        @AuraEnabled public String scoringGuidance;
        @AuraEnabled public String aiNotes;
        @AuraEnabled public Boolean active;
        @AuraEnabled public List<CriterionUsageRow> recentApplicationUsages;
    }

    public class CriterionUsageRow {
        @AuraEnabled public Id applicationFormId;
        @AuraEnabled public String applicationFormName;
        @AuraEnabled public Id evaluationId;
        @AuraEnabled public String evaluationName;
        @AuraEnabled public String evaluationStatus;
        @AuraEnabled public String evaluationTemplateName;
        @AuraEnabled public String usedOn;
    }

    public class CriteriaDataResponse {
        @AuraEnabled public List<CriteriaRow> rows;
        @AuraEnabled public String helperNote;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer returnedCount;
    }

    public class TemplateRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String displayName;
        @AuraEnabled public String displayLabelFieldApiName;
        @AuraEnabled public Boolean displayNameEditable;
        @AuraEnabled public String status;
        @AuraEnabled public String version;
        @AuraEnabled public Integer criteriaCount;
        @AuraEnabled public String lastUpdated;
    }

    public class TemplateDisplayNameUpdate {
        @AuraEnabled public Id templateId;
        @AuraEnabled public String displayName;
    }

    public class TemplateDisplayNameSaveResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public Integer updatedCount;
    }

    public class TemplateUsageRow {
        @AuraEnabled public Id criterionId;
        @AuraEnabled public Id templateId;
        @AuraEnabled public String criterionName;
        @AuraEnabled public String templateName;
        @AuraEnabled public String templateDisplayName;
        @AuraEnabled public String templateStatus;
        @AuraEnabled public String templateVersion;
        @AuraEnabled public Boolean versionMismatch;
        @AuraEnabled public String usageState;
    }

    public class TemplateOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
    }

    public class BundleOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
    }

    public class CriterionLookupOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
    }

    @AuraEnabled(cacheable=true)
    public static HomeDashboardData getHomeDashboardData() {
        // Dashboard method combines multiple summary queries into one payload
        // so the home page can load quickly with a single wire call.
        HomeDashboardData out = new HomeDashboardData();
        out.metrics = new HomeMetrics();
        out.recentCriteriaUpdates = new List<HomeRow>();
        out.topUsedCriteria = new List<HomeRow>();
        out.aiInsightText = 'AI-assisted framework review is available for evaluation templates.';
        out.aiInsightSecondaryText = 'Run framework analysis from Criteria Insights to generate governance recommendations.';
        out.hasFrameworkAnalysis = false;
        out.latestAnalyzedTemplateId = null;
        out.helperNote = 'Some fields are optional and will display as -- until schema is finalized.';

        Map<String, Schema.SObjectField> critFields = Schema.SObjectType.Criterion_Library__c.fields.getMap();
        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        Map<String, Schema.SObjectField> etcFields = Schema.SObjectType.Evaluation_Template_Criterion__c.fields.getMap();

        out.metrics.totalTemplates = (Integer) Database.countQuery('SELECT COUNT() FROM Evaluation_Template__c');
        if (critFields.containsKey('Active__c')) {
            out.metrics.activeCriteria = (Integer) Database.countQuery('SELECT COUNT() FROM Criterion_Library__c WHERE Active__c = true');
        }

        if (critFields.containsKey('Requires_Review__c')) {
            out.metrics.criteriaNeedingReview = (Integer) Database.countQuery('SELECT COUNT() FROM Criterion_Library__c WHERE Requires_Review__c = true');
        }

        if (etcFields.containsKey('SourceLibraryCriterion__c')) {
            List<AggregateResult> usageAgg = [
                SELECT COUNT_DISTINCT(Evaluation_Template__c) templateCount
                FROM Evaluation_Template_Criterion__c
                WHERE SourceLibraryCriterion__c != null
            ];
            out.metrics.templatesUsingCriteria = usageAgg.isEmpty() ? 0 : (Integer) usageAgg[0].get('templateCount');
        } else {
            out.metrics.templatesUsingCriteria = (Integer) Database.countQuery('SELECT COUNT_DISTINCT(Evaluation_Template__c) FROM Evaluation_Template_Criterion__c');
        }

        String recentQuery = 'SELECT Id, Label__c, LastModifiedDate';
        if (critFields.containsKey('DefaultWeight__c')) {
            recentQuery += ', DefaultWeight__c';
        }
        recentQuery += ' FROM Criterion_Library__c ORDER BY LastModifiedDate DESC LIMIT 5';
        for (SObject row : Database.query(recentQuery)) {
            HomeRow item = new HomeRow();
            item.id = (Id) row.get('Id');
            item.name = asString(row.get('Label__c'));
            item.subtitle = 'Updated ' + String.valueOf(row.get('LastModifiedDate'));
            item.detail = critFields.containsKey('DefaultWeight__c') ? toDisplay(row.get('DefaultWeight__c')) : '--';
            out.recentCriteriaUpdates.add(item);
        }

        if (etcFields.containsKey('SourceLibraryCriterion__c')) {
            List<AggregateResult> topAgg = [
                SELECT SourceLibraryCriterion__c criterionId, COUNT(Id) cnt
                FROM Evaluation_Template_Criterion__c
                WHERE SourceLibraryCriterion__c != null
                GROUP BY SourceLibraryCriterion__c
                ORDER BY COUNT(Id) DESC
                LIMIT 5
            ];
            Set<Id> criterionIds = new Set<Id>();
            for (AggregateResult ar : topAgg) {
                criterionIds.add((Id) ar.get('criterionId'));
            }
            Map<Id, Criterion_Library__c> criteriaById = criterionIds.isEmpty()
                ? new Map<Id, Criterion_Library__c>()
                : new Map<Id, Criterion_Library__c>([
                    SELECT Id, Label__c, Description__c
                    FROM Criterion_Library__c
                    WHERE Id IN :criterionIds
                ]);

            for (AggregateResult ar : topAgg) {
                Id criterionId = (Id) ar.get('criterionId');
                Criterion_Library__c criterion = criteriaById.get(criterionId);
                if (criterion == null) {
                    continue;
                }
                HomeRow item = new HomeRow();
                item.id = criterion.Id;
                item.name = criterion.Label__c;
                item.subtitle = 'Used in ' + String.valueOf(ar.get('cnt')) + ' template rows';
                item.detail = String.isBlank(criterion.Description__c) ? '--' : criterion.Description__c;
                out.topUsedCriteria.add(item);
            }
        }

        if (templateFields.containsKey('Framework_Health_Score__c')) {
            String reviewedSoql =
                'SELECT Id, Name, Framework_Health_Score__c ' +
                'FROM Evaluation_Template__c ' +
                'WHERE Framework_Health_Score__c != null ';
            if (templateFields.containsKey('Framework_Last_Reviewed__c')) {
                reviewedSoql += 'ORDER BY Framework_Last_Reviewed__c DESC NULLS LAST, LastModifiedDate DESC ';
            } else {
                reviewedSoql += 'ORDER BY LastModifiedDate DESC ';
            }
            reviewedSoql += 'LIMIT 1';

            List<SObject> reviewed = Database.query(reviewedSoql);
            if (!reviewed.isEmpty()) {
                out.hasFrameworkAnalysis = true;
                out.latestAnalyzedTemplateId = (Id) reviewed[0].get('Id');
                out.aiInsightText = 'Latest analyzed template: ' + String.valueOf(reviewed[0].get('Name')) +
                    ' (health score ' + String.valueOf(reviewed[0].get('Framework_Health_Score__c')) + ').';
                out.aiInsightSecondaryText = 'Open Criteria Insights to review issues, recommendations, and apply actions.';
            }
        } else if (!out.topUsedCriteria.isEmpty()) {
            out.aiInsightText = 'Top reused criterion: ' + out.topUsedCriteria[0].name + '.';
            out.aiInsightSecondaryText = 'Run AI framework review to detect overlap, imbalance, and improvement opportunities.';
        } else if (out.metrics.totalTemplates != null && out.metrics.totalTemplates > 0) {
            out.aiInsightText = 'Templates are available but no framework analysis metrics are stored yet.';
            out.aiInsightSecondaryText = 'Analyze an evaluation template to populate AI health and recommendation insights.';
        } else {
            out.aiInsightText = 'No evaluation templates found yet.';
            out.aiInsightSecondaryText = 'Create a template first, then run AI framework review from Criteria Insights.';
        }

        if (out.metrics.criteriaNeedingReview == null && critFields.containsKey('Requires_Review__c')) {
            out.metrics.criteriaNeedingReview = 0;
        }
        if (out.metrics.activeCriteria == null) {
            out.metrics.activeCriteria = 0;
        }
        if (out.metrics.templatesUsingCriteria == null) {
            out.metrics.templatesUsingCriteria = 0;
        }
        if (out.metrics.totalTemplates == null) {
            out.metrics.totalTemplates = 0;
        }

        return out;
    }

    @AuraEnabled(cacheable=true)
    public static CriteriaDataResponse getCriteriaLibraryData(String searchText, String categoryFilter, String activeFilter, String versionFilter) {
        // Returns criteria table rows plus helper text for new developers/admins.
        CriteriaDataResponse response = new CriteriaDataResponse();
        response.rows = new List<CriteriaRow>();
        response.helperNote = 'Manage criteria here: assign bundles, create new bundles, and remove criteria from the library.';
        response.totalCount = 0;
        response.returnedCount = 0;

        Map<String, Schema.SObjectField> critFields = Schema.SObjectType.Criterion_Library__c.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'Label__c', 'Description__c' };
        if (critFields.containsKey('DefaultWeight__c')) selectFields.add('DefaultWeight__c');
        if (critFields.containsKey('Active__c')) selectFields.add('Active__c');
        if (critFields.containsKey('Category__c')) selectFields.add('Category__c');
        if (critFields.containsKey('Version__c')) selectFields.add('Version__c');
        if (critFields.containsKey('Recommended_Scoring_Guidance__c')) selectFields.add('Recommended_Scoring_Guidance__c');
        if (critFields.containsKey('AI_Evaluation_Guidance__c')) selectFields.add('AI_Evaluation_Guidance__c');
        if (critFields.containsKey('Section_Library__c')) {
            selectFields.add('Section_Library__c');
            selectFields.add('Section_Library__r.Label__c');
        }

        // Query is built dynamically so optional fields can be skipped safely
        // if they do not exist in a target org.
        String baseQuery = 'SELECT ' + String.join(selectFields, ',') + ' FROM Criterion_Library__c';
        List<String> whereParts = new List<String>();
        if (!String.isBlank(searchText)) {
            String safe = '%' + String.escapeSingleQuotes(searchText.trim()) + '%';
            whereParts.add('(Label__c LIKE \'' + safe + '\' OR Description__c LIKE \'' + safe + '\')');
        }

        if (critFields.containsKey('Category__c') && !String.isBlank(categoryFilter) && categoryFilter != 'All') {
            whereParts.add('Category__c = \'' + String.escapeSingleQuotes(categoryFilter) + '\'');
        }

        if (critFields.containsKey('Version__c') && !String.isBlank(versionFilter) && versionFilter != 'All') {
            whereParts.add('Version__c = \'' + String.escapeSingleQuotes(versionFilter) + '\'');
        }

        if (critFields.containsKey('Active__c') && !String.isBlank(activeFilter) && activeFilter != 'All') {
            if (activeFilter == 'Active') {
                whereParts.add('Active__c = true');
            } else if (activeFilter == 'Inactive') {
                whereParts.add('Active__c = false');
            }
        }

        String soql = baseQuery;
        String whereClause = '';
        if (!whereParts.isEmpty()) {
            whereClause = ' WHERE ' + String.join(whereParts, ' AND ');
            soql += whereClause;
        }
        soql += ' ORDER BY LastModifiedDate DESC';

        response.totalCount = (Integer) Database.countQuery('SELECT COUNT() FROM Criterion_Library__c' + whereClause);

        Map<Id, Integer> templatesUsingByCriterionId = new Map<Id, Integer>();
        if (Schema.SObjectType.Evaluation_Template_Criterion__c.fields.getMap().containsKey('SourceLibraryCriterion__c')) {
            for (AggregateResult ar : [
                SELECT SourceLibraryCriterion__c criterionId, COUNT_DISTINCT(Evaluation_Template__c) templateCount
                FROM Evaluation_Template_Criterion__c
                WHERE SourceLibraryCriterion__c != null
                GROUP BY SourceLibraryCriterion__c
            ]) {
                templatesUsingByCriterionId.put((Id) ar.get('criterionId'), (Integer) ar.get('templateCount'));
            }
        }

        for (SObject row : Database.query(soql)) {
            CriteriaRow out = new CriteriaRow();
            out.id = (Id) row.get('Id');
            out.name = asDisplayString(row.get('Label__c'));
            out.category = critFields.containsKey('Category__c') ? asDisplayString(row.get('Category__c')) : '--';
            out.bundleId = critFields.containsKey('Section_Library__c') ? (Id) row.get('Section_Library__c') : null;
            out.bundleName = (
                critFields.containsKey('Section_Library__c') &&
                row.getSObject('Section_Library__r') != null
            )
                ? asDisplayString(row.getSObject('Section_Library__r').get('Label__c'))
                : '--';
            out.defaultWeight = critFields.containsKey('DefaultWeight__c') ? (Decimal) row.get('DefaultWeight__c') : null;
            Boolean active = critFields.containsKey('Active__c') ? (Boolean) row.get('Active__c') : null;
            out.active = active;
            out.status = active == null ? '--' : (active ? 'Active' : 'Inactive');
            out.version = critFields.containsKey('Version__c') ? asDisplayString(row.get('Version__c')) : '--';
            out.templatesUsing = templatesUsingByCriterionId.containsKey(out.id) ? templatesUsingByCriterionId.get(out.id) : 0;
            out.description = asDisplayString(row.get('Description__c'));
            out.scoringGuidance = critFields.containsKey('Recommended_Scoring_Guidance__c')
                ? asDisplayString(row.get('Recommended_Scoring_Guidance__c'))
                : '--';
            out.aiNotes = critFields.containsKey('AI_Evaluation_Guidance__c')
                ? asDisplayString(row.get('AI_Evaluation_Guidance__c'))
                : '--';
            response.rows.add(out);
        }

        response.returnedCount = response.rows.size();
        response.helperNote =
            'Showing ' + String.valueOf(response.returnedCount) +
            ' of ' + String.valueOf(response.totalCount) +
            ' criteria based on current filters.';

        return response;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateRow> getEvaluationTemplateRows(String searchText) {
        List<TemplateRow> out = new List<TemplateRow>();
        Map<Id, Integer> criteriaCountByTemplate = new Map<Id, Integer>();
        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        String preferredLabelField = findPreferredTemplateLabelField(templateFields);
        Boolean editable = !String.isBlank(preferredLabelField) &&
            templateFields.get(preferredLabelField).getDescribe().isUpdateable();

        for (AggregateResult ar : [
            SELECT Evaluation_Template__c templateId, COUNT(Id) criterionCount
            FROM Evaluation_Template_Criterion__c
            WHERE Evaluation_Template__c != null
            GROUP BY Evaluation_Template__c
        ]) {
            criteriaCountByTemplate.put((Id) ar.get('templateId'), (Integer) ar.get('criterionCount'));
        }

        List<String> whereParts = new List<String>();
        if (!String.isBlank(searchText)) {
            String safe = '%' + String.escapeSingleQuotes(searchText.trim()) + '%';
            whereParts.add('(Name LIKE \'' + safe + '\' OR Description__c LIKE \'' + safe + '\')');
        }

        List<String> selectFields = new List<String>{ 'Id', 'Name', 'Status__c', 'Version__c', 'LastModifiedDate' };
        if (!String.isBlank(preferredLabelField)) {
            selectFields.add(preferredLabelField);
        }
        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Evaluation_Template__c';
        if (!whereParts.isEmpty()) {
            soql += ' WHERE ' + String.join(whereParts, ' AND ');
        }
        soql += ' ORDER BY LastModifiedDate DESC LIMIT 200';

        for (SObject row : Database.query(soql)) {
            TemplateRow t = new TemplateRow();
            t.id = (Id) row.get('Id');
            t.name = asDisplayString(row.get('Name'));
            t.displayName = resolveTemplateDisplayLabel(row, preferredLabelField);
            t.displayLabelFieldApiName = preferredLabelField;
            t.displayNameEditable = editable;
            t.status = asDisplayString(row.get('Status__c'));
            t.version = asDisplayString(row.get('Version__c'));
            t.criteriaCount = criteriaCountByTemplate.containsKey(t.id) ? criteriaCountByTemplate.get(t.id) : 0;
            t.lastUpdated = String.valueOf(row.get('LastModifiedDate'));
            out.add(t);
        }
        return out;
    }

    @AuraEnabled
    public static TemplateDisplayNameSaveResponse saveTemplateDisplayNames(List<TemplateDisplayNameUpdate> updates) {
        TemplateDisplayNameSaveResponse response = new TemplateDisplayNameSaveResponse();
        response.success = false;
        response.message = '';
        response.fieldApiName = null;
        response.updatedCount = 0;

        if (updates == null || updates.isEmpty()) {
            response.message = 'No template display name updates were provided.';
            return response;
        }

        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        String preferredLabelField = findPreferredTemplateLabelField(templateFields);
        if (String.isBlank(preferredLabelField)) {
            response.message = 'No editable template display name field found. Add one of: Display_Name__c, Template_Display_Name__c, User_Facing_Name__c, Label__c.';
            return response;
        }

        Schema.DescribeFieldResult describe = templateFields.get(preferredLabelField).getDescribe();
        if (describe == null || !describe.isUpdateable()) {
            response.message = 'Display name field is not editable for this user due to field-level security.';
            return response;
        }

        List<Evaluation_Template__c> rowsToUpdate = new List<Evaluation_Template__c>();
        for (TemplateDisplayNameUpdate updateReq : updates) {
            if (updateReq == null || updateReq.templateId == null) {
                continue;
            }
            Evaluation_Template__c row = new Evaluation_Template__c(Id = updateReq.templateId);
            String normalized = String.isBlank(updateReq.displayName) ? null : updateReq.displayName.trim();
            row.put(preferredLabelField, normalized);
            rowsToUpdate.add(row);
        }

        if (rowsToUpdate.isEmpty()) {
            response.message = 'No valid template rows were provided for update.';
            return response;
        }

        update rowsToUpdate;
        response.success = true;
        response.fieldApiName = preferredLabelField;
        response.updatedCount = rowsToUpdate.size();
        response.message = 'Template display names updated.';
        return response;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateUsageRow> getTemplateUsageRows(String searchText, Id criterionLibraryId) {
        // This method powers "where is this criterion used?" views.
        // It supports both modern linked rows and legacy label-only rows.
        List<TemplateUsageRow> out = new List<TemplateUsageRow>();
        Map<String, Schema.SObjectField> etcFields = Schema.SObjectType.Evaluation_Template_Criterion__c.fields.getMap();
        Map<String, Schema.SObjectField> criterionFields = Schema.SObjectType.Criterion_Library__c.fields.getMap();
        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        String preferredLabelField = findPreferredTemplateLabelField(templateFields);
        Boolean hasSourceLibrary = etcFields.containsKey('SourceLibraryCriterion__c');
        Boolean hasCriterionVersion = criterionFields.containsKey('Version__c');
        String criterionFilterLabel = null;

        if (criterionLibraryId != null) {
            List<Criterion_Library__c> criterionRows = [
                SELECT Label__c
                FROM Criterion_Library__c
                WHERE Id = :criterionLibraryId
                LIMIT 1
            ];
            if (!criterionRows.isEmpty()) {
                criterionFilterLabel = criterionRows[0].Label__c;
            }
        }

        String soql =
            'SELECT Id, Label__c, Weight__c, Evaluation_Template__c, Evaluation_Template__r.Name, Evaluation_Template__r.Status__c, ' +
            'Evaluation_Template__r.Version__c' +
            (!String.isBlank(preferredLabelField) ? ', Evaluation_Template__r.' + preferredLabelField : '') +
            (hasSourceLibrary
                ? ', SourceLibraryCriterion__c, SourceLibraryCriterion__r.Label__c' +
                  (hasCriterionVersion ? ', SourceLibraryCriterion__r.Version__c' : '')
                : '') +
            ' FROM Evaluation_Template_Criterion__c' +
            ' WHERE Evaluation_Template__c != null';
        if (criterionLibraryId != null) {
            if (hasSourceLibrary && !String.isBlank(criterionFilterLabel)) {
                // Supports both modern linked rows and legacy rows that still only carry Label__c.
                soql += ' AND (SourceLibraryCriterion__c = :criterionLibraryId OR (SourceLibraryCriterion__c = null AND Label__c = :criterionFilterLabel))';
            } else if (hasSourceLibrary) {
                soql += ' AND SourceLibraryCriterion__c = :criterionLibraryId';
            } else if (!String.isBlank(criterionFilterLabel)) {
                soql += ' AND Label__c = :criterionFilterLabel';
            }
        }
        soql +=
            ' ORDER BY Evaluation_Template__r.LastModifiedDate DESC LIMIT 500';

        for (SObject row : Database.query(soql)) {
            String criterionName = asDisplayString(
                hasSourceLibrary && row.getSObject('SourceLibraryCriterion__r') != null
                    ? row.getSObject('SourceLibraryCriterion__r').get('Label__c')
                    : row.get('Label__c')
            );
            String templateName = asDisplayString(row.getSObject('Evaluation_Template__r') == null
                ? null : row.getSObject('Evaluation_Template__r').get('Name'));
            String preferredTemplateName = (
                !String.isBlank(preferredLabelField) && row.getSObject('Evaluation_Template__r') != null
            )
                ? asDisplayString(row.getSObject('Evaluation_Template__r').get(preferredLabelField))
                : '--';

            if (!String.isBlank(searchText)) {
                String q = searchText.toLowerCase();
                String matchTemplateText = preferredTemplateName == '--' ? templateName : preferredTemplateName;
                if (!(criterionName.toLowerCase().contains(q) || matchTemplateText.toLowerCase().contains(q))) {
                    continue;
                }
            }

            TemplateUsageRow usage = new TemplateUsageRow();
            Id criterionIdToReturn = hasSourceLibrary ? (Id) row.get('SourceLibraryCriterion__c') : null;
            if (
                criterionIdToReturn == null &&
                criterionLibraryId != null &&
                !String.isBlank(criterionFilterLabel) &&
                criterionName == criterionFilterLabel
            ) {
                criterionIdToReturn = criterionLibraryId;
            }
            usage.criterionId = criterionIdToReturn;
            usage.templateId = row.getSObject('Evaluation_Template__r') == null
                ? null
                : (Id) row.get('Evaluation_Template__c');
            usage.criterionName = criterionName;
            usage.templateName = templateName;
            usage.templateStatus = asDisplayString(row.getSObject('Evaluation_Template__r') == null
                ? null : row.getSObject('Evaluation_Template__r').get('Status__c'));
            usage.templateVersion = asDisplayString(row.getSObject('Evaluation_Template__r') == null
                ? null : row.getSObject('Evaluation_Template__r').get('Version__c'));
            usage.templateDisplayName = preferredTemplateName == '--' ? templateName : preferredTemplateName;
            usage.usageState = usage.templateStatus == '--' ? 'Unknown' : usage.templateStatus;

            if (hasSourceLibrary && hasCriterionVersion && row.getSObject('SourceLibraryCriterion__r') != null) {
                String criterionVersion = asDisplayString(row.getSObject('SourceLibraryCriterion__r').get('Version__c'));
                usage.versionMismatch = usage.templateVersion != '--' && criterionVersion != '--' && usage.templateVersion != criterionVersion;
            } else {
                usage.versionMismatch = false;
            }

            out.add(usage);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateOption> getEvaluationTemplateOptions() {
        List<TemplateOption> out = new List<TemplateOption>();
        Map<String, Schema.SObjectField> templateFields = Schema.SObjectType.Evaluation_Template__c.fields.getMap();
        String preferredLabelField = findPreferredTemplateLabelField(templateFields);
        List<String> selectFields = new List<String>{ 'Id', 'Name', 'Status__c', 'Version__c', 'LastModifiedDate' };
        if (!String.isBlank(preferredLabelField)) {
            selectFields.add(preferredLabelField);
        }
        String soql = 'SELECT ' + String.join(selectFields, ',') +
            ' FROM Evaluation_Template__c ORDER BY LastModifiedDate DESC LIMIT 200';
        for (SObject row : Database.query(soql)) {
            TemplateOption option = new TemplateOption();
            option.id = (Id) row.get('Id');
            option.label = resolveTemplateDisplayLabel(row, preferredLabelField);
            out.add(option);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<CriterionLookupOption> getCriterionLookupOptions(String searchText) {
        List<CriterionLookupOption> out = new List<CriterionLookupOption>();
        if (String.isBlank(searchText) || searchText.trim().length() < 2) {
            return out;
        }
        String q = '%' + String.escapeSingleQuotes(searchText.trim()) + '%';
        for (Criterion_Library__c row : [
            SELECT Id, Label__c
            FROM Criterion_Library__c
            WHERE Label__c LIKE :q
            ORDER BY Label__c ASC
            LIMIT 25
        ]) {
            CriterionLookupOption option = new CriterionLookupOption();
            option.id = row.Id;
            option.label = row.Label__c;
            out.add(option);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static CriteriaRow getCriterionRecordPanelData(Id criterionId) {
        // Detail payload for right-side panel in criteria workspace.
        // Includes recent real-world usage from evaluation score history.
        if (criterionId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> critFields = Schema.SObjectType.Criterion_Library__c.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'Label__c', 'Description__c' };
        if (critFields.containsKey('DefaultWeight__c')) selectFields.add('DefaultWeight__c');
        if (critFields.containsKey('Active__c')) selectFields.add('Active__c');
        if (critFields.containsKey('Category__c')) selectFields.add('Category__c');
        if (critFields.containsKey('Version__c')) selectFields.add('Version__c');
        if (critFields.containsKey('Recommended_Scoring_Guidance__c')) selectFields.add('Recommended_Scoring_Guidance__c');
        if (critFields.containsKey('AI_Evaluation_Guidance__c')) selectFields.add('AI_Evaluation_Guidance__c');
        if (critFields.containsKey('Section_Library__c')) {
            selectFields.add('Section_Library__c');
            selectFields.add('Section_Library__r.Label__c');
        }

        String soql = 'SELECT ' + String.join(selectFields, ',') + ' FROM Criterion_Library__c WHERE Id = :criterionId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) {
            return null;
        }

        SObject row = rows[0];
        CriteriaRow out = new CriteriaRow();
        out.id = (Id) row.get('Id');
        out.name = asDisplayString(row.get('Label__c'));
        out.category = critFields.containsKey('Category__c') ? asDisplayString(row.get('Category__c')) : '--';
        out.bundleId = critFields.containsKey('Section_Library__c') ? (Id) row.get('Section_Library__c') : null;
        out.bundleName = (
            critFields.containsKey('Section_Library__c') &&
            row.getSObject('Section_Library__r') != null
        )
            ? asDisplayString(row.getSObject('Section_Library__r').get('Label__c'))
            : '--';
        out.defaultWeight = critFields.containsKey('DefaultWeight__c') ? (Decimal) row.get('DefaultWeight__c') : null;
        Boolean active = critFields.containsKey('Active__c') ? (Boolean) row.get('Active__c') : null;
        out.active = active;
        out.status = active == null ? '--' : (active ? 'Active' : 'Inactive');
        out.version = critFields.containsKey('Version__c') ? asDisplayString(row.get('Version__c')) : '--';
        out.description = asDisplayString(row.get('Description__c'));
        out.scoringGuidance = critFields.containsKey('Recommended_Scoring_Guidance__c')
            ? asDisplayString(row.get('Recommended_Scoring_Guidance__c'))
            : '--';
        out.aiNotes = critFields.containsKey('AI_Evaluation_Guidance__c')
            ? asDisplayString(row.get('AI_Evaluation_Guidance__c'))
            : '--';
        out.recentApplicationUsages = new List<CriterionUsageRow>();

        if (Schema.SObjectType.Evaluation_Template_Criterion__c.fields.getMap().containsKey('SourceLibraryCriterion__c')) {
            List<AggregateResult> usage = [
                SELECT COUNT_DISTINCT(Evaluation_Template__c) templateCount
                FROM Evaluation_Template_Criterion__c
                WHERE SourceLibraryCriterion__c = :criterionId
            ];
            out.templatesUsing = usage.isEmpty() ? 0 : (Integer) usage[0].get('templateCount');

            Set<String> criterionKeys = new Set<String>();
            for (Evaluation_Template_Criterion__c templateCriterion : [
                SELECT Criterion_Key__c
                FROM Evaluation_Template_Criterion__c
                WHERE SourceLibraryCriterion__c = :criterionId
                AND Criterion_Key__c != null
                LIMIT 500
            ]) {
                criterionKeys.add(templateCriterion.Criterion_Key__c);
            }

            if (!criterionKeys.isEmpty()) {
                for (Evaluation_Criterion_Score__c scoreRow : [
                    SELECT Id,
                           Criterion_Key__c,
                           LastModifiedDate,
                           ApplicationFormEvaluation__c,
                           ApplicationFormEvaluation__r.Name,
                           ApplicationFormEvaluation__r.Status,
                           ApplicationFormEvaluation__r.ApplicationFormId,
                           ApplicationFormEvaluation__r.ApplicationForm.Name,
                           ApplicationFormEvaluation__r.Evaluation_Template__r.Name
                    FROM Evaluation_Criterion_Score__c
                    WHERE Criterion_Key__c IN :criterionKeys
                    AND ApplicationFormEvaluation__c != null
                    ORDER BY LastModifiedDate DESC
                    LIMIT 12
                ]) {
                    CriterionUsageRow usageRow = new CriterionUsageRow();
                    usageRow.evaluationId = scoreRow.ApplicationFormEvaluation__c;
                    usageRow.evaluationName = scoreRow.ApplicationFormEvaluation__r == null
                        ? '--'
                        : asDisplayString(scoreRow.ApplicationFormEvaluation__r.Name);
                    usageRow.evaluationStatus = scoreRow.ApplicationFormEvaluation__r == null
                        ? '--'
                        : asDisplayString(scoreRow.ApplicationFormEvaluation__r.Status);
                    usageRow.applicationFormId = scoreRow.ApplicationFormEvaluation__r == null
                        ? null
                        : scoreRow.ApplicationFormEvaluation__r.ApplicationFormId;
                    usageRow.applicationFormName = (
                        scoreRow.ApplicationFormEvaluation__r != null &&
                        scoreRow.ApplicationFormEvaluation__r.ApplicationForm != null
                    )
                        ? asDisplayString(scoreRow.ApplicationFormEvaluation__r.ApplicationForm.Name)
                        : '--';
                    usageRow.evaluationTemplateName = (
                        scoreRow.ApplicationFormEvaluation__r != null &&
                        scoreRow.ApplicationFormEvaluation__r.Evaluation_Template__r != null
                    )
                        ? asDisplayString(scoreRow.ApplicationFormEvaluation__r.Evaluation_Template__r.Name)
                        : '--';
                    usageRow.usedOn = String.valueOf(scoreRow.LastModifiedDate);
                    out.recentApplicationUsages.add(usageRow);
                }
            }
        } else {
            out.templatesUsing = 0;
        }

        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<BundleOption> getBundleOptions() {
        List<BundleOption> out = new List<BundleOption>();
        Map<String, Schema.SObjectField> sectionFields = Schema.SObjectType.Section_Library__c.fields.getMap();

        String soql = 'SELECT Id, Label__c';
        if (sectionFields.containsKey('Active__c')) {
            soql += ', Active__c';
        }
        if (sectionFields.containsKey('DisplayOrder__c')) {
            soql += ', DisplayOrder__c';
        }
        soql += ' FROM Section_Library__c';
        if (sectionFields.containsKey('Active__c')) {
            soql += ' WHERE Active__c = true';
        }
        if (sectionFields.containsKey('DisplayOrder__c')) {
            soql += ' ORDER BY DisplayOrder__c ASC NULLS LAST, Label__c ASC';
        } else {
            soql += ' ORDER BY Label__c ASC';
        }

        for (SObject row : Database.query(soql)) {
            BundleOption option = new BundleOption();
            option.id = (Id) row.get('Id');
            option.label = asDisplayString(row.get('Label__c'));
            out.add(option);
        }
        return out;
    }

    @AuraEnabled
    public static Id createBundle(String bundleLabel) {
        if (String.isBlank(bundleLabel)) {
            throw new AuraHandledException('Bundle name is required.');
        }

        String trimmed = bundleLabel.trim();
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Section_Library__c.fields.getMap();

        for (Section_Library__c existing : [
            SELECT Id
            FROM Section_Library__c
            WHERE Label__c = :trimmed
            LIMIT 1
        ]) {
            return existing.Id;
        }

        Section_Library__c newBundle = new Section_Library__c();

        if (fields.containsKey('Label__c') && fields.get('Label__c').getDescribe().isCreateable()) {
            newBundle.Label__c = trimmed;
        }
        if (fields.containsKey('DeveloperKey__c') && fields.get('DeveloperKey__c').getDescribe().isCreateable()) {
            newBundle.DeveloperKey__c = normalizeDeveloperKey(trimmed);
        }
        if (fields.containsKey('Active__c') && fields.get('Active__c').getDescribe().isCreateable()) {
            newBundle.Active__c = true;
        }

        insert newBundle;
        return newBundle.Id;
    }

    @AuraEnabled
    public static void assignCriterionToBundle(Id criterionId, Id bundleId) {
        if (criterionId == null) {
            throw new AuraHandledException('Criterion is required.');
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Criterion_Library__c.fields.getMap();
        if (!fields.containsKey('Section_Library__c') || !fields.get('Section_Library__c').getDescribe().isUpdateable()) {
            throw new AuraHandledException('Bundle assignment is not available in this org configuration.');
        }
        update new Criterion_Library__c(
            Id = criterionId,
            Section_Library__c = bundleId
        );
    }

    @AuraEnabled
    public static void deleteCriterion(Id criterionId) {
        if (criterionId == null) {
            throw new AuraHandledException('Criterion is required.');
        }
        delete new Criterion_Library__c(Id = criterionId);
    }

    private static String asDisplayString(Object value) {
        return value == null || String.isBlank(String.valueOf(value)) ? '--' : String.valueOf(value);
    }

    private static String asString(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static String toDisplay(Object value) {
        return value == null ? '--' : String.valueOf(value);
    }

    private static String resolveTemplateDisplayLabel(SObject templateRow, String preferredLabelField) {
        if (templateRow == null) {
            return '--';
        }
        if (!String.isBlank(preferredLabelField)) {
            String preferred = asDisplayString(templateRow.get(preferredLabelField));
            if (preferred != '--') {
                return preferred;
            }
        }
        String status = asDisplayString(templateRow.get('Status__c'));
        String version = asDisplayString(templateRow.get('Version__c'));
        if (version != '--') {
            String prefix = status == '--' ? 'Evaluation Rubric' : status + ' Rubric';
            return prefix + ' v' + version;
        }
        return asDisplayString(templateRow.get('Name'));
    }

    private static String findPreferredTemplateLabelField(Map<String, Schema.SObjectField> templateFields) {
        List<String> candidateFields = new List<String>{
            'Display_Name__c',
            'Template_Display_Name__c',
            'User_Facing_Name__c',
            'Label__c'
        };
        for (String apiName : candidateFields) {
            if (templateFields.containsKey(apiName)) {
                return apiName;
            }
        }
        return null;
    }

    private static Map<Id, String> loadFundingOpportunityNameByTemplateId() {
        Map<Id, String> out = new Map<Id, String>();
        for (FundingOpportunity fo : [
            SELECT Id, Name, Evaluation_Template__c
            FROM FundingOpportunity
            WHERE Evaluation_Template__c != null
            LIMIT 1000
        ]) {
            if (!out.containsKey(fo.Evaluation_Template__c)) {
                out.put(fo.Evaluation_Template__c, fo.Name);
            }
        }
        return out;
    }

    private static String normalizeDeveloperKey(String value) {
        String base = String.isBlank(value) ? 'bundle' : value.toLowerCase();
        String normalized = base.replaceAll('[^a-z0-9]+', '_');
        while (normalized.startsWith('_')) {
            normalized = normalized.substring(1);
        }
        while (normalized.endsWith('_')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (String.isBlank(normalized)) {
            normalized = 'bundle';
        }
        if (normalized.length() > 80) {
            normalized = normalized.substring(0, 80);
        }
        return normalized;
    }
}
