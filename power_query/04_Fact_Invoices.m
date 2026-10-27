let
    Source = Raw_Invoices,

    // Keep only the columns needed for invoice tracking
    #"Kept Relevant Columns" = Table.SelectColumns(Source, {"InvoiceId", "InvoiceNo", "InvoiceTypeId", "InvoiceDate", "POSAPId", "CurrencyType", "InvoiceAmount", "DueDate", "InvoiceStatusId", "IsCompleted", "TypeFor", "CreatedOn"}),

    // Set data types (dates stored without time)
    #"Set Data Types" = Table.TransformColumnTypes(#"Kept Relevant Columns", {{"InvoiceId", Int64.Type}, {"InvoiceNo", type text}, {"InvoiceTypeId", Int64.Type}, {"InvoiceDate", type date}, {"POSAPId", Int64.Type}, {"CurrencyType", type text}, {"InvoiceAmount", type number}, {"DueDate", type date}, {"InvoiceStatusId", Int64.Type}, {"IsCompleted", Int64.Type}, {"TypeFor", type text}, {"CreatedOn", type date}}, "en-US"),

    // Safety check: one row per invoice (primary key). InvoiceNo is NOT unique - vendors reuse numbers across POs
    #"Removed Duplicate Invoices" = Table.Distinct(#"Set Data Types", {"InvoiceId"}),

    // Flag invoice dates that are missing or impossible (e.g. year 2080)
    #"Added Date Quality Flag" = Table.AddColumn(#"Removed Duplicate Invoices", "InvoiceDateQuality", each if [InvoiceDate] = null then "Missing - record date used" else if Date.Year([InvoiceDate]) > Date.Year([CreatedOn]) + 1 then "Invalid - record date used" else "Original", type text),

    // Replace missing/invalid invoice dates with the date the invoice record was created
    #"Added Corrected Invoice Date" = Table.AddColumn(#"Added Date Quality Flag", "InvoiceDateCorrected", each if [InvoiceDateQuality] = "Original" then [InvoiceDate] else [CreatedOn], type date),
    #"Removed Original Invoice Date" = Table.RemoveColumns(#"Added Corrected Invoice Date", {"InvoiceDate"}),
    #"Renamed Corrected Invoice Date" = Table.RenameColumns(#"Removed Original Invoice Date", {{"InvoiceDateCorrected", "InvoiceDate"}}),

    // Fix malformed PO reference: SAP PO numbers have 10 digits (one record had 14: 47000530939999 -> 4700053093)
    #"Fixed PO Reference" = Table.TransformColumns(#"Renamed Corrected Invoice Date", {{"POSAPId", each if _ <> null and Text.Length(Text.From(_)) > 10 then Number.From(Text.Start(Text.From(_), 10)) else _, Int64.Type}}),

    // Bring in PurchaseOrderId and PO currency from Dim_PO (join on POSAPId)
    #"Merged PO Info" = Table.NestedJoin(#"Fixed PO Reference", {"POSAPId"}, Dim_PO, {"POSAPId"}, "PO", JoinKind.LeftOuter),
    #"Expanded PO Info" = Table.ExpandTableColumn(#"Merged PO Info", "PO", {"PurchaseOrderId", "POCurrency"}, {"PurchaseOrderId", "POCurrency"}),

    // Invoice currency: use the invoice's own currency; if missing, fall back to the PO currency
    #"Added Invoice Currency" = Table.AddColumn(#"Expanded PO Info", "InvoiceCurrency", each if [CurrencyType] = null or Text.Trim([CurrencyType]) = "" then [POCurrency] else Text.Upper(Text.Trim([CurrencyType])), type text),

    // Invoice year, used for the exchange-rate lookup
    #"Added Invoice Year" = Table.AddColumn(#"Added Invoice Currency", "InvoiceYear", each Date.Year([InvoiceDate]), Int64.Type),

    // Look up the USD exchange rate by Currency + Year
    #"Merged FX Rates" = Table.NestedJoin(#"Added Invoice Year", {"InvoiceCurrency", "InvoiceYear"}, Dim_FX_Rates, {"Currency", "Year"}, "FX", JoinKind.LeftOuter),
    #"Expanded FX Rate" = Table.ExpandTableColumn(#"Merged FX Rates", "FX", {"USD_per_Unit"}, {"FXRateToUSD"}),

    // Invoice amount in USD
    #"Added Invoice Amount USD" = Table.AddColumn(#"Expanded FX Rate", "InvoiceAmountUSD", each [InvoiceAmount] * [FXRateToUSD], type number),

    // Readable processing status instead of 0/1
    #"Added Process Status" = Table.AddColumn(#"Added Invoice Amount USD", "InvoiceProcessStatus", each if [IsCompleted] = 1 then "Completed" else "In Process", type text),

    // Fill blank invoice purpose
    #"Filled Blank Invoice Purpose" = Table.ReplaceValue(#"Added Process Status", null, "Not Specified", Replacer.ReplaceValue, {"TypeFor"}),

    // Remove helper columns that are no longer needed
    #"Removed Helper Columns" = Table.RemoveColumns(#"Filled Blank Invoice Purpose", {"CurrencyType", "POCurrency", "IsCompleted", "CreatedOn", "InvoiceYear"}),

    // Business-friendly column names
    #"Renamed Columns" = Table.RenameColumns(#"Removed Helper Columns", {{"TypeFor", "InvoicePurpose"}, {"InvoiceAmount", "InvoiceAmountLocal"}})
in
    #"Renamed Columns"
