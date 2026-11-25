import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';

/// Utilidades compartilhadas pelos serviços.
class Base {
  Base(this.db);
  final Database db;

  static const double eps = 0.000001;

  static bool ehInsumo(String tipo) => tipo == 'insumo' || tipo == 'embalagem';

  /// Serviços não têm estoque (não reservam nem dão baixa).
  static bool ehServico(String tipo) => tipo == 'servico';

  static double d(Object? v) => v == null ? 0 : (v as num).toDouble();
  static int i(Object? v) => v == null ? 0 : (v as num).toInt();

  Future<String?> config(String chave, {DatabaseExecutor? ex}) async {
    final r = await (ex ?? db).query('config', where: 'chave = ?', whereArgs: [chave]);
    return r.isEmpty ? null : r.first['valor'] as String?;
  }

  Future<void> setConfig(String chave, String? valor, {DatabaseExecutor? ex}) async {
    await (ex ?? db).insert('config', {'chave': chave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> categoriaFin(DatabaseExecutor ex, String codigo) async {
    final r = await ex.query('categorias_financeiras',
        columns: ['id'], where: 'codigo = ?', whereArgs: [codigo]);
    if (r.isEmpty) throw RegraException('Categoria financeira $codigo não encontrada');
    return r.first['id'] as int;
  }

  static Future<Map<String, Object?>> categoriaFinPorId(DatabaseExecutor ex, int id) async {
    final r = await ex.query('categorias_financeiras', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw RegraException('Categoria financeira não encontrada');
    return r.first;
  }

  static Future<Map<String, Object?>> item(DatabaseExecutor ex, int id) async {
    final r = await ex.query('itens', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw RegraException('Item $id não encontrado');
    return r.first;
  }

  static Future<String> nomeItem(DatabaseExecutor ex, int itemId, int variacaoId) async {
    final it = await item(ex, itemId);
    var nome = it['nome'] as String;
    if (variacaoId != 0) {
      final v = await ex.query('variacoes', where: 'id = ?', whereArgs: [variacaoId]);
      if (v.isNotEmpty) nome = '$nome - ${v.first['nome']}';
    }
    return nome;
  }

  static Future<void> auditar(DatabaseExecutor ex, String acao,
      {String? entidade, int? entidadeId, String? motivo, String? detalhes}) async {
    await ex.insert('auditoria', {
      'data_hora': agoraIso(),
      'acao': acao,
      'entidade': entidade,
      'entidade_id': entidadeId,
      'motivo': motivo,
      'detalhes': detalhes,
    });
  }

  /// Lança um valor na DRE (competência). [chave] impede lançamentos duplicados.
  static Future<void> lancarResultado(
    DatabaseExecutor ex, {
    required String data,
    required String grupo,
    required String descricao,
    required double valor,
    int? categoriaId,
    String? refTipo,
    int? refId,
    int? itemId,
    int? variacaoId,
    double? quantidade,
    String? canal,
    bool variavel = true,
    String? chave,
  }) async {
    if (valor.abs() < 0.005 && quantidade == null) return;
    await ex.insert('lancamentos_resultado', {
      'data': data,
      'grupo': grupo,
      'descricao': descricao,
      'valor': r2(valor),
      'categoria_id': categoriaId,
      'ref_tipo': refTipo,
      'ref_id': refId,
      'item_id': itemId,
      'variacao_id': variacaoId,
      'quantidade': quantidade,
      'canal': canal,
      'variavel': variavel ? 1 : 0,
      'chave': chave,
      'criado_em': agoraIso(),
    });
  }
}
