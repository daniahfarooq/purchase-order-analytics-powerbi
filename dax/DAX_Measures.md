# DAX Measures

All 44 measures in the Purchase Order Analytics report. They live in a dedicated `_Measures` table and are organised into 8 display folders.

## Conventions

- **Measures only.** Every number on the report comes from a measure; raw numeric columns are hidden in the model.
- **One base, many views.** `PO Amount USD` is the single base measure. Scaled versions (`(USD M)`, `(USD K)`), shares and time comparisons are built on top of it, so a change in logic happens in one place.
- **Line-level allocation.** PO value is stored per PO line (each PO's amount shared across its active lines by net value), so plant and project filters work while totals still reconcile to the PO header.
- **Readable units.** Card and chart measures use custom format strings such as `$#,0.00"M"`.

## Highlights

| Measure | What it demonstrates |
|---|---|
| [Cancelled PO Amount USD](#cancelled-po-amount-usd) | Business rule implemented exactly as specified, evaluated per PO. |
| [PO Amount PY USD](#po-amount-py-usd) | Like-for-like time intelligence that handles a partial final year. |
| [Invoice Amount by Invoice Date (USD M)](#invoice-amount-by-invoice-date-usd-m) | USERELATIONSHIP and TREATAS together: two fact tables, an inactive relationship, and full slicer support. |
| [Vendor Rank](#vendor-rank) | Ranking that stays correct when other vendor attributes are shown in the same visual. |
| [Share of Quarter %](#share-of-quarter-) | REMOVEFILTERS versus ALLSELECTED: shares measured against total spend, not just the visual's Top N. |
| [Days Open](#days-open) | As-of date logic for an operational follow-up list. |

## Contents

- [1. PO Value](#1-po-value) (5)
- [2. Volumes](#2-volumes) (3)
- [3. Cancellations](#3-cancellations) (5)
- [4. Invoices](#4-invoices) (10)
- [5. Vendors & Ranking](#5-vendors--ranking) (8)
- [6. Time Intelligence](#6-time-intelligence) (8)
- [7. Plants & Projects](#7-plants--projects) (4)
- [8. Report info](#8-report-info) (1)

## 1. PO Value

### PO Amount USD

Base measure. Total PO value in US dollars, summed from line-level allocated amounts so that it responds correctly to plant and project filters.

```dax
SUM ( Fact_PO_Lines[AllocatedPOAmountUSD] )
```
<sub>Format: `$#,0`</sub>

### PO Amount (USD M)

PO value in millions of US dollars, used on cards and charts.

```dax
DIVIDE ( [PO Amount USD], 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### Avg PO Value (USD K)

Average value per purchase order, in thousands of US dollars.

```dax
DIVIDE ( [PO Amount USD], [PO Count] ) / 1000
```
<sub>Format: `$#,0.0"K"`</sub>

### PO Amount (Local Currency)

PO value in its original currency. Returns a value only when a single currency is in context, so different currencies are never added together.

```dax
IF ( HASONEVALUE ( Dim_PO[POCurrency] ), SUM ( Fact_PO_Lines[AllocatedPOAmountLocal] ) )
```
<sub>Format: `#,0`</sub>

### Net PO Amount (USD M)

PO value excluding cancelled purchase orders.

```dax
[PO Amount (USD M)] - [Cancelled PO Amount (USD M)]
```
<sub>Format: `$#,0.00"M"`</sub>

## 2. Volumes

### PO Count

Number of distinct purchase orders in the current filter context.

```dax
DISTINCTCOUNT ( Fact_PO_Lines[PurchaseOrderId] )
```
<sub>Format: `#,0`</sub>

### PO Line Count

Number of PO line items.

```dax
COUNTROWS ( Fact_PO_Lines )
```
<sub>Format: `#,0`</sub>

### Vendor Count

Number of distinct vendors with purchase orders.

```dax
DISTINCTCOUNT ( Fact_PO_Lines[VendorId] )
```
<sub>Format: `#,0`</sub>

## 3. Cancellations

### Cancelled PO Amount USD

Value of cancelled POs. Implements the business rule from the brief: a PO is cancelled when its number of lines equals its number of lines marked for deletion ("L"). Evaluated per PO, so it responds to every slicer.

```dax
VAR CancelledPOs =
    FILTER (
        VALUES ( Fact_PO_Lines[PurchaseOrderId] ),
        CALCULATE ( COUNTROWS ( Fact_PO_Lines ) )
            = CALCULATE ( COUNTROWS ( Fact_PO_Lines ), Fact_PO_Lines[DeletionIndicator] = "L" )
    )
RETURN
    CALCULATE ( [PO Amount USD], CancelledPOs )
```
<sub>Format: `$#,0`</sub>

### Cancelled PO Amount (USD M)

Cancelled PO value in millions of US dollars.

```dax
DIVIDE ( [Cancelled PO Amount USD], 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### Cancelled PO Count

Number of cancelled POs, using the same rule.

```dax
COUNTROWS (
    FILTER (
        VALUES ( Fact_PO_Lines[PurchaseOrderId] ),
        CALCULATE ( COUNTROWS ( Fact_PO_Lines ) )
            = CALCULATE ( COUNTROWS ( Fact_PO_Lines ), Fact_PO_Lines[DeletionIndicator] = "L" )
    )
)
```
<sub>Format: `#,0`</sub>

### Cancelled % of PO Amount

Share of total PO value that was cancelled.

```dax
DIVIDE ( [Cancelled PO Amount USD], [PO Amount USD] )
```
<sub>Format: `0.0%`</sub>

### Cancelled Card Tooltip

Dynamic tooltip text for the Cancelled PO KPI card (count and share of value).

```dax
FORMAT ( [Cancelled PO Count], "#,0" ) & " cancelled POs, "
    & FORMAT ( [Cancelled % of PO Amount], "0.0%" )
    & " of PO value. Click to see the POs."
```
<sub>Returns text</sub>

## 4. Invoices

### Invoiced PO Count

Number of POs with at least one invoice.

```dax
CALCULATE ( [PO Count], Dim_PO[Invoice Status] = "Invoiced" )
```
<sub>Format: `#,0`</sub>

### Not Invoiced PO Count

Number of POs without any invoice.

```dax
CALCULATE ( [PO Count], Dim_PO[Invoice Status] = "Not Invoiced" )
```
<sub>Format: `#,0`</sub>

### % POs Invoiced

Share of POs with an invoice. Returns 0% (not blank) when none are invoiced, and blank only when there are no POs.

```dax
IF ( NOT ISBLANK ( [PO Count] ), DIVIDE ( [Invoiced PO Count] + 0, [PO Count] ) )
```
<sub>Format: `0.0%`</sub>

### Not Invoiced Active PO Count

Active (not cancelled) POs without an invoice: the finance follow-up population.

```dax
CALCULATE ( [PO Count], Dim_PO[Invoice Status] = "Not Invoiced", Dim_PO[PO Status] = "Active" )
```
<sub>Format: `#,0`</sub>

### Not Invoiced Active PO Amount (USD M)

Value of active POs without an invoice.

```dax
CALCULATE ( [PO Amount (USD M)], Dim_PO[Invoice Status] = "Not Invoiced", Dim_PO[PO Status] = "Active" )
```
<sub>Format: `$#,0.00"M"`</sub>

### Invoice Count

Number of invoices for the POs in context. TREATAS passes the PO filter from the line-item fact to the invoice fact, so vendor, plant and project slicers apply to invoices too.

```dax
CALCULATE (
    COUNTROWS ( Fact_Invoices ),
    TREATAS ( VALUES ( Fact_PO_Lines[PurchaseOrderId] ), Fact_Invoices[PurchaseOrderId] )
)
```
<sub>Format: `#,0`</sub>

### Invoice Amount (USD M)

Invoiced value for the POs in context, using the same TREATAS pattern.

```dax
DIVIDE (
    CALCULATE (
        SUM ( Fact_Invoices[InvoiceAmountUSD] ),
        TREATAS ( VALUES ( Fact_PO_Lines[PurchaseOrderId] ), Fact_Invoices[PurchaseOrderId] )
    ),
    1000000
)
```
<sub>Format: `$#,0.00"M"`</sub>

### Invoiced % of PO Value

Invoiced value as a share of PO value.

```dax
DIVIDE ( [Invoice Amount (USD M)], [PO Amount (USD M)] )
```
<sub>Format: `0.0%`</sub>

### Invoice Amount by Invoice Date (USD M)

Invoiced value by invoice date. USERELATIONSHIP activates the inactive Date-to-InvoiceDate relationship, while TREATAS keeps the vendor, plant and project filters (with the date filter removed from the PO set).

```dax
VAR POsInScope =
    CALCULATETABLE ( VALUES ( Fact_PO_Lines[PurchaseOrderId] ), REMOVEFILTERS ( Dim_Date ) )
RETURN
    DIVIDE (
        CALCULATE (
            SUM ( Fact_Invoices[InvoiceAmountUSD] ),
            USERELATIONSHIP ( Dim_Date[Date], Fact_Invoices[InvoiceDate] ),
            TREATAS ( POsInScope, Fact_Invoices[PurchaseOrderId] )
        ),
        1000000
    )
```
<sub>Format: `$#,0.00"M"`</sub>

### Days Open

Days from PO creation to the latest PO date in the data (a fixed as-of date), used to age the uninvoiced follow-up list.

```dax
VAR AsOfDate = CALCULATE ( MAX ( Dim_PO[POCreationDate] ), REMOVEFILTERS () )
RETURN
    IF (
        HASONEVALUE ( Dim_PO[PurchaseOrderId] ) && NOT ISBLANK ( [PO Amount USD] ),
        DATEDIFF ( MIN ( Dim_PO[POCreationDate] ), AsOfDate, DAY )
    )
```
<sub>Format: `#,0`</sub>

## 5. Vendors & Ranking

### Vendor Rank

Dense rank of a vendor by PO value. ALLSELECTED(Dim_Vendor) ranks against all vendors in the current selection, regardless of other vendor columns (such as country) shown in the visual.

```dax
IF (
    ISINSCOPE ( Dim_Vendor[VendorDisplayName] ) && NOT ISBLANK ( [PO Amount USD] ),
    RANKX ( ALLSELECTED ( Dim_Vendor ), [PO Amount USD], , DESC, DENSE )
)
```
<sub>Format: `#,0`</sub>

### Top 10 Vendors Amount (USD M)

Combined value of the ten largest vendors in the current selection (TOPN).

```dax
VAR Top10 = TOPN ( 10, ALLSELECTED ( Dim_Vendor[VendorDisplayName] ), [PO Amount USD], DESC )
RETURN
    DIVIDE ( CALCULATE ( [PO Amount USD], Top10 ), 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### Vendor Share %

A vendor's share of PO value among the vendors in the current selection.

```dax
DIVIDE ( [PO Amount USD], CALCULATE ( [PO Amount USD], ALLSELECTED ( Dim_Vendor ) ) )
```
<sub>Format: `0.0%`</sub>

### Top 10 Vendor Share %

Share of spend going to the top 10 vendors: a supplier-concentration indicator.

```dax
DIVIDE ( [Top 10 Vendors Amount (USD M)], [PO Amount (USD M)] )
```
<sub>Format: `0.0%`</sub>

### International Spend Share %

Share of spend with vendors outside India.

```dax
DIVIDE (
    CALCULATE ( [PO Amount USD], Dim_Vendor[VendorRegion] = "International" ),
    [PO Amount USD]
)
```
<sub>Format: `0.0%`</sub>

### Avg Spend per Vendor (USD K)

Average PO value per vendor, in thousands of US dollars.

```dax
DIVIDE ( [PO Amount USD], [Vendor Count] ) / 1000
```
<sub>Format: `$#,0.0"K"`</sub>

### Top 10 Table Title

Dynamic visual title that names the selected quarter.

```dax
IF (
    HASONEVALUE ( Dim_Date[YearQuarter] ),
    "Top 10 vendors in " & VALUES ( Dim_Date[YearQuarter] ),
    "Top 10 vendors across all quarters (pick a quarter on the left)"
)
```
<sub>Returns text</sub>

### Share of Quarter %

A vendor's share of the whole quarter's spend. REMOVEFILTERS ignores the table's Top 10 filter, so shares are measured against total spend rather than the top 10 only.

```dax
DIVIDE ( [PO Amount USD], CALCULATE ( [PO Amount USD], REMOVEFILTERS ( Dim_Vendor ) ) )
```
<sub>Format: `0.0%`</sub>

## 6. Time Intelligence

### PO Amount PY USD

Previous-year value on a like-for-like basis: only dates that have PO data are shifted back a year, so a partial year (data ends 26-Jun-2023) is compared with the same days of the prior year.

```dax
CALCULATE (
    [PO Amount USD],
    CALCULATETABLE ( DATEADD ( Dim_Date[Date], -1, YEAR ), Dim_Date[Has PO Data] = TRUE () )
)
```
<sub>Format: `$#,0`</sub>

### PO Amount PY (USD M)

Previous-year value in millions of US dollars.

```dax
DIVIDE ( [PO Amount PY USD], 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### PO Amount YoY %

Year-over-year change; blank when either year has no data.

```dax
VAR Curr = [PO Amount USD]
VAR Prev = [PO Amount PY USD]
RETURN
    IF ( NOT ISBLANK ( Curr ) && NOT ISBLANK ( Prev ), DIVIDE ( Curr - Prev, Prev ) )
```
<sub>Format: `0.0%`</sub>

### PO Amount PQ USD

Previous-quarter value, using the same like-for-like pattern.

```dax
CALCULATE (
    [PO Amount USD],
    CALCULATETABLE ( DATEADD ( Dim_Date[Date], -1, QUARTER ), Dim_Date[Has PO Data] = TRUE () )
)
```
<sub>Format: `$#,0`</sub>

### PO Amount QoQ %

Quarter-over-quarter change; blank when either quarter has no data.

```dax
VAR Curr = [PO Amount USD]
VAR Prev = [PO Amount PQ USD]
RETURN
    IF ( NOT ISBLANK ( Curr ) && NOT ISBLANK ( Prev ), DIVIDE ( Curr - Prev, Prev ) )
```
<sub>Format: `0.0%`</sub>

### PO Amount YTD (USD M)

Calendar year-to-date PO value.

```dax
DIVIDE ( CALCULATE ( [PO Amount USD], DATESYTD ( Dim_Date[Date] ) ), 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### PO Amount FYTD (USD M)

Fiscal year-to-date PO value, using the Indian fiscal year ending 31 March.

```dax
DIVIDE ( CALCULATE ( [PO Amount USD], DATESYTD ( Dim_Date[Date], "3/31" ) ), 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

### PO Amount PQ (USD M)

Previous-quarter value in millions of US dollars.

```dax
DIVIDE ( [PO Amount PQ USD], 1000000 )
```
<sub>Format: `$#,0.00"M"`</sub>

## 7. Plants & Projects

### Plant Count

Number of plants with PO lines.

```dax
DISTINCTCOUNT ( Fact_PO_Lines[PlantCode] )
```
<sub>Format: `#,0`</sub>

### Non-Project Spend (USD M)

PO value not linked to any project.

```dax
CALCULATE ( [PO Amount (USD M)], Dim_Project[SpendType] = "Non-Project Spend" )
```
<sub>Format: `$#,0.00"M"`</sub>

### Project Count

Number of projects with spend (excludes lines with no project).

```dax
CALCULATE ( DISTINCTCOUNT ( Fact_PO_Lines[ProjectCode] ), Dim_Project[SpendType] = "Project Spend" )
```
<sub>Format: `#,0`</sub>

### Project Spend Share %

Share of PO value linked to a project.

```dax
DIVIDE (
    CALCULATE ( [PO Amount USD], Dim_Project[SpendType] = "Project Spend" ),
    [PO Amount USD]
)
```
<sub>Format: `0.0%`</sub>

## 8. Report info

### Data As Of

Dynamic "data as of" label based on the latest PO creation date in the data.

```dax
"Data as of " & FORMAT ( CALCULATE ( MAX ( Dim_PO[POCreationDate] ), REMOVEFILTERS () ), "dd-mmm-yyyy" )
```
<sub>Returns text</sub>
