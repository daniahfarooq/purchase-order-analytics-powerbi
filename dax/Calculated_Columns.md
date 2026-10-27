# Calculated Columns

Five DAX calculated columns complement the Power Query transformations. They are used where a value depends on relationships between tables (which Power Query does not see) or is purely a display label.

## Dim_PO

### Invoice Status

Labels each PO as invoiced or not, based on whether any invoice references it. Used in slicers, filters and the PO table's colour coding.

```dax
Invoice Status =
IF ( COUNTROWS ( RELATEDTABLE ( Fact_Invoices ) ) > 0, "Invoiced", "Not Invoiced" )
```

### PO Status

Labels a PO as cancelled when every one of its lines is marked for deletion ("L"), the business rule from the brief.

```dax
PO Status =
VAR TotalLines = COUNTROWS ( RELATEDTABLE ( Fact_PO_Lines ) )
VAR DeletedLines =
    COUNTROWS ( FILTER ( RELATEDTABLE ( Fact_PO_Lines ), Fact_PO_Lines[DeletionIndicator] = "L" ) )
RETURN
    IF ( TotalLines > 0 && TotalLines = DeletedLines, "Cancelled", "Active" )
```

### Purchase Group Label

Readable slicer label combining the SAP purchase group code with the buyer's name, e.g. "Z03 - Kavle Ajit".

```dax
Purchase Group Label = Dim_PO[PurchaseGroup] & " - " & Dim_PO[Buyer]
```

## Dim_Date

### Has PO Data

Marks dates up to the latest PO date. Used by the previous-year and previous-quarter measures to compare like-for-like periods when the final year is incomplete.

```dax
Has PO Data = Dim_Date[Date] <= MAX ( Fact_PO_Lines[POCreationDate] )
```

## Dim_Vendor

### Country Label

Short country names for chart axes, so labels stay horizontal and readable.

```dax
Country Label =
SWITCH (
    Dim_Vendor[VendorCountry],
    "United Kingdom", "UK",
    "United States", "USA",
    "United Arab Emirates", "UAE",
    "Czech Republic", "Czechia",
    "South Korea", "S. Korea",
    Dim_Vendor[VendorCountry]
)
```
