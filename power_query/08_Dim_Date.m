let
    // Range covers every PO and invoice date, extended to full calendar years
    AllDates = List.Combine({Dim_PO[POCreationDate], Fact_Invoices[InvoiceDate]}),
    StartDate = Date.StartOfYear(List.Min(AllDates)),
    EndDate = Date.EndOfYear(List.Max(AllDates)),
    DayCount = Duration.Days(EndDate - StartDate) + 1,

    // One row per day
    #"Date List" = List.Dates(StartDate, DayCount, #duration(1, 0, 0, 0)),
    #"Converted to Table" = Table.FromList(#"Date List", Splitter.SplitByNothing(), type table [Date = date]),

    // Calendar attributes
    #"Added Year" = Table.AddColumn(#"Converted to Table", "Year", each Date.Year([Date]), Int64.Type),
    #"Added Quarter No" = Table.AddColumn(#"Added Year", "QuarterNo", each Date.QuarterOfYear([Date]), Int64.Type),
    #"Added Quarter" = Table.AddColumn(#"Added Quarter No", "Quarter", each "Q" & Text.From([QuarterNo]), type text),
    #"Added Year Quarter" = Table.AddColumn(#"Added Quarter", "YearQuarter", each Text.From([Year]) & " Q" & Text.From([QuarterNo]), type text),
    #"Added Year Quarter Sort" = Table.AddColumn(#"Added Year Quarter", "YearQuarterSort", each [Year] * 10 + [QuarterNo], Int64.Type),
    #"Added Month No" = Table.AddColumn(#"Added Year Quarter Sort", "MonthNo", each Date.Month([Date]), Int64.Type),
    #"Added Month Name" = Table.AddColumn(#"Added Month No", "MonthName", each Date.MonthName([Date], "en-US"), type text),
    #"Added Month Short" = Table.AddColumn(#"Added Month Name", "MonthShort", each Text.Start([MonthName], 3), type text),
    #"Added Year Month" = Table.AddColumn(#"Added Month Short", "YearMonth", each [MonthShort] & " " & Text.From([Year]), type text),
    #"Added Year Month Sort" = Table.AddColumn(#"Added Year Month", "YearMonthSort", each [Year] * 100 + [MonthNo], Int64.Type),
    #"Added Weekday Name" = Table.AddColumn(#"Added Year Month Sort", "WeekdayName", each Date.DayOfWeekName([Date], "en-US"), type text),
    #"Added Weekday No" = Table.AddColumn(#"Added Weekday Name", "WeekdayNo", each Date.DayOfWeek([Date], Day.Monday) + 1, Int64.Type),

    // Indian fiscal year (April-March), e.g. April 2022 to March 2023 = "FY 2022-23"
    #"Added Fiscal Year" = Table.AddColumn(#"Added Weekday No", "FiscalYear", each let fy = if [MonthNo] >= 4 then [Year] else [Year] - 1 in "FY " & Text.From(fy) & "-" & Text.End(Text.From(fy + 1), 2), type text),

    // Fiscal quarter: FQ1 = Apr-Jun, FQ2 = Jul-Sep, FQ3 = Oct-Dec, FQ4 = Jan-Mar
    #"Added Fiscal Quarter" = Table.AddColumn(#"Added Fiscal Year", "FiscalQuarter", each "FQ" & Text.From(Number.IntegerDivide(Number.Mod([MonthNo] + 8, 12), 3) + 1), type text)
in
    #"Added Fiscal Quarter"
