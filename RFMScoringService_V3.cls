public with sharing class RFMScoringService_V3 {
    public class RFMScore {
        public String unifiedCustomerId;
        public Decimal recencyScore;
        public Integer frequencyScore;
        public Decimal monetaryScore;
        public Decimal totalScore;
        public String rfmKey;
        public String rfmCategory;
    }

    public static List<RFMScore> calculateRFMForUnifiedIndividuals(List<RFMCustomer__c> individuals) {
        System.debug('Starting RFM score calculation for Unified Individuals');

        Map<String, List<String>> unifiedIdToNames = new Map<String, List<String>>();
        Map<String, String> nameToUnifiedId = new Map<String, String>();

        for (RFMCustomer__c ind : individuals) {
            if (String.isNotBlank(ind.Name) && String.isNotBlank(ind.Unified_Customer_Id__c)) {
                if (!unifiedIdToNames.containsKey(ind.Unified_Customer_Id__c)) {
                    unifiedIdToNames.put(ind.Unified_Customer_Id__c, new List<String>());
                }
                unifiedIdToNames.get(ind.Unified_Customer_Id__c).add(ind.Name);
                nameToUnifiedId.put(ind.Name, ind.Unified_Customer_Id__c);
            }
        }

        List<String> customerIds = new List<String>(nameToUnifiedId.keySet());

        // Query Sales_Order__c
        String salesOrderQuery = 'SELECT Customer_Id__c, Order_Date__c, Total_Amount__c ' +
                                 'FROM Sales_Order__c WHERE Customer_Id__c IN :customerIds';
        List<SObject> genericOrders = Database.query(salesOrderQuery);

        Map<String, List<SObject>> ordersByUnifiedCustomer = new Map<String, List<SObject>>();
        for (SObject so : genericOrders) {
            String customerId = (String)so.get('Customer_Id__c');
            String unifiedId = nameToUnifiedId.get(customerId);
            if (unifiedId != null) {
                if (!ordersByUnifiedCustomer.containsKey(unifiedId)) {
                    ordersByUnifiedCustomer.put(unifiedId, new List<SObject>());
                }
                ordersByUnifiedCustomer.get(unifiedId).add(so);
            }
        }

        Date today = Date.today();
        List<RFMScore> rfmResults = new List<RFMScore>();
        Map<String, Decimal> customerTotalSpending = new Map<String, Decimal>();
        Map<String, Integer> customerFrequency = new Map<String, Integer>();
        Map<String, Integer> customerRecency = new Map<String, Integer>();

        for (String unifiedId : ordersByUnifiedCustomer.keySet()) {
            List<SObject> custOrders = ordersByUnifiedCustomer.get(unifiedId);
            Decimal totalAmount = 0;
            Integer frequency = custOrders.size();
            Integer minDays = 99999;

            for (SObject so : custOrders) {
                Decimal amount = (Decimal)so.get('Total_Amount__c');
                Datetime orderDateTime = (Datetime)so.get('Order_Date__c');
                Date orderDate = orderDateTime.date();
                totalAmount += amount;
                Integer daysSince = today.daysBetween(orderDate);
                if (daysSince < minDays) minDays = daysSince;
            }

            customerTotalSpending.put(unifiedId, totalAmount);
            customerFrequency.put(unifiedId, frequency);
            customerRecency.put(unifiedId, minDays);
        }

        List<Integer> allRecency = new List<Integer>(customerRecency.values());
        allRecency.sort();

        List<Integer> allFrequency = new List<Integer>(customerFrequency.values());
        allFrequency.sort();

        Decimal percentile33Recency = calculatePercentile(allRecency, 33);
        Decimal percentile66Recency = calculatePercentile(allRecency, 66);
        Decimal percentile33Frequency = calculatePercentile(allFrequency, 33);
        Decimal percentile66Frequency = calculatePercentile(allFrequency, 66);

        for (String unifiedId : ordersByUnifiedCustomer.keySet()) {
            Decimal totalAmount = customerTotalSpending.get(unifiedId);
            Integer frequency = customerFrequency.get(unifiedId);
            Integer minDays = customerRecency.get(unifiedId);

            RFMScore score = new RFMScore();
            score.unifiedCustomerId = unifiedId;
            score.recencyScore = calcRecency(minDays, percentile33Recency, percentile66Recency);
            score.frequencyScore = calcFrequency(frequency, percentile33Frequency, percentile66Frequency);
            score.monetaryScore = calcMonetary(totalAmount, percentile33Recency, percentile66Recency);
            score.totalScore = score.recencyScore * 100 + score.frequencyScore * 10 + score.monetaryScore;

            Map<String, String> categoryInfo = getRFMCategory(score.recencyScore, score.frequencyScore, score.monetaryScore);
            score.rfmKey = categoryInfo.get('key');
            score.rfmCategory = categoryInfo.get('category');

            rfmResults.add(score);
        }

        // DELETE existing metrics for those Unified Customers
    //   List<String> unifiedCustomerIds = new List<String>(ordersByUnifiedCustomer.keySet());
 		 List<RFMMetrics__c> existingMetrics = [SELECT Id FROM RFMMetrics__c];
        if (!existingMetrics.isEmpty()) {
            Database.delete(existingMetrics, false); 
        }

        // INSERT updated metrics
        List<RFMMetrics__c> recordsToInsert = new List<RFMMetrics__c>();
        for (RFMScore score : rfmResults) {
            recordsToInsert.add(new RFMMetrics__c(
                Unified_Customer_ID__c = score.unifiedCustomerId,
                Recency_Score__c = score.recencyScore,
                Frequency_Score__c = score.frequencyScore,
                Monetary_Score__c = score.monetaryScore,
                RFM_Combined_Score__c = score.totalScore,
                RFM_Key__c = score.rfmKey,
                RFM_Category__c = score.rfmCategory
            ));
        }
        insert recordsToInsert;

        return rfmResults;
    }

    private static Decimal calcRecency(Integer days, Decimal p33, Decimal p66) {
        if (days <= p33) return 3;
        else if (days <= p66) return 2;
        else return 1;
    }

    private static Integer calcFrequency(Integer count, Decimal p33, Decimal p66) {
        if (count >= p66) return 3;
        else if (count >= p33) return 2;
        else return 1;
    }

    private static Decimal calcMonetary(Decimal total, Decimal p33, Decimal p66) {
        if (total >= p66) return 3;
        else if (total >= p33) return 2;
        else return 1;
    }

    private static Decimal calculatePercentile(List<Integer> sortedList, Integer percentile) {
        if (sortedList.isEmpty()) return 0;
        Integer index = (sortedList.size() * percentile) / 100;
        if (index >= sortedList.size()) index = sortedList.size() - 1;
        return sortedList[index];
    }

    private static Map<String, String> getRFMCategory(Decimal r, Integer f, Decimal m) {
        String rGrade = r == 3 ? 'H' : (r == 2 ? 'M' : 'L');
        String fGrade = f == 3 ? 'H' : (f == 2 ? 'M' : 'L');
        String mGrade = m == 3 ? 'H' : (m == 2 ? 'M' : 'L');

        String key = rGrade + fGrade + mGrade;

        Map<String, String> categories = new Map<String, String> {
            'HHH' => 'Champions',
            'HHM' => 'Potential Champions',
            'HHL' => 'Potential Loyalists',
            'HMH' => 'Recent Big Spenders',
            'HMM' => 'Loyal Customers',
            'HML' => 'Recent Buyers',
            'HLH' => 'High Value New Customers',
            'HLM' => 'Promising',
            'HLL' => 'New Customers',
            'MHH' => 'Loyal Big Spenders',
            'MHM' => 'Consistent Spenders',
            'MHL' => 'Valuable Infrequents',
            'MMH' => 'Steady Spenders',
            'MMM' => 'Average Customers',
            'MML' => 'Occasional Buyers',
            'MLH' => 'Infrequent Big Spenders',
            'MLM' => 'Infrequent Spenders',
            'MLL' => 'Rare Buyers',
            'LHH' => 'Dormant Big Spenders',
            'LHM' => 'Lost Big Spenders',
            'LHL' => 'High Value Lapses',
            'LMH' => 'Lost Loyalists',
            'LMM' => 'Former Regulars',
            'LML' => 'Former Buyers',
            'LLH' => 'Lost High Spenders',
            'LLM' => 'Lost Medium Spenders',
            'LLL' => 'Inactive'
        };

        return new Map<String, String> {
            'key' => key,
            'category' => categories.containsKey(key) ? categories.get(key) : 'Unknown'
        };
    }
}