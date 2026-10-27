let
    Source = Fact_PO_Lines,

    // One row per plant (each plant code has exactly one name)
    #"Kept Plant Columns" = Table.SelectColumns(Source, {"PlantCode", "PlantName"}),
    #"Removed Duplicate Plants" = Table.Distinct(#"Kept Plant Columns", {"PlantCode"}),

    // Location without the "SMI " company prefix (e.g. "SMI Gurgaon" -> "Gurgaon")
    #"Added Plant Location" = Table.AddColumn(#"Removed Duplicate Plants", "PlantLocation", each if Text.StartsWith([PlantName], "SMI ") then Text.Trim(Text.Middle([PlantName], 4)) else [PlantName], type text),

    // Label for slicers and visuals, e.g. "8500 - SMI Gurgaon"
    #"Added Plant Label" = Table.AddColumn(#"Added Plant Location", "PlantLabel", each Text.From([PlantCode]) & " - " & [PlantName], type text),

    #"Sorted by Plant Code" = Table.Sort(#"Added Plant Label", {{"PlantCode", Order.Ascending}})
in
    #"Sorted by Plant Code"
