public class RFMCalloutQueueable_v2 implements Queueable {
    Set<String> customerIds;

    public RFMCalloutQueueable_v2(Set<String> customerIds) {
        this.customerIds = customerIds;
    }

    public void execute(QueueableContext context) {
        if (customerIds == null || customerIds.isEmpty()) return;

     
        String linkQuery = 'SELECT SourceRecordId__c, UnifiedRecordId__c ' +
                           'FROM UnifiedLinkssotIndividualRfm__dlm ' +
                           'WHERE SourceRecordId__c IN :customerIds ' +
                           'AND UnifiedRecordId__c != null';
        List<UnifiedLinkssotIndividualRfm__dlm> matchedLinks = Database.query(linkQuery);

        System.debug('Unified Link Records: ' + matchedLinks);

       
        List<RFMCustomer__c> rfmCustomersToInsert = new List<RFMCustomer__c>();
        for (UnifiedLinkssotIndividualRfm__dlm link : matchedLinks) {
            rfmCustomersToInsert.add(new RFMCustomer__c(
                Name = link.SourceRecordId__c,
                Unified_Customer_Id__c = link.UnifiedRecordId__c
            ));
        }

        System.debug('Records to Insert into RFM Customer: ' + rfmCustomersToInsert);
        if (!rfmCustomersToInsert.isEmpty()) {
            insert rfmCustomersToInsert;
        }

       
        String customerQuery = 'SELECT Id, Name, Unified_Customer_Id__c ' +
                               'FROM RFMCustomer__c ' +
                               'WHERE Name IN :customerIds';
        List<RFMCustomer__c> customers = Database.query(customerQuery);

        if (!customers.isEmpty()) {
            List<RFMScoringService_V3.RFMScore> scores = RFMScoringService_V3.calculateRFMForUnifiedIndividuals(customers);
            System.debug('RFM Scores Calculated: ' + scores);
        }
    }
}