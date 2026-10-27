let
    Source = Raw_PO_Header,

    // Keep only business-relevant columns: drops 6 fully-empty columns, 18 phantom columns (Column27-Column44) and low-value columns
    #"Kept Relevant Columns" = Table.SelectColumns(Source, {"PurchaseOrderId", "POSAPId", "VendorId", "VendorSAPId", "POCreationDate", "POAmount", "Currency", "PurchaseGroup", "PurchaseGroupDescription", "ProcurementType", "PaymentTermId", "poStatus", "incoTerms", "Ammended", "POVersion"}),

    // Convert text dates like "Monday, November 15, 2021" into real Date values (no time part)
    #"Converted PO Creation Date" = Table.TransformColumns(#"Kept Relevant Columns", {{"POCreationDate", each if _ is date then _ else if _ is datetime then Date.From(_) else try Date.FromText(Text.Trim(Text.From(_)), [Format = "dddd, MMMM d, yyyy", Culture = "en-US"]) otherwise null, type date}}),

    // Set correct data types for every column
    #"Set Data Types" = Table.TransformColumnTypes(#"Converted PO Creation Date", {{"PurchaseOrderId", Int64.Type}, {"POSAPId", Int64.Type}, {"VendorId", Int64.Type}, {"VendorSAPId", Int64.Type}, {"POAmount", type number}, {"Currency", type text}, {"PurchaseGroup", type text}, {"PurchaseGroupDescription", type text}, {"ProcurementType", type text}, {"PaymentTermId", Int64.Type}, {"poStatus", Int64.Type}, {"incoTerms", type text}, {"Ammended", Int64.Type}, {"POVersion", Int64.Type}}, "en-US"),

    // Remove stray spaces from text columns and standardise currency codes
    #"Trimmed Text Columns" = Table.TransformColumns(#"Set Data Types", {{"Currency", each Text.Upper(Text.Trim(_)), type text}, {"PurchaseGroup", Text.Trim, type text}, {"PurchaseGroupDescription", Text.Trim, type text}, {"ProcurementType", Text.Trim, type text}, {"incoTerms", Text.Trim, type text}}),

    // Safety check: guarantee one row per purchase order (primary key)
    #"Removed Duplicate POs" = Table.Distinct(#"Trimmed Text Columns", {"PurchaseOrderId"}),

    // Replace the 6 missing Procurement Types with "Unknown"
    #"Filled Missing Procurement Type" = Table.ReplaceValue(#"Removed Duplicate POs", null, "Unknown", Replacer.ReplaceValue, {"ProcurementType"}),

    // List of recognised incoterm codes found in the data (ZO1 = company-specific/service code)
    IncotermCodes = {"DAP", "EXW", "CIP", "CIF", "FCA", "CPT", "CFR", "FOB", "FOR", "DDP", "DAT", "FAS", "ZO1"},

    // Split incoTerms part 1: the 3-letter code (e.g. "DAPSite Basis" -> "DAP")
    #"Added Incoterm Code" = Table.AddColumn(#"Filled Missing Procurement Type", "IncotermCode", each (
        let raw = [incoTerms], code = if raw = null then null else Text.Upper(Text.Start(raw, 3))
        in if code = null then "Not Specified" else if List.Contains(IncotermCodes, code) then code else "Other"), type text),

    // Split incoTerms part 2: the delivery place (e.g. "DAPSite Basis" -> "Site Basis")
    #"Added Incoterm Place" = Table.AddColumn(#"Added Incoterm Code", "IncotermPlace", each (
        if [incoTerms] = null or [IncotermCode] = "Other" then [incoTerms]
        else let place = Text.Trim(Text.Middle([incoTerms], 3)) in if place = "" then null else place), type text),

    // Remove the original fused incoTerms column
    #"Removed Original incoTerms" = Table.RemoveColumns(#"Added Incoterm Place", {"incoTerms"}),

    // Extract buyer name from Purchase Group Description ("AJKA-Kavle Ajit" -> "Kavle Ajit")
    #"Added Buyer Name" = Table.AddColumn(#"Removed Original incoTerms", "Buyer", each (
        if [PurchaseGroupDescription] = null then "Unknown"
        else if Text.Contains([PurchaseGroupDescription], "-") then Text.Trim(Text.AfterDelimiter([PurchaseGroupDescription], "-"))
        else [PurchaseGroupDescription]), type text),

    // Turn the 0/1 Ammended flag into readable labels
    #"Added Amendment Flag" = Table.AddColumn(#"Added Buyer Name", "AmendmentStatus", each if [Ammended] = 1 then "Amended" else "Original", type text),
    #"Removed Ammended Column" = Table.RemoveColumns(#"Added Amendment Flag", {"Ammended"}),

    // PO Year, used to pick the correct annual exchange rate
    #"Added PO Year" = Table.AddColumn(#"Removed Ammended Column", "POYear", each Date.Year([POCreationDate]), Int64.Type),

    // Look up the USD exchange rate by Currency + Year from the custom FX table
    #"Merged FX Rates" = Table.NestedJoin(#"Added PO Year", {"Currency", "POYear"}, Dim_FX_Rates, {"Currency", "Year"}, "FX", JoinKind.LeftOuter),
    #"Expanded FX Rate" = Table.ExpandTableColumn(#"Merged FX Rates", "FX", {"USD_per_Unit"}, {"FXRateToUSD"}),

    // Convert PO Amount to USD
    #"Added PO Amount USD" = Table.AddColumn(#"Expanded FX Rate", "POAmountUSD", each [POAmount] * [FXRateToUSD], type number),

    // Clear, business-friendly column names
    #"Renamed Columns" = Table.RenameColumns(#"Added PO Amount USD", {{"POAmount", "POAmountLocal"}, {"Currency", "POCurrency"}, {"poStatus", "POStatusCode"}})
in
    #"Renamed Columns"
