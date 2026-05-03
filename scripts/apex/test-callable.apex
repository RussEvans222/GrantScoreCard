// Test the Callable
Callable c = (Callable) Type.forName('GetFundingOpportunitiesCallable').newInstance();
Map<String, Object> args = new Map<String, Object>();
Object result = c.call('getFundingOpportunities', args);

System.debug('RESULT: ' + JSON.serializePretty(result));
