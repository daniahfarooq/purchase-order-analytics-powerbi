let
    Source = Raw_FX_Rates,

    // Set data types; en-US culture so decimals like 1.181 parse correctly on any PC
    #"Set Data Types" = Table.TransformColumnTypes(Source, {{"Currency", type text}, {"Year", Int64.Type}, {"USD_per_Unit", type number}}, "en-US"),

    // Standardise currency codes (upper case, no stray spaces)
    #"Standardised Currency" = Table.TransformColumns(#"Set Data Types", {{"Currency", each Text.Upper(Text.Trim(_)), type text}})
in
    #"Standardised Currency"
