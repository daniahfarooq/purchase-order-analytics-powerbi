// ============================================================================
// Raw source pattern (queries in group "1 - Raw Sources", load disabled)
// ----------------------------------------------------------------------------
// DataFolder is a text parameter holding the path to the data folder,
// ending with a backslash, e.g. "C:\PO_Dashboard\01_Data\".
// Every raw query reads its file through this parameter, so the report can be
// pointed at a new folder in one place. Raw queries are left untyped on purpose;
// all typing and cleaning happens in the clean queries (group "2 - Clean Tables").
// ============================================================================

// Raw_PO_Header (same pattern for Raw_PO_Lines, Raw_Vendors, Raw_Invoices)
let
    Source = Excel.Workbook(File.Contents(DataFolder & "PO_Header.xlsx"), null, true),
    Sheet1_Sheet = Source{[Item = "Sheet1", Kind = "Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(Sheet1_Sheet, [PromoteAllScalars = true])
in
    #"Promoted Headers"

// Raw_FX_Rates
let
    Source = Csv.Document(File.Contents(DataFolder & "FX_Rates_Annual.csv"), [Delimiter = ",", Columns = 3, Encoding = 65001, QuoteStyle = QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars = true])
in
    #"Promoted Headers"
