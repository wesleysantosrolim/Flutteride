import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'proot_manager.dart';

enum LinuxSetupStatus {
  notInstalled,
  downloadingPRoot,
  extractingAsset,
  extractingRootfs,
  configuringPermissions,
  ready,
  error,
}

class LinuxEnvironmentService {
  final PRootManager _prootManager = PRootManager();

  static const String _assetRootfsPath =
      'assets/linux/ubuntu-base-arm64.tar.gz';

  Future<Directory> get _rootfsDir async {
    final appDir =
        await getApplicationSupportDirectory();

    return Directory(
      p.join(
        appDir.path,
        'ubuntu_rootfs',
      ),
    );
  }

  Future<File> get _tarArchiveFile async {
    final appDir =
        await getTemporaryDirectory();

    return File(
      p.join(
        appDir.path,
        'ubuntu-base-arm64.tar.gz',
      ),
    );
  }

  Future<bool> isInstalled() async {
    try {
      final dir = await _rootfsDir;

      final bashFile = File(
        p.join(
          dir.path,
          'bin',
          'bash',
        ),
      );

      final usrBashFile = File(
        p.join(
          dir.path,
          'usr',
          'bin',
          'bash',
        ),
      );

      final hasBash =
          await bashFile.exists() ||
          await usrBashFile.exists();

      final hasPRoot =
          await _prootManager.isAvailable();

      return await dir.exists() &&
          hasBash &&
          hasPRoot;
    } catch (e) {
      debugPrint(
        'Erro ao verificar instalação: $e',
      );

      return false;
    }
  }

  Future<void> _copyAssetToTemp(
    String assetPath,
    File targetFile,
  ) async {
    final byteData =
        await rootBundle.load(assetPath);

    final buffer = byteData.buffer;

    await targetFile.writeAsBytes(
      buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      flush: true,
    );
  }

  Future<void> _prepareTmpDirectory(
    String rootfsPath,
  ) async {
    final tmpDir = Directory(
      p.join(
        rootfsPath,
        'tmp',
      ),
    );

    if (!await tmpDir.exists()) {
      await tmpDir.create(
        recursive: true,
      );
    }

    try {
      await Process.run(
        'chmod',
        [
          '1777',
          tmpDir.path,
        ],
      );
    } catch (e) {
      debugPrint(
        'Aviso de permissão em /tmp: $e',
      );
    }
  }

  Stream<Map<String, dynamic>> setupEnvironment() async* {
    try {
      yield {
        'status':
            LinuxSetupStatus.downloadingPRoot,
        'progress': 0.05,
        'message':
            'Obtendo e preparando executor nativo PRoot...',
      };

      final prootOk =
          await _prootManager.ensureInstalled();

      if (!prootOk) {
        throw Exception(
          'Falha ao configurar o binário PRoot.',
        );
      }

      final prootFile =
          await _prootManager.getPRootFile;

      if (await prootFile.exists()) {
        await Process.run(
          'chmod',
          [
            '+x',
            prootFile.path,
          ],
        );
      }

      final rootfsDirectory =
          await _rootfsDir;

      final archiveFile =
          await _tarArchiveFile;

      yield {
        'status':
            LinuxSetupStatus.extractingAsset,
        'progress': 0.15,
        'message':
            'Carregando Ubuntu 22.04 dos assets locais...',
      };

      await _copyAssetToTemp(
        _assetRootfsPath,
        archiveFile,
      );

      yield {
        'status':
            LinuxSetupStatus.extractingRootfs,
        'progress': 0.50,
        'message':
            'Descompactando arquivos do sistema '
            '(pode demorar)...',
      };

      if (!await rootfsDirectory.exists()) {
        await rootfsDirectory.create(
          recursive: true,
        );
      }

      await _extractTarGz(
        archiveFile.path,
        rootfsDirectory.path,
      );

      yield {
        'status':
            LinuxSetupStatus.configuringPermissions,
        'progress': 0.85,
        'message':
            'Ajustando permissões do sistema...',
      };

      final bashBinPath =
          p.join(
            rootfsDirectory.path,
            'bin',
          );

      final usrBinPath =
          p.join(
            rootfsDirectory.path,
            'usr',
            'bin',
          );

      if (await Directory(bashBinPath).exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            '755',
            bashBinPath,
          ],
        );
      }

      if (await Directory(usrBinPath).exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            '755',
            usrBinPath,
          ],
        );
      }

      yield {
        'status':
            LinuxSetupStatus.configuringPermissions,
        'progress': 0.95,
        'message':
            'Configurando DNS e diretórios de sistema...',
      };

      await _configureDnsDirectly(
        rootfsDirectory.path,
      );

      await _prepareTmpDirectory(
        rootfsDirectory.path,
      );

      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }

      yield {
        'status':
            LinuxSetupStatus.ready,
        'progress': 1.0,
        'message':
            'Ambiente Linux preparado com sucesso!',
      };
    } catch (e) {
      debugPrint(
        'Erro no setupEnvironment: $e',
      );

      yield {
        'status':
            LinuxSetupStatus.error,
        'progress': 0.0,
        'message':
            'Erro no processo de setup:\n$e',
      };
    }
  }

  Future<void> _configureDnsDirectly(
    String rootfsPath,
  ) async {
    final etcDir = Directory(
      p.join(
        rootfsPath,
        'etc',
      ),
    );

    if (!await etcDir.exists()) {
      await etcDir.create(
        recursive: true,
      );
    }

    final resolvConfFile = File(
      p.join(
        etcDir.path,
        'resolv.conf',
      ),
    );

    const dnsContent =
        'nameserver 8.8.8.8\n'
        'nameserver 1.1.1.1\n';

    await resolvConfFile.writeAsString(
      dnsContent,
    );
  }

  Future<void> _extractTarGz(
    String archivePath,
    String outputPath,
  ) async {
    final result = await Process.run(
      'tar',
      [
        '-xzf',
        archivePath,
        '-C',
        outputPath,
      ],
    );

    final bashBin = File(
      p.join(
        outputPath,
        'bin',
        'bash',
      ),
    );

    final usrBashBin = File(
      p.join(
        outputPath,
        'usr',
        'bin',
        'bash',
      ),
    );

    final isExtracted =
        await bashBin.exists() ||
        await usrBashBin.exists();

    if (!isExtracted) {
      throw Exception(
        'Falha ao extrair a Rootfs do Ubuntu: '
        '${result.stderr}',
      );
    }
  }
}