global with sharing class RFMMetrics_V2 {

    @InvocableMethod(label='Fetch RFM Metrics by Category V2')
    global static List<List<RFMResponseMetrics>> fetchRFMMetrics(List<Request> req) {
        List<RFMMetrics__c> metricsList = new List<RFMMetrics__c>();
        String query;

        if (!req.isEmpty() && req[0].category != null) {
            query = 'SELECT Unified_Customer_ID__c, RFM_Category__c, RFM_Combined_Score__c FROM RFMMetrics__c WHERE RFM_Category__c = \'' + String.escapeSingleQuotes(req[0].category) + '\' LIMIT 5';
        } else {
            query = 'SELECT Unified_Customer_ID__c, RFM_Category__c, RFM_Combined_Score__c FROM RFMMetrics__c LIMIT 5';
        }

        metricsList = Database.query(query);

        List<List<RFMResponseMetrics>> outputResponse = new List<List<RFMResponseMetrics>>();
        List<RFMResponseMetrics> responses = new List<RFMResponseMetrics>();

        for (RFMMetrics__c metric : metricsList) {
            RFMResponseMetrics response = new RFMResponseMetrics();
            response.unifiedCustomerId = metric.Unified_Customer_ID__c;
            response.rfmCategory = metric.RFM_Category__c;
            response.combinedScore = metric.RFM_Combined_Score__c != null ? String.valueOf(metric.RFM_Combined_Score__c) : null;
            responses.add(response);
        }

        outputResponse.add(responses);
        return outputResponse;
    }

    global class Request {
        @InvocableVariable(required=true)
        global String category;
    }
}