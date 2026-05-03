// Test DataRaptor directly
Map<String, Object> input = new Map<String, Object>();
Map<String, Object> output = new Map<String, Object>();
Map<String, Object> options = new Map<String, Object>();
options.put('isDebug', true);

try {
    // Query to verify namespace
    String namespace = [SELECT NamespacePrefix FROM Organization LIMIT 1].NamespacePrefix;
    System.debug('Namespace: ' + namespace);

    // Test direct SOQL first
    List<FundingOpportunity> testQuery = [SELECT Id, Name, Description FROM FundingOpportunity LIMIT 3];
    System.debug('Direct SOQL returned: ' + testQuery.size() + ' records');
    for(FundingOpportunity opp : testQuery) {
        System.debug('Record: ' + opp.Id + ' - ' + opp.Name);
    }

    // Now test the DataRaptor
    System.debug('Testing DataRaptor: DRFundingList');
    Type drType = Type.forName('omnistudio', 'DRDataPackRunnable');
    if (drType != null) {
        Object drInstance = drType.newInstance();

        output = (Map<String, Object>) drType.getMethod('invokeMethod', new List<Type>{
            Type.forName('String'),
            Type.forName('Map<String,Object>'),
            Type.forName('Map<String,Object>'),
            Type.forName('Map<String,Object>')
        }).invoke(drInstance, new List<Object>{
            'DRFundingList',
            input,
            output,
            options
        });

        System.debug('DataRaptor Output: ' + JSON.serializePretty(output));
    } else {
        System.debug('ERROR: Could not find omnistudio.DRDataPackRunnable class');
    }

} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}
