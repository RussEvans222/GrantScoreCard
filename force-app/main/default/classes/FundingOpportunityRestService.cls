@RestResource(urlMapping='/funding-opportunities/*')
global class FundingOpportunityRestService {
    @HttpGet
    global static List<Map<String, Object>> getFundingOpportunities() {
        List<FundingOpportunity> opps = [
            SELECT Id, Name, Description
            FROM FundingOpportunity
            LIMIT 50
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for(FundingOpportunity opp : opps) {
            Map<String, Object> oppMap = new Map<String, Object>();
            oppMap.put('Id', opp.Id);
            oppMap.put('name', opp.Name);
            oppMap.put('Description', opp.Description);
            result.add(oppMap);
        }

        return result;
    }
}
