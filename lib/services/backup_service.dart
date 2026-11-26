import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import '../core/armazenamento.dart';

import '../data/db.dart';

/// Backup protegido por senha (AES-256-GCM, chave derivada por PBKDF2-SHA256).
///
/// Formato do arquivo (.gsvbak):
///   "GPVBAK1\n" + cabeçalho JSON (1 linha) + "\n" + nonce(12) + texto cifrado + MAC(16)
/// O conteúdo cifrado é um ZIP com: banco.db, logo (opcional) e manifesto.json
/// (versão do esquema e SHA-256 de cada arquivo para validação de integridade).
class BackupService {
  static const _magic = 'GPVBAK1\n';
  static const _iteracoes = 120000;

  static Future<SecretKey> _chave(String senha, List<int> sal) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iteracoes, bits: 256);
    return kdf.deriveKey(secretKey: SecretKey(utf8.encode(senha)), nonce: sal);
  }

  static Future<String> _sha256(List<int> dados) async {
    final h = await Sha256().hash(dados);
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Gera os bytes do backup criptografado da base atual.
  static Future<Uint8List> gerar({required AppDb app, required String senha}) async {
    if (senha.length < 4) throw RegraException('Use uma senha com pelo menos 4 caracteres');
    // Garante que tudo foi gravado no arquivo principal antes da cópia.
    try {
      await app.db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final dbBytes = await app.factory.readDatabaseBytes(app.path);
    final arquivos = <String, List<int>>{'banco.db': dbBytes};
    final logo = await Armazenamento.ler('logo.png');
    if (logo != null) arquivos['logo.png'] = logo;
    final manifesto = {
      'app': 'gestor_servicos',
      'versao_esquema': AppDb.versaoEsquema,
      'gerado_em': DateTime.now().toIso8601String(),
      'arquivos': {for (final e in arquivos.entries) e.key: await _sha256(e.value)},
    };
    final zip = Archive();
    for (final e in arquivos.entries) {
      zip.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    final mj = utf8.encode(jsonEncode(manifesto));
    zip.addFile(ArchiveFile('manifesto.json', mj.length, mj));
    final zipBytes = ZipEncoder().encode(zip)!;

    final sal = SecretKeyData.random(length: 16).bytes;
    final aes = AesGcm.with256bits();
    final nonce = aes.newNonce();
    final box = await aes.encrypt(zipBytes, secretKey: await _chave(senha, sal), nonce: nonce);
    final cab = jsonEncode({
      'formato': 1,
      'versao_esquema': AppDb.versaoEsquema,
      'sal': base64Encode(sal),
      'iteracoes': _iteracoes,
    });
    final b = BytesBuilder();
    b.add(utf8.encode(_magic));
    b.add(utf8.encode(cab));
    b.add(utf8.encode('\n'));
    b.add(box.nonce);
    b.add(box.cipherText);
    b.add(box.mac.bytes);
    return b.toBytes();
  }

  /// Valida senha, integridade e versão. Devolve os arquivos do backup.
  static Future<Map<String, List<int>>> abrir(Uint8List bytes, String senha) async {
    final magic = utf8.encode(_magic);
    if (bytes.length < magic.length + 40 ||
        utf8.decode(bytes.sublist(0, magic.length), allowMalformed: true) != _magic) {
      throw RegraException('Arquivo não é um backup do Gestor de Serviços.');
    }
    final fimCab = bytes.indexOf(10, magic.length);
    if (fimCab < 0) throw RegraException('Backup corrompido (cabeçalho).');
    final cab = jsonDecode(utf8.decode(bytes.sublist(magic.length, fimCab))) as Map<String, dynamic>;
    final versao = cab['versao_esquema'] as int;
    if (versao > AppDb.versaoEsquema) {
      throw RegraException('Backup criado por uma versão mais nova do app. Atualize o aplicativo para restaurar.');
    }
    final sal = base64Decode(cab['sal'] as String);
    final iter = (cab['iteracoes'] as int?) ?? _iteracoes;
    final corpo = bytes.sublist(fimCab + 1);
    if (corpo.length < 12 + 16) throw RegraException('Backup corrompido.');
    final nonce = corpo.sublist(0, 12);
    final mac = corpo.sublist(corpo.length - 16);
    final cifrado = corpo.sublist(12, corpo.length - 16);
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256);
    final chave = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(senha)), nonce: sal);
    List<int> zipBytes;
    try {
      zipBytes = await AesGcm.with256bits()
          .decrypt(SecretBox(cifrado, nonce: nonce, mac: Mac(mac)), secretKey: chave);
    } on SecretBoxAuthenticationError {
      throw RegraException('Senha incorreta ou arquivo alterado/corrompido.');
    }
    final zip = ZipDecoder().decodeBytes(zipBytes);
    final arquivos = <String, List<int>>{};
    for (final f in zip.files) {
      if (f.isFile) arquivos[f.name] = f.content as List<int>;
    }
    final mjBytes = arquivos['manifesto.json'];
    if (mjBytes == null || !arquivos.containsKey('banco.db')) {
      throw RegraException('Backup incompleto.');
    }
    final man = jsonDecode(utf8.decode(mjBytes)) as Map<String, dynamic>;
    final hashes = (man['arquivos'] as Map).cast<String, String>();
    for (final e in hashes.entries) {
      final dados = arquivos[e.key];
      if (dados == null || await _sha256(dados) != e.value) {
        throw RegraException('Falha na verificação de integridade (${e.key}).');
      }
    }
    return arquivos;
  }

  /// Restaura substituindo a base atual. Se algo falhar, a base anterior é mantida.
  static Future<AppDb> restaurar({
    required AppDb atual,
    required Map<String, List<int>> arquivos,
  }) async {
    final f = atual.factory;
    final caminho = atual.path;
    final temp = '$caminho.restaurando';
    final novosBytes = Uint8List.fromList(arquivos['banco.db']!);

    await f.writeDatabaseBytes(temp, novosBytes);
    // Testa abrir o banco restaurado (inclui migrações) antes de substituir.
    final teste = await AppDb.abrir(caminho: temp, factory: f);
    final cfg = await teste.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='config'");
    await teste.fechar();
    if (cfg.isEmpty) {
      await f.deleteDatabase(temp);
      throw RegraException('O arquivo restaurado não contém uma base válida.');
    }
    final restaurado = await f.readDatabaseBytes(temp);
    await f.deleteDatabase(temp);

    final copia = await atual.factory.readDatabaseBytes(caminho);
    final logoAnterior = await Armazenamento.ler('logo.png');
    await atual.fechar();
    try {
      await f.deleteDatabase(caminho);
      await f.writeDatabaseBytes(caminho, restaurado);
      final logo = arquivos['logo.png'];
      await Armazenamento.gravar('logo.png', logo == null ? null : Uint8List.fromList(logo));
      return await AppDb.abrir(caminho: caminho, factory: f);
    } catch (e) {
      // Recupera a base anterior.
      await f.deleteDatabase(caminho);
      await f.writeDatabaseBytes(caminho, copia);
      await Armazenamento.gravar('logo.png', logoAnterior);
      await AppDb.abrir(caminho: caminho, factory: f);
      rethrow;
    }
  }
}
