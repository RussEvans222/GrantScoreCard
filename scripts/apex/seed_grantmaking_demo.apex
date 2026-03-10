/*
 * Idempotent seed script for Grantmaking demo setup.
 * Run with: sf apex run --file scripts/apex/seed_grantmaking_demo.apex -o <orgAlias>
 */

Map<String, Map<String, Object>> sectionSeed = new Map<String, Map<String, Object>>{
    'COMMUNITY_IMPACT' => new Map<String, Object>{
        'label' => 'Community Impact',
        'order' => 10
    },
    'FEASIBILITY' => new Map<String, Object>{
        'label' => 'Project Feasibility',
        'order' => 20
    },
    'FINANCIAL_VIABILITY' => new Map<String, Object>{
        'label' => 'Financial Viability',
        'order' => 30
    },
    'ORGANIZATIONAL_CAPACITY' => new Map<String, Object>{
        'label' => 'Organizational Capacity',
        'order' => 40
    }
};

Map<String, Section_Library__c> existingSectionsByKey = new Map<String, Section_Library__c>();
for (Section_Library__c row : [
    SELECT Id, DeveloperKey__c, Label__c, DisplayOrder__c, Active__c
    FROM Section_Library__c
    WHERE DeveloperKey__c IN :sectionSeed.keySet()
]) {
    existingSectionsByKey.put(row.DeveloperKey__c, row);
}

List<Section_Library__c> sectionsToInsert = new List<Section_Library__c>();
List<Section_Library__c> sectionsToUpdate = new List<Section_Library__c>();
for (String key : sectionSeed.keySet()) {
    Map<String, Object> seed = sectionSeed.get(key);
    String label = (String) seed.get('label');
    Decimal sortOrder = Decimal.valueOf(String.valueOf(seed.get('order')));

    if (existingSectionsByKey.containsKey(key)) {
        Section_Library__c upd = existingSectionsByKey.get(key);
        upd.Label__c = label;
        upd.DisplayOrder__c = sortOrder;
        upd.Active__c = true;
        sectionsToUpdate.add(upd);
    } else {
        sectionsToInsert.add(new Section_Library__c(
            DeveloperKey__c = key,
            Label__c = label,
            DisplayOrder__c = sortOrder,
            Active__c = true
        ));
    }
}

if (!sectionsToInsert.isEmpty()) {
    insert sectionsToInsert;
}
if (!sectionsToUpdate.isEmpty()) {
    update sectionsToUpdate;
}

Map<String, Id> sectionIdByKey = new Map<String, Id>();
for (Section_Library__c row : [
    SELECT Id, DeveloperKey__c
    FROM Section_Library__c
    WHERE DeveloperKey__c IN :sectionSeed.keySet()
]) {
    sectionIdByKey.put(row.DeveloperKey__c, row.Id);
}

List<Map<String, Object>> criterionSeed = new List<Map<String, Object>>{
    new Map<String, Object>{
        'key' => 'COMMUNITY_NEED',
        'label' => 'Community Need Alignment',
        'description' => 'How well the proposed project addresses a documented community need.',
        'weight' => 30,
        'required' => true,
        'displayOrder' => 10,
        'sectionKey' => 'COMMUNITY_IMPACT'
    },
    new Map<String, Object>{
        'key' => 'BENEFICIARY_REACH',
        'label' => 'Beneficiary Reach',
        'description' => 'Expected number and diversity of beneficiaries impacted by the project.',
        'weight' => 20,
        'required' => true,
        'displayOrder' => 20,
        'sectionKey' => 'COMMUNITY_IMPACT'
    },
    new Map<String, Object>{
        'key' => 'IMPLEMENTATION_PLAN',
        'label' => 'Implementation Plan Quality',
        'description' => 'Clarity and realism of milestones, staffing, and execution timeline.',
        'weight' => 20,
        'required' => true,
        'displayOrder' => 10,
        'sectionKey' => 'FEASIBILITY'
    },
    new Map<String, Object>{
        'key' => 'BUDGET_REASONABLENESS',
        'label' => 'Budget Reasonableness',
        'description' => 'Appropriateness of budget relative to activities and deliverables.',
        'weight' => 15,
        'required' => true,
        'displayOrder' => 10,
        'sectionKey' => 'FINANCIAL_VIABILITY'
    },
    new Map<String, Object>{
        'key' => 'ORG_TRACK_RECORD',
        'label' => 'Organization Track Record',
        'description' => 'Evidence of relevant delivery experience and governance capacity.',
        'weight' => 15,
        'required' => true,
        'displayOrder' => 10,
        'sectionKey' => 'ORGANIZATIONAL_CAPACITY'
    }
};

Set<String> criterionKeys = new Set<String>();
for (Map<String, Object> seed : criterionSeed) {
    criterionKeys.add((String) seed.get('key'));
}

Map<String, Criterion_Library__c> existingCriteriaByKey = new Map<String, Criterion_Library__c>();
for (Criterion_Library__c row : [
    SELECT Id, DeveloperKey__c, Label__c, Description__c, DefaultWeight__c,
           DefaultRequired__c, DisplayOrder__c, Section_Library__c, Active__c, IsStandard__c
    FROM Criterion_Library__c
    WHERE DeveloperKey__c IN :criterionKeys
]) {
    existingCriteriaByKey.put(row.DeveloperKey__c, row);
}

List<Criterion_Library__c> criteriaToInsert = new List<Criterion_Library__c>();
List<Criterion_Library__c> criteriaToUpdate = new List<Criterion_Library__c>();
for (Map<String, Object> seed : criterionSeed) {
    String key = (String) seed.get('key');
    Id sectionId = sectionIdByKey.get((String) seed.get('sectionKey'));

    if (existingCriteriaByKey.containsKey(key)) {
        Criterion_Library__c upd = existingCriteriaByKey.get(key);
        upd.Label__c = (String) seed.get('label');
        upd.Description__c = (String) seed.get('description');
        upd.DefaultWeight__c = Decimal.valueOf(String.valueOf(seed.get('weight')));
        upd.DefaultRequired__c = (Boolean) seed.get('required');
        upd.DisplayOrder__c = Decimal.valueOf(String.valueOf(seed.get('displayOrder')));
        upd.Section_Library__c = sectionId;
        upd.Active__c = true;
        upd.IsStandard__c = true;
        criteriaToUpdate.add(upd);
    } else {
        criteriaToInsert.add(new Criterion_Library__c(
            DeveloperKey__c = key,
            Label__c = (String) seed.get('label'),
            Description__c = (String) seed.get('description'),
            DefaultWeight__c = Decimal.valueOf(String.valueOf(seed.get('weight'))),
            DefaultRequired__c = (Boolean) seed.get('required'),
            DisplayOrder__c = Decimal.valueOf(String.valueOf(seed.get('displayOrder'))),
            Section_Library__c = sectionId,
            Active__c = true,
            IsStandard__c = true
        ));
    }
}

if (!criteriaToInsert.isEmpty()) {
    insert criteriaToInsert;
}
if (!criteriaToUpdate.isEmpty()) {
    update criteriaToUpdate;
}

System.debug(LoggingLevel.INFO, 'Grantmaking demo seed complete. Sections upserted=' + sectionSeed.size() + ', criteria upserted=' + criterionSeed.size());
