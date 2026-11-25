import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  static Future<String?> caminhoLogo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, 'logo.png'));
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null; // ambiente sem plugin (testes)
    }
  }

  /// Gera os bytes do backup criptografado da base atual.
  static Future<Uint8List> gerar({required AppDb app, required String senha}) async {
    if (senha.length < 4) throw RegraException('Use uma senha com pelo menos 4 caracteres');
    // Garante que tudo foi gravado no arquivo principal antes da cópia.
    try {
      await app.db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final dbBytes = await File(app.path).readAsBytes();
    final arquivos = <String, List<int>>{'banco.db': dbBytes};
    final logo = await caminhoLogo();
    if (logo != null) arquivos['logo.png'] = await File(logo).readAsBytes();
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
    final caminho = atual.path;
    final docs = await getApplicationDocumentsDirectory();
    final temp = File('$caminho.restaurando');
    final copia = File('$caminho.anterior');
    final logoPath = p.join(docs.path, 'logo.png');
    final logoAnterior = File('$logoPath.anterior');

    await temp.writeAsBytes(arquivos['banco.db']!, flush: true);
    // Testa abrir o banco restaurado (inclui migrações) antes de substituir.
    final teste = await AppDb.abrir(caminho: temp.path);
    final cfg = await teste.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='config'");
    await teste.fechar();
    if (cfg.isEmpty) {
      await temp.delete();
      throw RegraException('O arquivo restaurado não contém uma base válida.');
    }

    await atual.fechar();
    try {
      if (await copia.exists()) await copia.delete();
      await File(caminho).copy(copia.path);
      for (final suf in ['-wal', '-shm', '-journal']) {
        final f = File('$caminho$suf');
        if (await f.exists()) await f.delete();
      }
      await temp.copy(caminho);
      await temp.delete();
      if (await File(logoPath).exists()) await File(logoPath).copy(logoAnterior.path);
      if (arquivos.containsKey('logo.png')) {
        await File(logoPath).writeAsBytes(arquivos['logo.png']!, flush: true);
      } else if (await File(logoPath).exists()) {
        await File(logoPath).delete();
      }
      final novo = await AppDb.abrir(caminho: caminho);
      if (await copia.exists()) await copia.delete();
      if (await logoAnterior.exists()) await logoAnterior.delete();
      return novo;
    } catch (e) {
      // Recupera a base anterior.
      if (await copia.exists()) {
        await copia.copy(caminho);
      }
      if (await logoAnterior.exists()) await logoAnterior.copy(logoPath);
      await AppDb.abrir(caminho: caminho);
      rethrow;
    }
  }
}
