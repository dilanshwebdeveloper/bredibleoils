import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/fmt.dart';

Future<Uint8List> buildInvoicePdf(Map<String, dynamic> inv, Map<String, dynamic> co) async {
  final logo = pw.MemoryImage((await rootBundle.load('assets/logo.jpg')).buffer.asUint8List());
  final lines = (inv['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final inter = inv['interstate'] == true;
  const fs = 9.0;

  pw.Widget cell(String t, {bool bold = false, pw.Alignment al = pw.Alignment.centerLeft}) => pw.Container(
        padding: const pw.EdgeInsets.all(4),
        alignment: al,
        child: pw.Text(t, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  const right = pw.Alignment.centerRight;

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        cell('#', bold: true), cell('Description', bold: true), cell('HSN', bold: true),
        cell('Qty (KG)', bold: true, al: right), cell('Rate/KG', bold: true, al: right),
        cell('Taxable', bold: true, al: right), cell('GST %', bold: true, al: right),
      ],
    ),
    for (var i = 0; i < lines.length; i++)
      pw.TableRow(children: [
        cell('${i + 1}'), cell('${lines[i]['product']}'), cell('${lines[i]['hsn']}'),
        cell(kg(lines[i]['kg']), al: right), cell(n(lines[i]['rate']).toStringAsFixed(2), al: right),
        cell(n(lines[i]['taxable']).toStringAsFixed(2), al: right), cell('${lines[i]['gst']}', al: right),
      ]),
  ];

  pw.Widget totalRow(String l, String v, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(width: 140, child: cell(l, bold: bold)),
          pw.SizedBox(width: 90, child: cell(v, bold: bold, al: right)),
        ],
      );

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Image(logo, width: 80),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${co['companyName'] ?? ''}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Factory: ${co['factoryAddress'] ?? ''}', style: const pw.TextStyle(fontSize: fs)),
            if ('${co['registeredOffice'] ?? ''}'.isNotEmpty)
              pw.Text('Regd. Office: ${co['registeredOffice']}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('GSTIN: ${co['gstin'] ?? ''}   FSSAI: ${co['fssai'] ?? ''}', style: const pw.TextStyle(fontSize: fs)),
            if ('${co['phone'] ?? ''}'.isNotEmpty) pw.Text('Phone: ${co['phone']}', style: const pw.TextStyle(fontSize: fs)),
          ]),
        ),
      ]),
      pw.Divider(),
      pw.Center(child: pw.Text('TAX INVOICE', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      if ('${inv['irn'] ?? ''}'.isNotEmpty) pw.Text('IRN: ${inv['irn']}   Date: ${inv['irnDate'] ?? ''}', style: const pw.TextStyle(fontSize: 8)),
      if ('${inv['ewayBillNo'] ?? ''}'.isNotEmpty) pw.Text('E-way bill: ${inv['ewayBillNo']}   Valid up to: ${inv['ewayValidUpto'] ?? ''}', style: const pw.TextStyle(fontSize: 8)),
      pw.SizedBox(height: 6),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Bill to:', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
            pw.Text('${inv['customerName']}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('${inv['customerAddress'] ?? ''}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('GSTIN: ${('${inv['customerGstin'] ?? ''}').isEmpty ? 'Unregistered' : inv['customerGstin']}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('Place of supply: ${inv['customerState'] ?? ''}', style: const pw.TextStyle(fontSize: fs)),
          ]),
        ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Invoice no: ${inv['invoiceNo']}', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
            pw.Text('Date: ${inv['date']}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('Vehicle: ${inv['vehicleNo'] ?? '-'}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('Transporter: ${inv['transporter'] ?? '-'}   LR: ${inv['lrNo'] ?? '-'}', style: const pw.TextStyle(fontSize: fs)),
            pw.Text('Weighment slip: ${inv['slipNo'] ?? '-'}  Net wt: ${kg(inv['netKg'])} KG', style: const pw.TextStyle(fontSize: fs)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(22), 1: const pw.FlexColumnWidth(3), 2: const pw.FixedColumnWidth(48),
          3: const pw.FixedColumnWidth(62), 4: const pw.FixedColumnWidth(55), 5: const pw.FixedColumnWidth(70),
          6: const pw.FixedColumnWidth(40),
        },
        children: rows,
      ),
      pw.SizedBox(height: 8),
      totalRow('Taxable value', n(inv['taxable']).toStringAsFixed(2)),
      if (!inter) totalRow('CGST', n(inv['cgst']).toStringAsFixed(2)),
      if (!inter) totalRow('SGST', n(inv['sgst']).toStringAsFixed(2)),
      if (inter) totalRow('IGST', n(inv['igst']).toStringAsFixed(2)),
      totalRow('Round off', n(inv['roundOff']).toStringAsFixed(2)),
      totalRow('Grand total', 'Rs. ${n(inv['grandTotal']).toStringAsFixed(2)}', bold: true),
      pw.SizedBox(height: 6),
      pw.Text('Amount in words: Rupees ${inWords(n(inv['grandTotal']).round())} Only',
          style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      if ('${co['bankDetails'] ?? ''}'.isNotEmpty) pw.Text('Bank details: ${co['bankDetails']}', style: const pw.TextStyle(fontSize: fs)),
      pw.Text('${co['invoiceTerms'] ?? ''}', style: const pw.TextStyle(fontSize: 8)),
      pw.SizedBox(height: 30),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('For ${co['companyName'] ?? ''}\n\n\nAuthorised signatory', style: const pw.TextStyle(fontSize: fs)),
      ),
    ],
  ));
  return doc.save();
}
