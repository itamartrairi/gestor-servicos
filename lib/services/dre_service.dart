import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'base.dart';

class Dre {
  Dre(this.inicio, this.fim, this.grupos);
  final String inicio, fim;
  final Map<String, double> grupos;

  double g(String k) => grupos[k] ?? 0;
  double get receitaBruta => g('receita_bruta');
  double get deducoes => r2(g('desconto') + g('devolucao') + g('imposto_venda'));
  double get receitaLiquida => r2(receitaBruta - deducoes);
  double get cpv => g('cpv');
  double get lucroBruto => r2(receitaLiquida - cpv);
  double get despesasVariaveis => g('despesa_variavel');
  double get despesasFixas => g('despesa_fixa');
  double get despesasOperacionais => r2(despesasVariaveis + despesasFixas);
  double get resultadoOperacional => r2(lucroBruto - despesasOperacionais);
  double get resultadoFinanceiro => r2(g('receita_financeira') - g('despesa_financeira'));
  double get resultadoLiquido => r2(resultadoOperacional + resultadoFinanceiro);

  /// Linhas na ordem de apresentação: (rótulo, valor, grupos para abrir, destaque).
  List<(String, double, List<String>, bool)> linhas() => [
        ('Receita bruta', receitaBruta, ['receita_bruta'], true),
        ('(-) Descontos', -g('desconto'), ['desconto'], false),
        ('(-) Devoluções', -g('devolucao'), ['devolucao'], false),
        ('(-) Impostos sobre vendas', -g('imposto_venda'), ['imposto_venda'], false),
        ('Receita líquida', receitaLiquida, [], true),
        ('(-) Custo dos produtos vendidos (CPV)', -cpv, ['cpv'], false),
        ('Lucro bruto', lucroBruto, [], true),
        ('(-) Despesas operacionais variáveis', -despesasVariaveis, ['despesa_variavel'], false),
        ('(-) Despesas operacionais fixas', -despesasFixas, ['despesa_fixa'], false),
        ('Resultado operacional', resultadoOperacional, [], true),
        ('(+) Receitas financeiras', g('receita_financeira'), ['receita_financeira'], false),
        ('(-) Despesas financeiras', -g('despesa_financeira'), ['despesa_financeira'], false),
        ('Resultado financeiro', resultadoFinanceiro, [], true),
        ('Resultado líquido', resultadoLiquido, [], true),
      ];
}

/// DRE gerencial por competência, a partir dos lançamentos de resultado.
class DreService {
  DreService(this.db);
  final Database db;

  Future<Dre> calcular(String inicio, String fim) async {
    final r = await db.rawQuery('''
      SELECT grupo, SUM(valor) v FROM lancamentos_resultado
      WHERE data >= ? AND data <= ? GROUP BY grupo''', [inicio, fim]);
    return Dre(inicio, fim, {for (final x in r) x['grupo'] as String: r2(Base.d(x['v']))});
  }

  Future<List<Map<String, Object?>>> lancamentos(String inicio, String fim, List<String> grupos) {
    return db.rawQuery('''
      SELECT * FROM lancamentos_resultado
      WHERE data >= ? AND data <= ? AND grupo IN (${List.filled(grupos.length, '?').join(',')})
      ORDER BY data, id''', [inicio, fim, ...grupos]);
  }
}
