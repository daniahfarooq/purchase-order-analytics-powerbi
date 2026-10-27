let
    Source = Raw_PO_Lines,

    // Keep only analytical columns: excludes 17 fully-empty columns and sparse logistics/comment/freight columns
    #"Kept Relevant Columns" = Table.SelectColumns(Source, {"PurchaseOrderLineId", "PurchaseOrderId", "POLineItemSAPCode", "POLineItemDescription", "POLineItemQuantity", "OrderUnit", "NetPrice", "NetValue", "Currency", "WBSCode", "PlantCode", "PlantCodeDescription", "DeletionIndicator", "MaterialNumber", "MaterialShortText", "POType", "AccountDescription", "PODeliveryDate", "TotalDeliveredQuantity"}),

    // Fix Excel error cell: source text "- DOCUMENTATION CHARGES" was read by Excel as a formula
    #"Fixed Excel Error in Description" = Table.ReplaceErrorValues(#"Kept Relevant Columns", {{"POLineItemDescription", "DOCUMENTATION CHARGES"}}),

    // Set data types (dates without time)
    #"Set Data Types" = Table.TransformColumnTypes(#"Fixed Excel Error in Description", {{"PurchaseOrderLineId", Int64.Type}, {"PurchaseOrderId", Int64.Type}, {"POLineItemSAPCode", Int64.Type}, {"POLineItemDescription", type text}, {"POLineItemQuantity", type number}, {"OrderUnit", type text}, {"NetPrice", type number}, {"NetValue", type number}, {"Currency", type text}, {"WBSCode", type text}, {"PlantCode", Int64.Type}, {"PlantCodeDescription", type text}, {"DeletionIndicator", type text}, {"MaterialNumber", type text}, {"MaterialShortText", type text}, {"POType", type text}, {"AccountDescription", type text}, {"PODeliveryDate", type date}, {"TotalDeliveredQuantity", type number}}, "en-US"),

    // Remove orphan lines that reference a non-existent PO (PurchaseOrderId = 0, 160 lines)
    #"Removed Orphan Lines" = Table.SelectRows(#"Set Data Types", each [PurchaseOrderId] <> null and [PurchaseOrderId] <> 0),

    // Safety check: one row per PO line (primary key)
    #"Removed Duplicate Lines" = Table.Distinct(#"Removed Orphan Lines", {"PurchaseOrderLineId"}),

    // Remove stray spaces from text columns
    #"Trimmed Text Columns" = Table.TransformColumns(#"Removed Duplicate Lines", {{"POLineItemDescription", Text.Trim, type text}, {"OrderUnit", Text.Trim, type text}, {"Currency", each if _ = null then null else Text.Upper(Text.Trim(_)), type text}, {"WBSCode", Text.Trim, type text}, {"PlantCodeDescription", Text.Trim, type text}, {"DeletionIndicator", Text.Trim, type text}, {"MaterialShortText", Text.Trim, type text}}),

    // Readable deletion status: "L" = line marked for deletion in SAP
    #"Added Line Status" = Table.AddColumn(#"Trimmed Text Columns", "LineStatus", each if [DeletionIndicator] = "L" then "Deleted" else "Active", type text),

    // Lines without a PO Type are service lines (they carry a service line code instead)
    #"Filled PO Type" = Table.ReplaceValue(#"Added Line Status", null, "Service", Replacer.ReplaceValue, {"POType"}),
    #"Filled Account Assignment" = Table.ReplaceValue(#"Filled PO Type", null, "Not Assigned", Replacer.ReplaceValue, {"AccountDescription"}),

    // Derive Project Code from WBS because ProjectId is 100% empty
    // Rule: "A03106I030.04.0400" -> "A03106" (first 6 chars); "ET760063266.0001" -> "ET760063266" (text before first dot)
    #"Added Project Code" = Table.AddColumn(#"Filled Account Assignment", "ProjectCode", each (
        let w = [WBSCode]
        in if w = null or w = "" then "No Project"
           else if Text.Length(w) > 1 and List.Contains({"A".."Z"}, Text.Upper(Text.Middle(w, 1, 1))) then List.First(Text.Split(w, "."))
           else Text.Start(w, 6)), type text),

    // Remove impossible delivery dates (one line dated in the year 2202)
    #"Cleaned Delivery Date" = Table.TransformColumns(#"Added Project Code", {{"PODeliveryDate", each if _ <> null and Date.Year(_) > 2030 then null else _, type date}}),

    // Delivery status from ordered vs delivered quantity
    #"Added Delivery Status" = Table.AddColumn(#"Cleaned Delivery Date", "DeliveryStatus", each (
        let q = [POLineItemQuantity], d = if [TotalDeliveredQuantity] = null then 0 else [TotalDeliveredQuantity]
        in if q = null or q <= 0 then "Not Applicable" else if d >= q then "Fully Delivered" else if d > 0 then "Partially Delivered" else "Not Delivered"), type text),

    // Bring PO-level fields from Dim_PO (inner join guarantees every line belongs to a valid PO)
    #"Merged PO Header" = Table.NestedJoin(#"Added Delivery Status", {"PurchaseOrderId"}, Dim_PO, {"PurchaseOrderId"}, "PO", JoinKind.Inner),
    #"Expanded PO Header" = Table.ExpandTableColumn(#"Merged PO Header", "PO", {"VendorId", "POCreationDate", "POAmountLocal", "POAmountUSD"}, {"VendorId", "POCreationDate", "POAmountLocal", "POAmountUSD"}),

    // Value used for allocation weights (blank Net Value treated as 0)
    #"Added Allocation Value" = Table.AddColumn(#"Expanded PO Header", "AllocValue", each if [NetValue] = null then 0 else [NetValue], type number),

    // Per-PO totals needed for the allocation weights
    #"Grouped PO Totals" = Table.Group(#"Added Allocation Value", {"PurchaseOrderId"}, {
        {"ActiveValue", each List.Sum(Table.SelectRows(_, each [LineStatus] = "Active")[AllocValue]), type number},
        {"ActiveCount", each Table.RowCount(Table.SelectRows(_, each [LineStatus] = "Active")), Int64.Type},
        {"TotalValue", each List.Sum([AllocValue]), type number},
        {"TotalCount", each Table.RowCount(_), Int64.Type}}),
    #"Merged PO Totals" = Table.NestedJoin(#"Added Allocation Value", {"PurchaseOrderId"}, #"Grouped PO Totals", {"PurchaseOrderId"}, "Totals", JoinKind.LeftOuter),
    #"Expanded PO Totals" = Table.ExpandTableColumn(#"Merged PO Totals", "Totals", {"ActiveValue", "ActiveCount", "TotalValue", "TotalCount"}),

    // Allocation weight: active lines share the PO amount by Net Value; fully-deleted (cancelled) POs keep their amount on the deleted lines
    #"Added Allocation Weight" = Table.AddColumn(#"Expanded PO Totals", "AllocationWeight", each (
        let av = if [ActiveValue] = null then 0 else [ActiveValue],
            tv = if [TotalValue] = null then 0 else [TotalValue]
        in if [LineStatus] = "Active" then (if av > 0 then [AllocValue] / av else 1 / [ActiveCount])
           else if [ActiveCount] > 0 then 0
           else (if tv > 0 then [AllocValue] / tv else 1 / [TotalCount])), type number),

    // Allocated PO amounts: lines of each PO add up exactly to the original PO amount
    #"Added Allocated Amount Local" = Table.AddColumn(#"Added Allocation Weight", "AllocatedPOAmountLocal", each [POAmountLocal] * [AllocationWeight], type number),
    #"Added Allocated Amount USD" = Table.AddColumn(#"Added Allocated Amount Local", "AllocatedPOAmountUSD", each [POAmountUSD] * [AllocationWeight], type number),

    // Remove helper columns used only for the calculation
    #"Removed Helper Columns" = Table.RemoveColumns(#"Added Allocated Amount USD", {"AllocValue", "ActiveValue", "ActiveCount", "TotalValue", "TotalCount", "POAmountLocal", "POAmountUSD"}),

    // Business-friendly column names
    #"Renamed Columns" = Table.RenameColumns(#"Removed Helper Columns", {{"POLineItemSAPCode", "LineItemNo"}, {"POLineItemDescription", "LineDescription"}, {"POLineItemQuantity", "Quantity"}, {"Currency", "LineCurrency"}, {"PlantCodeDescription", "PlantName"}, {"AccountDescription", "AccountAssignment"}, {"TotalDeliveredQuantity", "DeliveredQuantity"}})
in
    #"Renamed Columns"
