global class FundingOpportunityDataProvider {

    @InvocableMethod(label='Get Opportunities For Grounding' description='Returns FundingOpportunity records for AI grounding')
    global static List<String> getOpportunitiesForGrounding(List<Request> requests) {
        Request req = requests[0];
        Integer recordLimit = req.recordLimit != null ? req.recordLimit : 50;

        List<FundingOpportunity> opportunities = [
            SELECT Id, Name, Description, MaximumFundingAmount, StartDate, EndDate
            FROM FundingOpportunity
            ORDER BY CreatedDate DESC
            LIMIT :recordLimit
        ];

        // Format as readable text for AI
        List<String> formattedOpps = new List<String>();
        String result = '';

        for(FundingOpportunity opp : opportunities) {
            result += 'Opportunity ID: ' + opp.Id + '\n';
            result += 'Name: ' + opp.Name + '\n';

            if(String.isNotBlank(opp.Description)) {
                result += 'Description: ' + opp.Description + '\n';
            }

            if(opp.MaximumFundingAmount != null) {
                result += 'Max Award: $' + opp.MaximumFundingAmount.format() + '\n';
            }

            if(opp.StartDate != null) {
                result += 'Start Date: ' + opp.StartDate.format() + '\n';
            }

            if(opp.EndDate != null) {
                result += 'End Date: ' + opp.EndDate.format() + '\n';
            }

            result += '\n---\n\n';
        }

        formattedOpps.add(result);
        return formattedOpps;
    }

    global class Request {
        @InvocableVariable(label='Record Limit' description='Maximum number of opportunities to return')
        public Integer recordLimit;
    }
}
