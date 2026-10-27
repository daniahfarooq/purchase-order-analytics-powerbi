// Test query (group "9 - Tests", load disabled).
// Proves that the line-level allocation of PO amounts reconciles exactly to the PO header totals.
let
    HeaderTotalUSD = List.Sum(Dim_PO[POAmountUSD]),
    LineTotalUSD = List.Sum(Fact_PO_Lines[AllocatedPOAmountUSD]),
    Result = #table({"Check", "Value"}, {
        {"PO Header total (USD)", HeaderTotalUSD},
        {"Allocated line total (USD)", LineTotalUSD},
        {"Difference (should be ~0)", HeaderTotalUSD - LineTotalUSD},
        {"POs in header", Table.RowCount(Dim_PO)},
        {"POs found in lines", List.Count(List.Distinct(Fact_PO_Lines[PurchaseOrderId]))}})
in
    Result
