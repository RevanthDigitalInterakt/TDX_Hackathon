public class RFM_UnifiedLinkFetch {

    public class InputWrapper {
        @InvocableVariable(required=true label='Number of Days')
        public Integer numberOfDays;
    }

    public class OutputWrapper {
        @InvocableVariable(label='Status Message')
        public String statusMessage;
    }

    @InvocableMethod(label='UniFetchLink APEX')
    public static List<OutputWrapper> run(List<InputWrapper> inputs) {
        List<OutputWrapper> outputs = new List<OutputWrapper>();

        for (InputWrapper input : inputs) {
            if (input.numberOfDays != null && input.numberOfDays > 0) {
                System.debug('priniting no of days');
                System.debug(input.numberOfDays);
                refreshSalesOrders(input.numberOfDays);

                OutputWrapper output = new OutputWrapper();
                output.statusMessage = 'RFM preparation started for last ' + input.numberOfDays + ' days.';
                outputs.add(output);
            } else {
                throw new AuraHandledException('Please provide a valid number of days greater than 0.');
            }
        }
        return outputs;
    }

    public static void refreshSalesOrders(Integer NO_OF_DAYS) {
        Date startDate = Date.today().addDays(-NO_OF_DAYS);

        // Dynamic SOQL for fetching source orders
        String salesOrderQuery = 'SELECT ssot__Id__c, ssot__SoldToCustomerId__c, ssot__PurchaseOrderDate__c, ' +
                                 'STORE_CITY__c, ssot__GrandTotalAmount__c ' +
                                 'FROM ssot__SalesOrder__dlm ' +
                                 'WHERE ssot__PurchaseOrderDate__c >= :startDate';

        List<ssot__SalesOrder__dlm> orders = Database.query(salesOrderQuery);

        // Dynamic SOQL for deleting existing records
        String deleteQuery = 'SELECT Id FROM Sales_Order__c';
        List<Sales_Order__c> toDelete = Database.query(deleteQuery);
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }

        List<Sales_Order__c> newOrders = new List<Sales_Order__c>();
        Set<String> customerIds = new Set<String>();

        for (ssot__SalesOrder__dlm order : orders) {
            if (String.isNotBlank(order.ssot__SoldToCustomerId__c)) {
                newOrders.add(new Sales_Order__c(
                    Name = 'SO-' + order.ssot__Id__c,
                    Customer_Id__c = order.ssot__SoldToCustomerId__c,
                    Order_Date__c = order.ssot__PurchaseOrderDate__c,
                    STORE_N__c = order.STORE_CITY__c,
                    Total_Amount__c = order.ssot__GrandTotalAmount__c
                ));
                customerIds.add(order.ssot__SoldToCustomerId__c);
            }
        }

        if (!newOrders.isEmpty()) {
            insert newOrders;
        }

        System.enqueueJob(new RFMDeleteQueueable());
        System.enqueueJob(new RFMCalloutQueueable_v2(customerIds));
    }
}