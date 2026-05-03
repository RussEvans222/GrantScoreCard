// Test DataRaptor execution directly
Map<String, Object> input = new Map<String, Object>();
input.put('keyword', 'housing');

Map<String, Object> output = new Map<String, Object>();
Map<String, Object> options = new Map<String, Object>();

// Try to invoke the DataRaptor
try {
    vlocity_ins.DRDataPackRunnable drRunnable = new vlocity_ins.DRDataPackRunnable();
    output = (Map<String, Object>) drRunnable.invokeMethod(
        'DRExtractFundingOpportunities',
        input,
        output,
        options
    );
    System.debug('SUCCESS: ' + JSON.serializePretty(output));
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}

// Also test direct SOQL
List<FundingOpportunity> opps = [SELECT Id, Name, Description FROM FundingOpportunity LIMIT 5];
System.debug('Direct query found: ' + opps.size() + ' records');
