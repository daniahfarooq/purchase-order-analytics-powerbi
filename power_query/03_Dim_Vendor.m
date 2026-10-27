let
    Source = Raw_Vendors,

    // Keep only analytical columns; personal contact data (email, phone, address, GSTIN, salesperson) is deliberately excluded
    #"Kept Relevant Columns" = Table.SelectColumns(Source, {"VendorId", "VendorSapId", "VendorName", "VendorLocation", "VendorState", "VendorCountry", "VendorLocalCurrency", "VendorTypeDescription", "SupplierCategory", "SSIType"}),

    // Set data types
    #"Set Data Types" = Table.TransformColumnTypes(#"Kept Relevant Columns", {{"VendorId", Int64.Type}, {"VendorSapId", Int64.Type}, {"VendorName", type text}, {"VendorLocation", type text}, {"VendorState", type text}, {"VendorCountry", type text}, {"VendorLocalCurrency", type text}, {"VendorTypeDescription", type text}, {"SupplierCategory", type text}, {"SSIType", type text}}, "en-US"),

    // Safety check: one row per vendor (primary key)
    #"Removed Duplicate Vendors" = Table.Distinct(#"Set Data Types", {"VendorId"}),

    // Clean vendor names: trim and collapse double spaces
    #"Cleaned Vendor Names" = Table.TransformColumns(#"Removed Duplicate Vendors", {{"VendorName", each if _ = null then null else Text.Combine(List.Select(Text.Split(Text.Trim(_), " "), each _ <> ""), " "), type text}}),

    // Standardise capitalisation of city and state (e.g. "NEW DELHI" -> "New Delhi")
    #"Standardised City and State" = Table.TransformColumns(#"Cleaned Vendor Names", {{"VendorLocation", each if _ = null then null else Text.Proper(Text.Trim(_)), type text}, {"VendorState", each if _ = null then null else Text.Proper(Text.Trim(_)), type text}}),

    // Repair broken characters caused by wrong file encoding (e.g. "DÃ¤nemark" -> "Dänemark")
    #"Repaired Country Encoding" = Table.TransformColumns(#"Standardised City and State", {{"VendorCountry", each if _ <> null and Text.Contains(_, "Ã") then (try Text.FromBinary(Text.ToBinary(_, 28591), TextEncoding.Utf8) otherwise _) else Text.Trim(_), type text}}),

    // Lookup list: German country names -> English
    CountryTranslation = [#"Argentinien" = "Argentina", #"Australien" = "Australia", #"Bangladesch" = "Bangladesh", #"Belgien" = "Belgium", #"Brasilien" = "Brazil", #"China" = "China", #"Deutschland" = "Germany", #"Dänemark" = "Denmark", #"Finnland" = "Finland", #"Frankreich" = "France", #"Hongkong" = "Hong Kong", #"Indien" = "India", #"Indonesien" = "Indonesia", #"Israel" = "Israel", #"Italien" = "Italy", #"Japan" = "Japan", #"Kanada" = "Canada", #"Luxemburg" = "Luxembourg", #"Malaysia" = "Malaysia", #"Malta" = "Malta", #"Niederlande" = "Netherlands", #"Philippinen" = "Philippines", #"Polen" = "Poland", #"Russische Foed." = "Russia", #"Schweden" = "Sweden", #"Schweiz" = "Switzerland", #"Singapur" = "Singapore", #"Slowenien" = "Slovenia", #"Spanien" = "Spain", #"Südkorea" = "South Korea", #"Taiwan" = "Taiwan", #"Thailand" = "Thailand", #"Tschechische Re" = "Czech Republic", #"Türkei" = "Turkey", #"USA" = "United States", #"United Kingdom" = "United Kingdom", #"Ver.Arab.Emir." = "United Arab Emirates", #"Vietnam" = "Vietnam", #"Österreich" = "Austria"],

    // Translate country names to English (unknown values are kept as they are)
    #"Translated Country Names" = Table.TransformColumns(#"Repaired Country Encoding", {{"VendorCountry", each if _ = null then "Unknown" else if Text.EndsWith(_, "sterreich") then "Austria" else Record.FieldOrDefault(CountryTranslation, _, _), type text}}),

    // Domestic (India) vs International vendor, useful for import analysis
    #"Added Vendor Region" = Table.AddColumn(#"Translated Country Names", "VendorRegion", each if [VendorCountry] = "India" then "Domestic" else "International", type text),

    // Replace blanks in optional classification columns
    #"Filled Blank Categories" = Table.ReplaceValue(#"Added Vendor Region", null, "Not Classified", Replacer.ReplaceValue, {"SupplierCategory", "SSIType"}),

    // Unique display name (name + SAP code): 87 vendors used in POs share a name with another vendor
    #"Added Vendor Display Name" = Table.AddColumn(#"Filled Blank Categories", "VendorDisplayName", each [VendorName] & " (" & Text.From([VendorSapId]) & ")", type text),

    // Business-friendly column names
    #"Renamed Columns" = Table.RenameColumns(#"Added Vendor Display Name", {{"VendorLocation", "VendorCity"}, {"VendorTypeDescription", "VendorType"}, {"VendorLocalCurrency", "VendorCurrency"}}),

    // One source cell contained "-junner dist - Pune", which Excel read as a formula and turned into an error. Replaced with "Pune".
    #"Fixed Excel Error in City" = Table.ReplaceErrorValues(#"Renamed Columns", {{"VendorCity", "Pune"}})
in
    #"Fixed Excel Error in City"
