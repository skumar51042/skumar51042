# Enterprise Reconciliation Suite

This repository contains an Excel VBA module for building and running an enterprise ledger reconciliation dashboard.

## Included macro module

- `EnterpriseReconSuite.bas` builds a dashboard, imports internal and vendor PDF ledger data through Power Query, reconciles transactions with exact and fuzzy matching, and exports an executive reconciliation workbook.
- The module is the V25.0 zero-overflow edition, which avoids `CLng()` conversions for large voucher or phone-like values and uses `Long` counters for row processing.

## Usage

1. Open the target Excel workbook.
2. Import `EnterpriseReconSuite.bas` into the VBA editor.
3. Run `Action_BuildEnterpriseEnvironment` to create the dashboard and hidden raw-data sheets.
4. Use the dashboard buttons to import the internal and vendor PDFs, run reconciliation, and export the executive report.
