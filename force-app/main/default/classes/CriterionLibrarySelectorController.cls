public with sharing class CriterionLibrarySelectorController {
    public class CriterionOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String sectionName;
        @AuraEnabled public Decimal defaultWeight;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal displayOrder;
    }

    @AuraEnabled(cacheable=true)
    public static List<CriterionOption> getActiveCriteria() {
        List<CriterionOption> result = new List<CriterionOption>();
        for (Criterion_Library__c row : [
            SELECT Id, Label__c, Description__c, DefaultWeight__c, DisplayOrder__c,
                   Section_Library__r.Label__c
            FROM Criterion_Library__c
            WHERE Active__c = true
            ORDER BY Section_Library__r.DisplayOrder__c ASC NULLS LAST, DisplayOrder__c ASC NULLS LAST, Label__c ASC
        ]) {
            CriterionOption item = new CriterionOption();
            item.id = row.Id;
            item.label = row.Label__c;
            item.description = row.Description__c;
            item.defaultWeight = row.DefaultWeight__c;
            item.displayOrder = row.DisplayOrder__c;
            item.sectionName = row.Section_Library__r == null ? null : row.Section_Library__r.Label__c;
            result.add(item);
        }
        return result;
    }
}