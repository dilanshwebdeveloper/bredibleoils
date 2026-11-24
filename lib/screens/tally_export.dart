import '../core/db.dart';
import '../core/fmt.dart';

/// Ledger names used in the XML. Create ledgers with these exact names in TallyPrime
/// (or edit them here) before importing.
const tallySalesLedger = 'Sales';
const tallyPurchaseLedger = 'Purchase';
const tallyCgst = 'CGST';
const tallySgst = 'SGST';
const tallyIgst = 'IGST';
const tallyRound = 'Round Off';

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
String _d(dynamic s) => '$s'.replaceAll('-', '');
String _a(double v) => v.toStringAsFixed(2);

String _entry(String ledger, double amount, {bool party = false}) {
  // Tally: debit = negative amount (deemed positive Yes), credit = positive amount.
  final debit = amount < 0;
  return '<ALLLEDGERENTRIES.LIST><LEDGERNAME>${_x(ledger)}</LEDGERNAME>'
      '<ISDEEMEDPOSITIVE>${debit ? 'Yes' : 'No'}</ISDEEMEDPOSITIVE>'
      '${party ? '<ISPARTYLEDGER>Yes</ISPARTYLEDGER>' : ''}<AMOUNT>${_a(amount)}</AMOUNT></ALLLEDGERENTRIES.LIST>';
}

/// Sales and purchase vouchers between two dates (yyyy-MM-dd) in TallyPrime import XML.
Future<String> buildTallyXml(String from, String to) async {
  Future<List<Map<String, dynamic>>> q(String c) async {
    final s = await Db.c(c).where('date', isGreaterThanOrEqualTo: from).where('date', isLessThanOrEqualTo: to).get();
    return s.docs.map((d) => d.data()).where((e) => e['status'] != 'Voided').toList();
  }

  final co = (await Db.c('settings').doc('company').get()).data() ?? {};
  final sb = StringBuffer();
  for (final i in await q('invoices')) {
    if (i['status'] == 'Cancelled') continue;
    final party = '${i['customerName']}';
    sb.write('<TALLYMESSAGE xmlns:UDF="TallyUDF"><VOUCHER VCHTYPE="Sales" ACTION="Create" OBJVIEW="Accounting Voucher View">'
        '<DATE>${_d(i['date'])}</DATE><VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>'
        '<VOUCHERNUMBER>${_x('${i['invoiceNo']}')}</VOUCHERNUMBER><PARTYLEDGERNAME>${_x(party)}</PARTYLEDGERNAME>'
        '<NARRATION>${_x('Vehicle ${i['vehicleNo'] ?? ''}')}</NARRATION>');
    sb.write(_entry(party, -n(i['grandTotal']), party: true));
    sb.write(_entry(tallySalesLedger, n(i['taxable'])));
    if (n(i['cgst']) != 0) sb.write(_entry(tallyCgst, n(i['cgst'])));
    if (n(i['sgst']) != 0) sb.write(_entry(tallySgst, n(i['sgst'])));
    if (n(i['igst']) != 0) sb.write(_entry(tallyIgst, n(i['igst'])));
    if (n(i['roundOff']) != 0) sb.write(_entry(tallyRound, n(i['roundOff'])));
    sb.write('</VOUCHER></TALLYMESSAGE>');
  }
  for (final p in [...await q('purchases'), ...await q('docPurchases')]) {
    final party = '${p['supplierName']}';
    sb.write('<TALLYMESSAGE xmlns:UDF="TallyUDF"><VOUCHER VCHTYPE="Purchase" ACTION="Create" OBJVIEW="Accounting Voucher View">'
        '<DATE>${_d(p['date'])}</DATE><VOUCHERTYPENAME>Purchase</VOUCHERTYPENAME>'
        '<VOUCHERNUMBER>${_x('${p['billNo'] ?? ''}'.isEmpty ? 'PUR-${_d(p['date'])}' : '${p['billNo']}')}</VOUCHERNUMBER>'
        '<PARTYLEDGERNAME>${_x(party)}</PARTYLEDGERNAME>');
    sb.write(_entry(party, n(p['amount']), party: true));
    sb.write(_entry(tallyPurchaseLedger, -n(p['amount'])));
    sb.write('</VOUCHER></TALLYMESSAGE>');
  }
  return '<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA>'
      '<REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${_x('${co['companyName'] ?? ''}')}</SVCURRENTCOMPANY>'
      '</STATICVARIABLES></REQUESTDESC><REQUESTDATA>$sb</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>';
}
