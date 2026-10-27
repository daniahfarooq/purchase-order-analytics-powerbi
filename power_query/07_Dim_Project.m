let
    Source = Fact_PO_Lines,

    // One row per project code
    #"Kept Project Column" = Table.SelectColumns(Source, {"ProjectCode"}),
    #"Removed Duplicate Projects" = Table.Distinct(#"Kept Project Column"),

    // Project vs non-project spend, for the "how much spend is tied to projects" story
    #"Added Spend Type" = Table.AddColumn(#"Removed Duplicate Projects", "SpendType", each if [ProjectCode] = "No Project" then "Non-Project Spend" else "Project Spend", type text),

    // Project series = leading letters of the code (e.g. "A03106" -> "A", "ET760063266" -> "ET")
    #"Added Project Series" = Table.AddColumn(#"Added Spend Type", "ProjectSeries", each if [ProjectCode] = "No Project" then "None" else Text.Combine(List.FirstN(Text.ToList([ProjectCode]), each _ >= "A" and _ <= "Z")), type text),

    #"Sorted by Project Code" = Table.Sort(#"Added Project Series", {{"ProjectCode", Order.Ascending}})
in
    #"Sorted by Project Code"
