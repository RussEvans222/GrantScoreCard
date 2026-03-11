public with sharing class CriterionLibraryManageAction {
    public class Request {
        @InvocableVariable
        public Id sectionId;

        @InvocableVariable
        public String newSectionLabel;

        @InvocableVariable(required=true)
        public String criterionLabel;

        @InvocableVariable
        public Decimal defaultWeight;

        @InvocableVariable
        public String description;

        @InvocableVariable
        public Boolean defaultRequired;

        @InvocableVariable
        public Decimal displayOrder;
    }

    public class Response {
        @InvocableVariable public Id sectionId;
        @InvocableVariable public Id criterionId;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Create Criterion Library Entry')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request req : requests) {
            Response out = new Response();
            try {
                if (req == null || String.isBlank(req.criterionLabel)) {
                    out.message = 'Criterion label is required.';
                    responses.add(out);
                    continue;
                }

                Id resolvedSectionId = req.sectionId;
                if (resolvedSectionId == null && !String.isBlank(req.newSectionLabel)) {
                    Section_Library__c section = new Section_Library__c();
                    section.Label__c = req.newSectionLabel.trim();
                    section.Active__c = true;
                    section.DeveloperKey__c = generateDeveloperKey('SEC', req.newSectionLabel);
                    insert section;
                    resolvedSectionId = section.Id;
                }

                Criterion_Library__c criterion = new Criterion_Library__c();
                criterion.Label__c = req.criterionLabel.trim();
                criterion.Active__c = true;
                criterion.DefaultRequired__c = req.defaultRequired == null ? true : req.defaultRequired;
                criterion.DefaultWeight__c = req.defaultWeight;
                criterion.Description__c = req.description;
                criterion.Section_Library__c = resolvedSectionId;
                criterion.IsStandard__c = false;
                criterion.DisplayOrder__c = req.displayOrder;
                criterion.DeveloperKey__c = generateDeveloperKey('CRIT', req.criterionLabel);
                insert criterion;

                out.sectionId = resolvedSectionId;
                out.criterionId = criterion.Id;
                out.message = 'Added criterion "' + criterion.Label__c + '" to the library.';
            } catch (Exception e) {
                out.message = e.getMessage();
            }
            responses.add(out);
        }
        return responses;
    }

    private static String generateDeveloperKey(String prefix, String seed) {
        String normalized = String.isBlank(seed) ? 'ITEM' : seed.toUpperCase();
        normalized = normalized.replaceAll('[^A-Z0-9]+', '_');
        if (normalized.length() > 40) {
            normalized = normalized.substring(0, 40);
        }
        String suffix = String.valueOf(DateTime.now().getTime());
        String key = prefix + '_' + normalized + '_' + suffix;
        if (key.length() > 80) {
            key = key.substring(0, 80);
        }
        return key;
    }
}