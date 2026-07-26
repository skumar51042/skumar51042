Option Explicit

' =========================================================================================
' ENTERPRISE RECONCILIATION SUITE V25.0 - ZERO OVERFLOW EDITION
' FIX 1: Removed all CLng() conversions to prevent Overflow on large Voucher/Phone numbers.
' FIX 2: Upgraded all Integer variables to Long to support infinite row scanning.
' FIX 3: Mapped columns E, J, K to successfully render the real-time "DIFF VALUE".
' =========================================================================================

Public Type ColMap
    DateCol As Long
    RefCol As Long
    PartCol As Long
    DebitCol As Long
    CreditCol As Long
End Type

Public Const APP_NAME As String = "Enterprise Recon Suite"
Public Const SH_DASHBOARD As String = "Dashboard"
Public Const SH_RAW_OURS As String = "Our_Data_Raw"
Public Const SH_RAW_VEND As String = "Vendor_Data_Raw"
Public Const SH_REP_MATCHED As String = "Auto_Cleared"
Public Const SH_REP_MISS_OURS As String = "Missing_Internally"
Public Const SH_REP_MISS_VEND As String = "Missing_at_Vendor"

Public Const COL_BG As Long = 16448244
Public Const COL_PRIMARY As Long = 6180650
Public Const COL_SUCCESS As Long = 6335015
Public Const COL_DANGER As Long = 3947745
Public Const COL_WARNING As Long = 1195119
Public Const COL_TEXT As Long = 9276800

Public Const TOLERANCE_AMT As Double = 0.5
Public Const CONFIDENCE_THRESHOLD As Double = 0.85

Private CalcState As Long

' =========================================================================================
' REGION: MACRO ENDPOINTS
' =========================================================================================
Public Sub Action_BuildEnterpriseEnvironment()
    Call BuildDashboardUI
End Sub

Public Sub Action_UploadOurs()
    Call ExtractPDF_PowerQuery(SH_RAW_OURS)
End Sub

Public Sub Action_UploadVendor()
    Call ExtractPDF_PowerQuery(SH_RAW_VEND)
End Sub

Public Sub Action_RunReconciliation()
    Call ExecuteEnterpriseReconciliation
End Sub

Public Sub Action_ExportReport()
    Call ExportExecutiveReport
End Sub

' =========================================================================================
' REGION: SYSTEM OPTIMIZATION
' =========================================================================================
Private Sub OptimizeStart(ByVal StatusMsg As String)
    CalcState = Application.Calculation
    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False
    Application.DisplayAlerts = False
    Application.StatusBar = StatusMsg
End Sub

Private Sub OptimizeEnd()
    Application.ScreenUpdating = True
    Application.Calculation = CalcState
    Application.EnableEvents = True
    Application.DisplayAlerts = True
    Application.StatusBar = False
End Sub

Private Function SafeSheetInit(ByVal SheetName As String) As Worksheet
    Dim ws As Worksheet
    Dim lo As ListObject
    Dim shp As Shape

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SheetName)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SheetName
    Else
        ws.Cells.Clear
        On Error Resume Next
        For Each lo In ws.ListObjects
            lo.Unlist
        Next lo
        For Each shp In ws.Shapes
            shp.Delete
        Next shp
        On Error GoTo 0
    End If

    Set SafeSheetInit = ws
End Function

' =========================================================================================
' REGION: DASHBOARD UI GENERATOR
' =========================================================================================
Private Sub BuildDashboardUI()
    Dim wsDash As Worksheet
    Dim wsOur As Worksheet
    Dim wsVen As Worksheet
    Dim ws As Worksheet

    Call OptimizeStart("Building UI...")

    Set wsDash = SafeSheetInit(SH_DASHBOARD)
    wsDash.Visible = xlSheetVisible
    wsDash.Activate

    Set wsOur = SafeSheetInit(SH_RAW_OURS)
    Set wsVen = SafeSheetInit(SH_RAW_VEND)
    wsOur.Visible = xlSheetHidden
    wsVen.Visible = xlSheetHidden

    Call SafeSheetInit(SH_REP_MISS_VEND)
    Call SafeSheetInit(SH_REP_MISS_OURS)
    Call SafeSheetInit(SH_REP_MATCHED)

    Application.DisplayAlerts = False
    For Each ws In ThisWorkbook.Worksheets
        If ws.Name <> SH_DASHBOARD And _
           ws.Name <> SH_RAW_OURS And _
           ws.Name <> SH_RAW_VEND And _
           ws.Name <> SH_REP_MISS_VEND And _
           ws.Name <> SH_REP_MISS_OURS And _
           ws.Name <> SH_REP_MATCHED Then
            On Error Resume Next
            ws.Delete
            On Error GoTo 0
        End If
    Next ws
    Application.DisplayAlerts = True

    wsDash.Cells.Interior.Color = COL_BG
    ActiveWindow.DisplayGridlines = False

    wsDash.Columns("A").ColumnWidth = 2
    wsDash.Columns("B:K").ColumnWidth = 15

    wsDash.Range("B2").Value = "ENTERPRISE RECONCILIATION SUMMARY"
    wsDash.Range("B2").Font.Color = COL_TEXT
    wsDash.Range("B2").Font.Bold = True

    Call DrawGridCard(wsDash, "B", "C", 4, "TRANSACTIONS MATCHED", "0", "Auto + Fuzzy Cleared", COL_SUCCESS, "CardMatchCount")
    Call DrawGridCard(wsDash, "D", "E", 4, "CLEARED VALUE", "Rs. 0.00", "Total Validated Amount", COL_SUCCESS, "CardMatchVal")
    Call DrawGridCard(wsDash, "F", "G", 4, "MISSING AT VENDOR", "0", "Unrecorded by Vendor", COL_DANGER, "CardMissVen")
    Call DrawGridCard(wsDash, "H", "I", 4, "MISSING INTERNALLY", "0", "Unrecorded by Us", COL_DANGER, "CardMissOur")
    Call DrawGridCard(wsDash, "J", "K", 4, "CLOSING VARIANCE", "Rs. 0.00", "Net Difference", COL_DANGER, "CardVar")

    wsDash.Range("B9").Value = "FINANCIAL LEDGER COMPARISON"
    wsDash.Range("B9").Font.Color = COL_TEXT
    wsDash.Range("B9").Font.Bold = True

    Call DrawUnifiedLedger(wsDash)

    wsDash.Range("B23").Value = "VARIANCE ANALYSIS - LINE BY LINE"
    wsDash.Range("B23").Font.Color = COL_TEXT
    wsDash.Range("B23").Font.Bold = True

    Call DrawGridCard(wsDash, "B", "C", 24, "PURCHASE VS SALES", "Rs. 0.00", "Our: 0 | Ven: 0", COL_DANGER, "VarPurSal")
    Call DrawGridCard(wsDash, "D", "E", 24, "PAYMENT VS RECEIPT", "Rs. 0.00", "Our: 0 | Ven: 0", COL_DANGER, "VarPayRec")
    Call DrawGridCard(wsDash, "F", "G", 24, "OUR DN VS VEND CN", "Rs. 0.00", "Our: 0 | Ven: 0", COL_DANGER, "VarDNCN")
    Call DrawGridCard(wsDash, "H", "I", 24, "OUR CN VS VEND DN", "Rs. 0.00", "Our: 0 | Ven: 0", COL_DANGER, "VarCNDN")
    Call DrawGridCard(wsDash, "J", "K", 24, "NET VARIANCE", "Rs. 0.00", "Our: 0 | Ven: 0", COL_DANGER, "VarNet")

    Call DrawButton(wsDash, 1050, 60, 180, 35, "1. Upload Tally PDF", "Action_UploadOurs", COL_PRIMARY)
    Call DrawButton(wsDash, 1050, 105, 180, 35, "2. Upload Vendor PDF", "Action_UploadVendor", COL_PRIMARY)
    Call DrawButton(wsDash, 1050, 150, 180, 45, "3. Run Enterprise Recon", "Action_RunReconciliation", COL_SUCCESS)
    Call DrawButton(wsDash, 1050, 205, 180, 35, "4. Export Exec Report", "Action_ExportReport", RGB(41, 128, 185))

    Call OptimizeEnd
    MsgBox "Dashboard UI Built Successfully!", vbInformation, APP_NAME
End Sub

Private Sub DrawGridCard(ByVal ws As Worksheet, ByVal C1 As String, ByVal C2 As String, ByVal r As Long, ByVal Title As String, ByVal val As String, ByVal SubT As String, ByVal Col As Long, ByVal Nme As String)
    Dim rng As Range

    ws.Range(C1 & r & ":" & C2 & r).Merge
    ws.Range(C1 & (r + 1) & ":" & C2 & (r + 1)).Merge
    ws.Range(C1 & (r + 2) & ":" & C2 & (r + 2)).Merge

    ws.Range(C1 & r).Value = Title
    ws.Range(C1 & r).Font.Size = 8
    ws.Range(C1 & r).Font.Color = COL_TEXT
    ws.Range(C1 & r).Font.Bold = True

    ws.Range(C1 & (r + 1)).Value = val
    ws.Range(C1 & (r + 1)).Font.Size = 16
    ws.Range(C1 & (r + 1)).Font.Color = Col
    ws.Range(C1 & (r + 1)).Font.Bold = True
    ws.Range(C1 & (r + 1)).Name = Nme & "_V"

    ws.Range(C1 & (r + 2)).Value = SubT
    ws.Range(C1 & (r + 2)).Font.Size = 8
    ws.Range(C1 & (r + 2)).Font.Color = RGB(149, 165, 166)
    ws.Range(C1 & (r + 2)).Name = Nme & "_S"

    Set rng = ws.Range(C1 & r & ":" & C2 & (r + 2))
    rng.Interior.Color = vbWhite
    rng.BorderAround xlContinuous, xlThin, RGB(220, 224, 228)
    rng.RowHeight = 20
    rng.VerticalAlignment = xlVAlignCenter
    ws.Range(C1 & r).RowHeight = 15
    ws.Range(C1 & (r + 2)).RowHeight = 15
End Sub

Private Sub DrawUnifiedLedger(ByVal ws As Worksheet)
    Dim r As Long
    Dim rng As Range

    ws.Range("B10:D10").Merge
    ws.Range("B10").Value = "OUR INTERNAL LEDGER (TALLY)"
    ws.Range("B10").Font.Color = COL_PRIMARY
    ws.Range("B10").Font.Bold = True

    ws.Range("E10").Value = "AMOUNT"
    ws.Range("E10").HorizontalAlignment = xlRight
    ws.Range("E10").Font.Size = 8
    ws.Range("E10").Font.Color = COL_TEXT

    ws.Range("G10:I10").Merge
    ws.Range("G10").Value = "VENDOR STATEMENT (VARUN)"
    ws.Range("G10").Font.Color = COL_PRIMARY
    ws.Range("G10").Font.Bold = True

    ws.Range("J10").Value = "AMOUNT"
    ws.Range("J10").HorizontalAlignment = xlRight
    ws.Range("J10").Font.Size = 8
    ws.Range("J10").Font.Color = COL_TEXT

    ws.Range("K10").Value = "DIFF VALUE"
    ws.Range("K10").HorizontalAlignment = xlRight
    ws.Range("K10").Font.Size = 8
    ws.Range("K10").Font.Color = COL_TEXT

    r = 12
    Call SetLedgerRow(ws, r, "Opening Balance", "Opening Balance")
    Call SetLedgerRow(ws, r + 1, "Purchases (+)", "Sales (+)")
    Call SetLedgerRow(ws, r + 2, "Credit Notes (+)", "Debit Notes (+)")
    Call SetLedgerRow(ws, r + 3, "Other Credits (+)", "Other Debits (+)")
    Call SetLedgerRow(ws, r + 4, "Payments (-)", "Receipts (-)")
    Call SetLedgerRow(ws, r + 5, "Debit Notes (-)", "Credit Notes (-)")
    Call SetLedgerRow(ws, r + 6, "Other Debits (-)", "Other Credits (-)")

    r = r + 8
    ws.Range("B" & r & ":D" & r).Merge
    ws.Range("B" & r).Value = "Computed Closing Balance"
    ws.Range("B" & r).Font.Bold = True
    ws.Range("G" & r & ":I" & r).Merge
    ws.Range("G" & r).Value = "Computed Closing Balance"
    ws.Range("G" & r).Font.Bold = True

    ws.Range("E" & r).Font.Bold = True
    ws.Range("J" & r).Font.Bold = True
    ws.Range("K" & r).Font.Bold = True

    Set rng = ws.Range("B10:K" & r)
    rng.Interior.Color = vbWhite
    rng.Borders(xlInsideHorizontal).LineStyle = xlContinuous
    rng.Borders(xlInsideHorizontal).Color = RGB(220, 224, 228)
    rng.BorderAround xlContinuous, xlThin, RGB(220, 224, 228)
    rng.RowHeight = 22
    ws.Range("B10:K10").RowHeight = 25
End Sub

Private Sub SetLedgerRow(ByVal ws As Worksheet, ByVal r As Long, ByVal lblOur As String, ByVal lblVen As String)
    ws.Range("B" & r & ":D" & r).Merge
    ws.Range("B" & r).Value = lblOur
    ws.Range("B" & r).Font.Size = 10

    ws.Range("G" & r & ":I" & r).Merge
    ws.Range("G" & r).Value = lblVen
    ws.Range("G" & r).Font.Size = 10

    ws.Range("E" & r).HorizontalAlignment = xlRight
    ws.Range("J" & r).HorizontalAlignment = xlRight
    ws.Range("K" & r).HorizontalAlignment = xlRight

    ws.Range("E" & r).Value = "Rs. 0.00"
    ws.Range("E" & r).Font.Bold = True
    ws.Range("J" & r).Value = "Rs. 0.00"
    ws.Range("J" & r).Font.Bold = True
    ws.Range("K" & r).Value = "Rs. 0.00"
    ws.Range("K" & r).Font.Bold = True
End Sub

Private Sub DrawButton(ByVal ws As Worksheet, ByVal L As Double, ByVal T As Double, ByVal W As Double, ByVal H As Double, ByVal Txt As String, ByVal Mac As String, ByVal Col As Long)
    Dim btn As Object
    Set btn = ws.Shapes.AddShape(msoShapeRoundedRectangle, L, T, W, H)
    btn.TextFrame.Characters.Text = Txt
    btn.TextFrame.Characters.Font.Bold = True
    btn.TextFrame.Characters.Font.Color = vbWhite
    btn.TextFrame.VerticalAlignment = xlVAlignCenter
    btn.TextFrame.HorizontalAlignment = xlHAlignCenter
    btn.Fill.ForeColor.RGB = Col
    btn.Line.Visible = msoFalse
    btn.OnAction = Mac
End Sub

' -----------------------------------------------------------------------------------------
' POWER QUERY ENGINE
' -----------------------------------------------------------------------------------------
Private Sub ExtractPDF_PowerQuery(ByVal TargetSheet As String)
    Dim fd As FileDialog
    Dim filePath As String
    Dim ws As Worksheet
    Dim qryName As String
    Dim mCode As String
    Dim lo As ListObject

    Set fd = Application.FileDialog(msoFileDialogFilePicker)

    With fd
        .Title = "Select PDF File (" & TargetSheet & ")"
        .Filters.Clear
        .Filters.Add "PDF Files", "*.pdf"
        If .Show = -1 Then
            filePath = .SelectedItems(1)
        Else
            Exit Sub
        End If
    End With

    Call OptimizeStart("Extracting Data... Please wait.")

    Set ws = ThisWorkbook.Sheets(TargetSheet)
    ws.Cells.Clear

    qryName = "PQ_Recon_" & Format(Now, "hhmmss")

    ' FIX: Ensure only [Kind] = "Page" is selected to prevent 2x duplication bugs
    mCode = "let " & _
            "Source = Pdf.Tables(File.Contents(""" & filePath & """), [Implementation=""1.3""]), " & _
            "FilteredRows = Table.SelectRows(Source, each ([Kind] = ""Page"")), " & _
            "Combined = Table.Combine(FilteredRows[Data]) " & _
            "in Combined"

    On Error Resume Next
    ThisWorkbook.Queries(qryName).Delete
    ThisWorkbook.Connections("Query - " & qryName).Delete
    On Error GoTo PQError

    ThisWorkbook.Queries.Add Name:=qryName, Formula:=mCode

    Set lo = ws.ListObjects.Add(SourceType:=0, Source:="OLEDB;Provider=Microsoft.Mashup.OleDb.1;Data Source=$Workbook$;Location=" & qryName, Destination:=ws.Range("$A$1"))
    With lo.QueryTable
        .CommandType = xlCmdSql
        .CommandText = Array("SELECT * FROM [" & qryName & "]")
        .Refresh BackgroundQuery:=False
    End With

    On Error Resume Next
    If ws.ListObjects.Count > 0 Then
        ws.ListObjects(1).Unlist
    End If

    ThisWorkbook.Queries(qryName).Delete
    ThisWorkbook.Connections("Query - " & qryName).Delete
    On Error GoTo 0

    Call OptimizeEnd
    MsgBox "PDF Imported Successfully!", vbInformation, APP_NAME
    Exit Sub

PQError:
    On Error Resume Next
    ThisWorkbook.Queries(qryName).Delete
    ThisWorkbook.Connections("Query - " & qryName).Delete
    Call OptimizeEnd
    MsgBox "Extraction Failed. Ensure file is not corrupted.", vbCritical, APP_NAME
End Sub

' -----------------------------------------------------------------------------------------
' CORE ENTERPRISE RECONCILIATION ENGINE (PURE REGEX BASED)
' -----------------------------------------------------------------------------------------
Private Sub ExecuteEnterpriseReconciliation()
    Dim wsOurs As Worksheet
    Dim wsVen As Worksheet
    Dim wsDash As Worksheet
    Dim arrOurs As Variant
    Dim arrVen As Variant
    Dim dictOurs As Object
    Dim dictType As Object
    Dim dictDate As Object
    Dim dictOrig As Object
    Dim arrMatch() As Variant
    Dim arrMissO() As Variant
    Dim arrMissV() As Variant
    Dim rM As Long
    Dim rMO As Long
    Dim rMV As Long
    Dim maxOut As Long
    Dim oOB As Double, oPur As Double, oCN As Double, oPay As Double, oDN As Double, oOC As Double, oOD As Double
    Dim vOB As Double, vSal As Double, vDN As Double, vRec As Double, vCN As Double, vOD As Double, vOC As Double
    Dim stMatchVal As Double, stMissOurs As Double, stMissVen As Double
    Dim i As Long
    Dim rowStr As String
    Dim amt As Double
    Dim dte As String
    Dim ref As String
    Dim typ As String
    Dim k As Variant
    Dim cOur As Double
    Dim cVen As Double
    Dim fKey As Variant
    Dim fFound As Boolean

    Set wsOurs = ThisWorkbook.Sheets(SH_RAW_OURS)
    Set wsVen = ThisWorkbook.Sheets(SH_RAW_VEND)
    Set wsDash = ThisWorkbook.Sheets(SH_DASHBOARD)

    If WorksheetFunction.CountA(wsOurs.Cells) = 0 Or WorksheetFunction.CountA(wsVen.Cells) = 0 Then
        MsgBox "Missing Data. Upload both PDFs first.", vbCritical, APP_NAME
        Exit Sub
    End If

    Call OptimizeStart("Running Enterprise RegEx Engine...")

    arrOurs = wsOurs.UsedRange.Value
    arrVen = wsVen.UsedRange.Value

    Set dictOurs = CreateObject("Scripting.Dictionary")
    Set dictType = CreateObject("Scripting.Dictionary")
    Set dictDate = CreateObject("Scripting.Dictionary")
    Set dictOrig = CreateObject("Scripting.Dictionary")

    rM = 1
    rMO = 1
    rMV = 1
    maxOut = UBound(arrOurs, 1) + UBound(arrVen, 1) + 10

    ReDim arrMatch(1 To maxOut, 1 To 8)
    ReDim arrMissO(1 To maxOut, 1 To 8)
    ReDim arrMissV(1 To maxOut, 1 To 8)

    ' ----------------------------------------------------
    ' PASS 1: INTERNAL LEDGER (TALLY)
    ' ----------------------------------------------------
    Application.StatusBar = "Processing Internal Ledger..."

    For i = 1 To UBound(arrOurs, 1)
        rowStr = UCase(JoinRow(arrOurs, i))

        If InStr(rowStr, "BROUGHT") > 0 Or InStr(rowStr, "CARRIED") > 0 Or InStr(rowStr, "PAGE") > 0 Then
            GoTo NxtO
        End If

        amt = ExtractAmountRegEx(rowStr)
        If amt = 0 Then
            GoTo NxtO
        End If

        dte = ExtractDateRegEx(rowStr)
        typ = ""

        If InStr(rowStr, "OPENING BALANCE") > 0 Then
            oOB = oOB + amt
            GoTo NxtO
        ElseIf InStr(rowStr, "CLOSING BALANCE") > 0 Then
            GoTo NxtO
        ElseIf InStr(rowStr, "PURCHASE") > 0 And InStr(rowStr, "DEBIT NOTE") = 0 And InStr(rowStr, "CREDIT NOTE") = 0 Then
            oPur = oPur + amt
            typ = "Purchase"
        ElseIf InStr(rowStr, "PAYMENT") > 0 Or InStr(rowStr, "HDFC BANK") > 0 Or InStr(rowStr, "ICICI BANK") > 0 Then
            oPay = oPay + amt
            typ = "Payment"
        ElseIf InStr(rowStr, "DEBIT NOTE") > 0 Then
            oDN = oDN + amt
            typ = "Debit Note"
        ElseIf InStr(rowStr, "CREDIT NOTE") > 0 Then
            oCN = oCN + amt
            typ = "Credit Note"
        ElseIf InStr(rowStr, " TO ") > 0 Then
            oOD = oOD + amt
            typ = "Other Debit"
        ElseIf InStr(rowStr, " BY ") > 0 Then
            oOC = oOC + amt
            typ = "Other Credit"
        End If

        If typ <> "" Then
            ref = ExtractRefRegEx(rowStr)
            If ref = "" Then
                ref = "INT_" & CStr(i)
            End If

            If dictOurs.exists(ref) Then
                dictOurs(ref) = dictOurs(ref) + amt
            Else
                dictOurs(ref) = amt
                dictDate(ref) = dte
                dictType(ref) = typ
                dictOrig(ref) = rowStr
            End If
        End If
NxtO:
    Next i

    ' ----------------------------------------------------
    ' PASS 2: VENDOR LEDGER (VARUN)
    ' ----------------------------------------------------
    Application.StatusBar = "Reconciling Vendor Data..."

    For i = 1 To UBound(arrVen, 1)
        rowStr = UCase(JoinRow(arrVen, i))

        If InStr(rowStr, "BROUGHT") > 0 Or InStr(rowStr, "CARRIED") > 0 Or InStr(rowStr, "PAGE") > 0 Then
            GoTo NxtV
        End If

        amt = ExtractAmountRegEx(rowStr)
        If amt = 0 Then
            GoTo NxtV
        End If

        dte = ExtractDateRegEx(rowStr)
        typ = ""

        If InStr(rowStr, "OPENING BALANCE") > 0 Then
            vOB = vOB + amt
            GoTo NxtV
        ElseIf InStr(rowStr, "CLOSING BALANCE") > 0 Then
            GoTo NxtV
        ElseIf InStr(rowStr, "SALES RETURN") > 0 Or InStr(rowStr, "CREDIT NOTE") > 0 Then
            vCN = vCN + amt
            typ = "Credit Note"
        ElseIf InStr(rowStr, "SALES") > 0 Then
            vSal = vSal + amt
            typ = "Sales"
        ElseIf InStr(rowStr, "RECEIPT") > 0 Or InStr(rowStr, "HDFC BANK") > 0 Or InStr(rowStr, "ICICI BANK") > 0 Then
            vRec = vRec + amt
            typ = "Receipt"
        ElseIf InStr(rowStr, "DEBIT NOTE") > 0 Then
            vDN = vDN + amt
            typ = "Debit Note"
        ElseIf InStr(rowStr, " TO ") > 0 Then
            vOD = vOD + amt
            typ = "Other Debit"
        ElseIf InStr(rowStr, " BY ") > 0 Then
            vOC = vOC + amt
            typ = "Other Credit"
        End If

        If typ <> "" Then
            ref = ExtractRefRegEx(rowStr)
            If ref = "" Then
                ref = "EXT_" & CStr(i)
            End If

            If dictOurs.exists(ref) Then
                ' Exact Match
                arrMatch(rM, 1) = dte
                arrMatch(rM, 2) = ref
                arrMatch(rM, 3) = ref
                arrMatch(rM, 4) = dictType(ref)
                arrMatch(rM, 5) = dictOurs(ref)
                arrMatch(rM, 6) = amt
                arrMatch(rM, 7) = amt
                arrMatch(rM, 8) = "Perfect Match"

                rM = rM + 1
                stMatchVal = stMatchVal + amt
                dictOurs.Remove ref
            Else
                ' Fuzzy Check
                fFound = False
                For Each fKey In dictOurs.keys
                    If Abs(dictOurs(fKey) - amt) <= TOLERANCE_AMT Then
                        If FuzzyDistance(ref, CStr(fKey)) > CONFIDENCE_THRESHOLD Or InStr(ref, CStr(fKey)) > 0 Or InStr(CStr(fKey), ref) > 0 Then
                            arrMatch(rM, 1) = dte
                            arrMatch(rM, 2) = fKey
                            arrMatch(rM, 3) = ref
                            arrMatch(rM, 4) = dictType(fKey)
                            arrMatch(rM, 5) = dictOurs(fKey)
                            arrMatch(rM, 6) = amt
                            arrMatch(rM, 7) = amt
                            arrMatch(rM, 8) = "Fuzzy Match"

                            rM = rM + 1
                            stMatchVal = stMatchVal + amt
                            dictOurs.Remove fKey
                            fFound = True
                            Exit For
                        End If
                    End If
                Next fKey

                If Not fFound Then
                    arrMissO(rMO, 1) = dte
                    arrMissO(rMO, 2) = ref
                    arrMissO(rMO, 3) = typ
                    arrMissO(rMO, 4) = Left(rowStr, 40)

                    If typ = "Sales" Then
                        arrMissO(rMO, 5) = amt
                        arrMissO(rMO, 6) = "-"
                    Else
                        arrMissO(rMO, 5) = "-"
                        arrMissO(rMO, 6) = amt
                    End If

                    arrMissO(rMO, 7) = amt
                    arrMissO(rMO, 8) = "Action Required"
                    rMO = rMO + 1
                    stMissOurs = stMissOurs + amt
                End If
            End If
        End If
NxtV:
    Next i

    ' ----------------------------------------------------
    ' PASS 3: MISSING AT VENDOR
    ' ----------------------------------------------------
    For Each k In dictOurs.keys
        arrMissV(rMV, 1) = dictDate(k)
        arrMissV(rMV, 2) = k
        arrMissV(rMV, 3) = dictType(k)
        arrMissV(rMV, 4) = Left(dictOrig(k), 40)

        If dictType(k) = "Payment" Then
            arrMissV(rMV, 5) = dictOurs(k)
            arrMissV(rMV, 6) = "-"
        Else
            arrMissV(rMV, 5) = "-"
            arrMissV(rMV, 6) = dictOurs(k)
        End If

        arrMissV(rMV, 7) = dictOurs(k)
        arrMissV(rMV, 8) = "Action Required"

        rMV = rMV + 1
        stMissVen = stMissVen + dictOurs(k)
    Next k

    Set dictOurs = Nothing
    Erase arrOurs
    Erase arrVen

    Application.StatusBar = "Formatting Reports..."
    Call OutputReportSheet(SH_REP_MATCHED, "Auto-Cleared Vouchers", "Validated 100%", COL_SUCCESS, Array("DATE", "OUR VCH", "VEND REF", "TYPE", "OUR AMT", "VEND AMT", "CLEARED AMT", "STATUS"), arrMatch, rM - 1)
    Call OutputReportSheet(SH_REP_MISS_OURS, "Missing Internally", "Vendor billed, we missed", COL_WARNING, Array("DATE", "VEND REF", "CATEGORY", "DESCRIPTION", "DR AMT", "CR AMT", "MATCH AMT", "ACTION"), arrMissO, rMO - 1)
    Call OutputReportSheet(SH_REP_MISS_VEND, "Missing at Vendor", "We booked, Vendor missed", COL_DANGER, Array("DATE", "OUR VCH", "CATEGORY", "DESCRIPTION", "DR AMT", "CR AMT", "MATCH AMT", "ACTION"), arrMissV, rMV - 1)

    cOur = oOB + oPur + oCN + oOC - oPay - oDN - oOD
    cVen = vOB + vSal + vDN + vOD - vRec - vCN - vOC

    With wsDash
        ' Opening Balance
        .Range("E12").Value = Format(oOB, "Rs. #,##0.00")
        .Range("J12").Value = Format(vOB, "Rs. #,##0.00")
        .Range("K12").Value = Format(Abs(oOB - vOB), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K12"), Abs(oOB - vOB))

        ' Purchase / Sales
        .Range("E13").Value = Format(oPur, "+ Rs. #,##0.00")
        .Range("E13").Font.Color = COL_SUCCESS
        .Range("J13").Value = Format(vSal, "+ Rs. #,##0.00")
        .Range("J13").Font.Color = COL_SUCCESS
        .Range("K13").Value = Format(Abs(oPur - vSal), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K13"), Abs(oPur - vSal))

        ' Credit Notes / Debit Notes
        .Range("E14").Value = Format(oCN, "+ Rs. #,##0.00")
        .Range("E14").Font.Color = COL_SUCCESS
        .Range("J14").Value = Format(vDN, "+ Rs. #,##0.00")
        .Range("J14").Font.Color = COL_SUCCESS
        .Range("K14").Value = Format(Abs(oCN - vDN), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K14"), Abs(oCN - vDN))

        ' Other Credits / Debits
        .Range("E15").Value = Format(oOC, "+ Rs. #,##0.00")
        .Range("E15").Font.Color = COL_SUCCESS
        .Range("J15").Value = Format(vOD, "+ Rs. #,##0.00")
        .Range("J15").Font.Color = COL_SUCCESS
        .Range("K15").Value = Format(Abs(oOC - vOD), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K15"), Abs(oOC - vOD))

        ' Payments / Receipts
        .Range("E16").Value = Format(oPay, "- Rs. #,##0.00")
        .Range("E16").Font.Color = COL_DANGER
        .Range("J16").Value = Format(vRec, "- Rs. #,##0.00")
        .Range("J16").Font.Color = COL_DANGER
        .Range("K16").Value = Format(Abs(oPay - vRec), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K16"), Abs(oPay - vRec))

        ' Debit Notes / Credit Notes
        .Range("E17").Value = Format(oDN, "- Rs. #,##0.00")
        .Range("E17").Font.Color = COL_DANGER
        .Range("J17").Value = Format(vCN, "- Rs. #,##0.00")
        .Range("J17").Font.Color = COL_DANGER
        .Range("K17").Value = Format(Abs(oDN - vCN), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K17"), Abs(oDN - vCN))

        ' Other Debits / Credits
        .Range("E18").Value = Format(oOD, "- Rs. #,##0.00")
        .Range("E18").Font.Color = COL_DANGER
        .Range("J18").Value = Format(vOC, "- Rs. #,##0.00")
        .Range("J18").Font.Color = COL_DANGER
        .Range("K18").Value = Format(Abs(oOD - vOC), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K18"), Abs(oOD - vOC))

        ' Closing Balances
        .Range("E20").Value = Format(cOur, "Rs. #,##0.00")
        .Range("J20").Value = Format(cVen, "Rs. #,##0.00")
        .Range("K20").Value = Format(Abs(cOur - cVen), "Rs. #,##0.00")
        Call SetDiffColor(.Range("K20"), Abs(cOur - cVen))

        Call UpdateGridCard(wsDash, "CardMatchCount", CStr(rM - 1), "Auto + Fuzzy Cleared", True)
        Call UpdateGridCard(wsDash, "CardMatchVal", "Rs. " & Format(stMatchVal, "#,##0.00"), "Total Validated Amount", True)
        Call UpdateGridCard(wsDash, "CardMissVen", CStr(rMV - 1), "Rs. " & Format(stMissVen, "#,##0.00") & " unrecorded", (rMV = 1))
        Call UpdateGridCard(wsDash, "CardMissOur", CStr(rMO - 1), "Rs. " & Format(stMissOurs, "#,##0.00") & " unrecorded", (rMO = 1))
        Call UpdateGridCard(wsDash, "CardVar", "Rs. " & Format(Abs(cOur - cVen), "#,##0.00"), "Net Difference", (Abs(cOur - cVen) < 1))

        Call UpdateGridCard(wsDash, "VarPurSal", "Rs. " & Format(Abs(oPur - vSal), "#,##0.00"), "Our: " & Format(oPur, "0") & " | Ven: " & Format(vSal, "0"), (Abs(oPur - vSal) < 1))
        Call UpdateGridCard(wsDash, "VarPayRec", "Rs. " & Format(Abs(oPay - vRec), "#,##0.00"), "Our: " & Format(oPay, "0") & " | Ven: " & Format(vRec, "0"), (Abs(oPay - vRec) < 1))
        Call UpdateGridCard(wsDash, "VarDNCN", "Rs. " & Format(Abs(oDN - vCN), "#,##0.00"), "Our: " & Format(oDN, "0") & " | Ven: " & Format(vCN, "0"), (Abs(oDN - vCN) < 1))
        Call UpdateGridCard(wsDash, "VarCNDN", "Rs. " & Format(Abs(oCN - vDN), "#,##0.00"), "Our: " & Format(oCN, "0") & " | Ven: " & Format(vDN, "0"), (Abs(oCN - vDN) < 1))
        Call UpdateGridCard(wsDash, "VarNet", "Rs. " & Format(Abs(cOur - cVen), "#,##0.00"), "Our: " & Format(cOur, "0") & " | Ven: " & Format(cVen, "0"), (Abs(cOur - cVen) < 1))
    End With

    Call OptimizeEnd
    MsgBox "Enterprise Reconciliation Complete!", vbInformation, APP_NAME
End Sub

Private Sub SetDiffColor(ByVal rng As Range, ByVal val As Double)
    If val < 1 Then
        rng.Font.Color = COL_SUCCESS
    Else
        rng.Font.Color = COL_DANGER
    End If
End Sub

' =========================================================================================
' REGION: REGEX PARSERS
' =========================================================================================
Private Function ExtractAmountRegEx(ByVal fullRow As String) As Double
    Dim reg As Object
    Dim matches As Object
    Dim lastVal As String
    Set reg = CreateObject("VBScript.RegExp")

    reg.Global = True
    reg.IgnoreCase = True
    reg.Pattern = "[0-9]{1,3}(,[0-9]{2,3})*\.[0-9]{2}"

    If reg.Test(fullRow) Then
        Set matches = reg.Execute(fullRow)
        lastVal = matches(matches.Count - 1).Value
        ExtractAmountRegEx = CDbl(Replace(lastVal, ",", ""))
    Else
        ExtractAmountRegEx = 0
    End If
End Function

Private Function ExtractDateRegEx(ByVal fullRow As String) As String
    Dim reg As Object
    Set reg = CreateObject("VBScript.RegExp")

    reg.Global = False
    reg.IgnoreCase = True
    reg.Pattern = "[0-9]{1,2}-[A-Z]{3}-[0-9]{2,4}"

    If reg.Test(fullRow) Then
        ExtractDateRegEx = reg.Execute(fullRow)(0).Value
    Else
        ExtractDateRegEx = "N/A"
    End If
End Function

Private Function ExtractRefRegEx(ByVal fullRow As String) As String
    Dim reg As Object
    Dim matches As Object
    Dim m As Object
    Dim matchStr As String
    Set reg = CreateObject("VBScript.RegExp")

    reg.Global = False
    reg.IgnoreCase = True
    reg.Pattern = "(VC|VCCN|INV|DN|CN)[-/0-9]+"

    If reg.Test(fullRow) Then
        matchStr = reg.Execute(fullRow)(0).Value
        ExtractRefRegEx = CleanNumber(matchStr)
        Exit Function
    End If

    reg.Global = True
    reg.Pattern = "\b[0-9]{1,6}\b"

    If reg.Test(fullRow) Then
        Set matches = reg.Execute(fullRow)
        For Each m In matches
            If Not IsDateLike(fullRow, m.FirstIndex) Then
                ExtractRefRegEx = CleanLeadingZeros(m.Value)
                Exit Function
            End If
        Next m
    End If
    ExtractRefRegEx = ""
End Function

Private Function CleanLeadingZeros(ByVal s As String) As String
    Do While Left(s, 1) = "0" And Len(s) > 1
        s = Mid(s, 2)
    Loop
    CleanLeadingZeros = s
End Function

Private Function CleanNumber(ByVal s As String) As String
    Dim px As Variant
    Dim p As Variant
    Dim i As Long
    Dim f As String

    px = Array("VCCN", "VC", "INV", "DN", "CN", "25-26", "26-26", "2025", "2026", "/", "-")
    For Each p In px
        s = Replace(UCase(s), p, "")
    Next p

    f = ""
    For i = 1 To Len(s)
        If IsNumeric(Mid(s, i, 1)) Then
            f = f & Mid(s, i, 1)
        End If
    Next i

    CleanNumber = CleanLeadingZeros(f)
End Function

Private Function IsDateLike(ByVal fullRow As String, ByVal idx As Long) As Boolean
    Dim nearText As String
    Dim startPos As Long

    If idx - 5 > 1 Then
        startPos = idx - 5
    Else
        startPos = 1
    End If

    nearText = Mid(fullRow, startPos, 15)
    If InStr(nearText, "JAN") > 0 Or InStr(nearText, "FEB") > 0 Or InStr(nearText, "MAR") > 0 Or InStr(nearText, "APR") > 0 Or InStr(nearText, "MAY") > 0 Or InStr(nearText, "JUN") > 0 Or InStr(nearText, "JUL") > 0 Or InStr(nearText, "AUG") > 0 Or InStr(nearText, "SEP") > 0 Or InStr(nearText, "OCT") > 0 Or InStr(nearText, "NOV") > 0 Or InStr(nearText, "DEC") > 0 Then
        IsDateLike = True
    Else
        IsDateLike = False
    End If
End Function

Private Function FuzzyDistance(ByVal s1 As String, ByVal s2 As String) As Double
    Dim matchCnt As Long
    Dim i As Long

    If s1 = s2 Then
        FuzzyDistance = 1
        Exit Function
    End If
    If Len(s1) = 0 Or Len(s2) = 0 Then
        FuzzyDistance = 0
        Exit Function
    End If

    matchCnt = 0
    For i = 1 To Len(s1)
        If InStr(1, s2, Mid(s1, i, 1)) > 0 Then
            matchCnt = matchCnt + 1
        End If
    Next i

    If Len(s1) > Len(s2) Then
        FuzzyDistance = matchCnt / Len(s1)
    Else
        FuzzyDistance = matchCnt / Len(s2)
    End If
End Function

' =========================================================================================
' REGION: UTILITIES & EXPORT
' =========================================================================================
Private Function SafeStr(ByVal val As Variant) As String
    On Error Resume Next
    If IsError(val) Then
        SafeStr = ""
    ElseIf IsNull(val) Or IsEmpty(val) Then
        SafeStr = ""
    Else
        SafeStr = Trim(CStr(val))
    End If
    On Error GoTo 0
End Function

Private Function JoinRow(ByVal arr As Variant, ByVal r As Long) As String
    Dim c As Long
    Dim res As String
    res = ""
    For c = 1 To UBound(arr, 2)
        res = res & " " & SafeStr(arr(r, c))
    Next c
    JoinRow = Trim(res)
End Function

Private Sub UpdateGridCard(ByVal ws As Worksheet, ByVal targetName As String, ByVal val As String, ByVal subTxt As String, ByVal isGood As Boolean)
    On Error Resume Next
    ws.Range(targetName & "_V").Value = val
    If isGood Then
        ws.Range(targetName & "_V").Font.Color = COL_SUCCESS
    Else
        ws.Range(targetName & "_V").Font.Color = COL_DANGER
    End If

    If subTxt <> "" Then
        ws.Range(targetName & "_S").Value = subTxt
    End If
    On Error GoTo 0
End Sub

Private Sub OutputReportSheet(ByVal wsName As String, ByVal Title As String, ByVal subTitle As String, ByVal Theme As Long, ByVal Headers As Variant, ByVal DataArr As Variant, ByVal RCnt As Long)
    Dim ws As Worksheet
    Dim c As Long
    Dim headRng As Range
    Dim drng As Range

    Set ws = ThisWorkbook.Sheets(wsName)
    ws.Cells.Clear
    ws.Cells.Interior.Color = COL_BG
    ActiveWindow.DisplayGridlines = False

    ws.Cells(2, 2).Value = Title
    ws.Cells(2, 2).Font.Size = 16
    ws.Cells(2, 2).Font.Bold = True
    ws.Cells(2, 2).Font.Color = Theme

    ws.Cells(3, 2).Value = subTitle
    ws.Cells(3, 2).Font.Size = 10
    ws.Cells(3, 2).Font.Color = COL_TEXT

    For c = LBound(Headers) To UBound(Headers)
        ws.Cells(5, c + 2).Value = Headers(c)
    Next c

    Set headRng = ws.Range(ws.Cells(5, 2), ws.Cells(5, UBound(Headers) + 2))
    headRng.Interior.Color = RGB(43, 45, 92)
    headRng.Font.Color = vbWhite
    headRng.Font.Bold = True
    headRng.RowHeight = 25
    headRng.VerticalAlignment = xlVAlignCenter
    headRng.HorizontalAlignment = xlCenter

    If RCnt > 0 Then
        Set drng = ws.Range(ws.Cells(6, 2), ws.Cells(5 + RCnt, UBound(Headers) + 2))
        drng.Value = DataArr
        drng.Interior.Color = vbWhite
        drng.Borders(xlInsideHorizontal).LineStyle = xlContinuous
        drng.Borders(xlInsideHorizontal).Color = RGB(220, 224, 228)
        drng.BorderAround xlContinuous, xlThin, RGB(220, 224, 228)
        drng.RowHeight = 20
        drng.VerticalAlignment = xlVAlignCenter
        drng.Columns(4).NumberFormat = "@"
        drng.Columns(5).NumberFormat = """Rs."" #,##0.00;@"
        drng.Columns(6).NumberFormat = """Rs."" #,##0.00;@"
        drng.Columns(7).NumberFormat = """Rs."" #,##0.00;@"
    End If
    ws.Columns("B:J").AutoFit
End Sub

Private Sub ExportExecutiveReport()
    Dim newWb As Workbook
    Dim fp As String

    ThisWorkbook.Sheets(Array(SH_DASHBOARD, SH_REP_MISS_VEND, SH_REP_MISS_OURS, SH_REP_MATCHED)).Copy
    Set newWb = ActiveWorkbook
    fp = Application.GetSaveAsFilename(InitialFileName:="Executive_Recon_" & Format(Now, "YYYYMMDD"), FileFilter:="Excel Files (*.xlsx), *.xlsx")

    If fp <> "False" Then
        newWb.SaveAs Filename:=fp, FileFormat:=xlOpenXMLWorkbook
        newWb.Close SaveChanges:=False
        MsgBox "Exported successfully!", vbInformation, APP_NAME
    Else
        newWb.Close False
    End If
End Sub
