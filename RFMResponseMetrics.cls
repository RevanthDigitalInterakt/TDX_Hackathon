global class RFMResponseMetrics {
    @AuraEnabled
    @InvocableVariable
    global String unifiedCustomerId;
    
    @AuraEnabled
    @InvocableVariable
    global String rfmCategory;
    
    @AuraEnabled
    @InvocableVariable
    global String combinedScore;
}   