# InvoiceGuard seed scenarios

Each row is one seeded invoice (vendor + invoice number identify it; `KPW/2025/118` appears twice, under V-1002 and V-1006). Expected holds are the OPEN holds after `ig_match_pkg.validate_invoice`. Status is VALIDATED when no holds are open, otherwise ON_HOLD.

| Vendor | Invoice number | PO | Expected hold codes | What it demonstrates |
|---|---|---|---|---|
| V-1001 | SIS/2025/0457 | PO-1001 | none (VALIDATED) | Clean 2-line invoice, approvable by AP_MANAGER |
| V-1001 | SIS-2025-0457 | PO-1001 | DUP_EXACT | Same number after normalisation (later entry flagged, original not) |
| V-1001 | SIS/2025/0488 | PO-1001 | PRICE_VAR | Unit price 265 vs PO 250, beyond 2% tolerance; line-level hold, AP_MANAGER release |
| V-1001 | SIS/2025/0502 | PO-1001 | none (approved by APMGR1, paid by FINCTRL1) | Full workflow to PAID |
| V-1001 | SIS/2025/0519 | PO-1001 | TAX_VAR | Tax at 12% instead of PO rate 18% |
| V-1001 | SIS/2025/0533 | PO-1003 (header) | PO_VENDOR (line) | A line billed against a PO-1001 line on a PO-1003 invoice |
| V-1001 | SIS/2025/0540 | PO-1003 | QTY_ORD | 55 billed against 50 ordered (60 received) |
| V-1001 | SIS/2025/0551 | PO-1005 | NO_RECEIPT | PO line with no goods receipt (QTY_REC is suppressed in this case) |
| V-1001 | SIS/2025/0560 | PO-1007 (CLOSED) | PO_STATUS | Invoice against a closed PO |
| V-1001 | SIS/2025/0570 | PO-1010 | DATE_ANOMALY | Invoice dated before its PO |
| V-1001 | SIS/2025/0601 | PO-1011 | SPLIT_SUSPECT | First of two invoices just under 500000 within 7 days (sum 934150.50) |
| V-1001 | SIS/2025/0602 | PO-1011 | SPLIT_SUSPECT | Second leg of the split |
| V-1001 | SIS/2025/0470 | PO-1004 | none (VALIDATED) | Clean invoice above AP_MANAGER limit 500000; approval blocked with -20005 for APMGR1, FIN_CONTROLLER may approve |
| V-1001 | SIS/2025/0399 | PO-1014 | UNAUTH_APPROVAL (from scan) | Legacy invoice approved directly by BUYER1 (no authority, SoD, above limit); payment blocked until released |
| V-1002 | KPW/2025/118 | PO-1002 | none (VALIDATED) | Clean invoice; the reference for the duplicate scenarios |
| V-1002 | KPW/2025/0912 | PO-1002 | DUP_SUSPECT | Same vendor, same amount, different number, within 30 days |
| V-1002 | KPW/2025/121 | PO-1002 | none (VALIDATED) | Clean invoice entered by APMGR2 (segregation-of-duties test) |
| V-1002 | KPW/2025/124 | PO-1002 | AMT_MISMATCH | Header carries 500 more than lines plus tax |
| V-1002 | KPW/2025/130 | PO-1002 line 2 | QTY_REC | 30 billed against 25 net received (ordered 40, 2 rejected) |
| V-1002 | KPW/2025/133 | PO-1001 | PO_VENDOR (header) | Vendor V-1002 invoicing against a V-1001 PO |
| V-1002 | KPW/2025/0140 | PO-1013 | ROUND_AMT | Base amount exactly 250000.00 |
| V-1006 | KPW/2025/118 | PO-1006 | DUP_SUSPECT, BANK_CHANGE | Same number and amount as V-1002's invoice at another vendor; remit-to account shared with V-1002 |
| V-1004 | MAL/2025/0042 | PO-1008 | VENDOR_STATUS | Vendor INACTIVE |
| V-1003 | DEC/25-26/0088 | PO-1009 | BANK_CHANGE | Remit-to account changed 5 days ago (HIGH-risk vendor adds risk score) |
| V-1005 | HIM/2025/0007 | PO-1012 | GSTIN_INVALID | GSTIN check digit wrong (format valid) |

## Hold code coverage

| Hold code | Scenario |
|---|---|
| DUP_EXACT | SIS-2025-0457 |
| DUP_SUSPECT | KPW/2025/0912; KPW/2025/118 (V-1006) |
| PRICE_VAR | SIS/2025/0488 |
| QTY_REC | KPW/2025/130 |
| QTY_ORD | SIS/2025/0540 |
| NO_RECEIPT | SIS/2025/0551 |
| AMT_MISMATCH | KPW/2025/124 |
| TAX_VAR | SIS/2025/0519 |
| PO_VENDOR | KPW/2025/133 (header); SIS/2025/0533 (line) |
| PO_STATUS | SIS/2025/0560 |
| VENDOR_STATUS | MAL/2025/0042 |
| BANK_CHANGE | DEC/25-26/0088; KPW/2025/118 (V-1006) |
| DATE_ANOMALY | SIS/2025/0570 |
| SPLIT_SUSPECT | SIS/2025/0601, SIS/2025/0602 |
| GSTIN_INVALID | HIM/2025/0007 |
| ROUND_AMT | KPW/2025/0140 |
| UNAUTH_APPROVAL | SIS/2025/0399 (post-approval scan) |

## Design decisions

- DUP_EXACT and DUP_SUSPECT flag the later-entered invoice only. The earlier original stays clean, and cancelling the duplicate clears the hold on re-validation.
- QTY_REC only applies when the PO line has receipts; a line with no receipts raises NO_RECEIPT only.
- Released holds stay released on re-validation unless the invoice's business data (amounts, vendor, PO, bank) changed after the release.
