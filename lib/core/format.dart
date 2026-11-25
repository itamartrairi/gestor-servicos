import 'package:intl/intl.dart';

/// Formatação padrão pt-BR: R$, DD/MM/AAAA e horário local.
final NumberFormat _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final NumberFormat _num = NumberFormat.decimalPattern('pt_BR');
final DateFormat _data = DateFormat('dd/MM/yyyy');
final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat _iso = DateFormat('yyyy-MM-dd');

String brl(num? v) => _brl.format(v ?? 0);

String numero(num? v, {int casas = 3}) {
  final f = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: casas);
  var s = f.format(v ?? 0);
  if (s.contains(',')) {
    s = s.replaceFirst(RegExp(r',?0+$'), '');
  }
  return s;
}

String pct(num? v) {
  final d = double.parse((v ?? 0).toStringAsFixed(2));
  return '${_num.format(d == 0 ? 0 : d)}%';
}

/// Data armazenada no banco sempre como yyyy-MM-dd (texto ISO).
String isoData(DateTime d) => _iso.format(d);

String hojeIso() => isoData(DateTime.now());

String agoraIso() => DateTime.now().toIso8601String();

DateTime parseIso(String s) => DateTime.parse(s);

String dataBr(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return _data.format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

String dataHoraBr(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    return _dataHora.format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

String dataBrDe(DateTime d) => _data.format(d);

/// Aceita "1.234,56", "1234,56" ou "1234.56".
double parseNum(String? s) {
  if (s == null) return 0;
  var t = s.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (t.isEmpty) return 0;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(t) ?? 0;
}

/// Arredonda valores monetários em 2 casas.
double r2(num v) => (v * 100).roundToDouble() / 100;

/// Arredonda custos unitários em 6 casas para preservar precisão.
double r6(num v) => (v * 1000000).roundToDouble() / 1000000;

String mesAno(DateTime d) => DateFormat('MM/yyyy').format(d);

String nomeMes(DateTime d) {
  const meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];
  return '${meses[d.month - 1]}/${d.year}';
}

DateTime inicioMes(DateTime d) => DateTime(d.year, d.month, 1);
DateTime fimMes(DateTime d) => DateTime(d.year, d.month + 1, 0);
