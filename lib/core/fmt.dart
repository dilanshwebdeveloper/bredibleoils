import 'package:intl/intl.dart';

String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
double n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
double r2(double v) => (v * 100).roundToDouble() / 100;
String kg(dynamic v) => NumberFormat('#,##0.##', 'en_IN').format(n(v));
String money(dynamic v) => 'Rs. ${NumberFormat('#,##0.00', 'en_IN').format(n(v))}';

/// Indian financial year, e.g. "2026-27"
String fy([DateTime? d]) {
  d ??= DateTime.now();
  final y = d.month >= 4 ? d.year : d.year - 1;
  return '$y-${((y + 1) % 100).toString().padLeft(2, '0')}';
}

String inWords(int x) {
  if (x == 0) return 'Zero';
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven',
    'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String b100(int v) => v < 20 ? ones[v] : tens[v ~/ 10] + (v % 10 == 0 ? '' : ' ${ones[v % 10]}');
  String b1000(int v) =>
      v < 100 ? b100(v) : '${ones[v ~/ 100]} Hundred${v % 100 == 0 ? '' : ' ${b100(v % 100)}'}';
  final parts = <String>[];
  final cr = x ~/ 10000000; x %= 10000000;
  final lk = x ~/ 100000; x %= 100000;
  final th = x ~/ 1000; x %= 1000;
  if (cr > 0) parts.add('${b1000(cr)} Crore');
  if (lk > 0) parts.add('${b100(lk)} Lakh');
  if (th > 0) parts.add('${b100(th)} Thousand');
  if (x > 0) parts.add(b1000(x));
  return parts.join(' ');
}

/// GST state codes. Customer state is stored as "08 - Rajasthan".
const indianStates = [
  '01 - Jammu & Kashmir', '02 - Himachal Pradesh', '03 - Punjab', '04 - Chandigarh', '05 - Uttarakhand',
  '06 - Haryana', '07 - Delhi', '08 - Rajasthan', '09 - Uttar Pradesh', '10 - Bihar', '11 - Sikkim',
  '12 - Arunachal Pradesh', '13 - Nagaland', '14 - Manipur', '15 - Mizoram', '16 - Tripura', '17 - Meghalaya',
  '18 - Assam', '19 - West Bengal', '20 - Jharkhand', '21 - Odisha', '22 - Chhattisgarh', '23 - Madhya Pradesh',
  '24 - Gujarat', '26 - Dadra & Nagar Haveli and Daman & Diu', '27 - Maharashtra', '29 - Karnataka', '30 - Goa',
  '31 - Lakshadweep', '32 - Kerala', '33 - Tamil Nadu', '34 - Puducherry', '35 - Andaman & Nicobar Islands',
  '36 - Telangana', '37 - Andhra Pradesh', '38 - Ladakh',
];
