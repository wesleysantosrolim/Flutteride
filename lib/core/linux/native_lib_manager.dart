import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NativeLibManager {
  static const List<String> _sharedLibs = [
    'libproot_loader.so',
    'libtalloc.so.2',
    'libandroid-shmem.so',
  ];

  static Future<Map<String, String>> prepareNativeEnvironment() async {
    final appSupportDir =
        await getApplicationSupportDirectory();

    final targetLibDir = Directory(
      p.join(
        appSupportDir.path,
        'usr',
        'lib',
      ),
    );

    if (!await targetLibDir.exists()) {
      await targetLibDir.create(
        recursive: true,
      );
    }

    for (final libName in _sharedLibs) {
      final targetFile = File(
        p.join(
          targetLibDir.path,
          libName,
        ),
      );

      if (!await targetFile.exists()) {
        try {
          final byteData = await rootBundle.load(
            'assets/native_libs/$libName',
          );

          final bytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );

          await targetFile.writeAsBytes(
            bytes,
            flush: true,
          );
        } catch (e) {
          debugPrint(
            'Erro ao carregar asset '
            'assets/native_libs/$libName: $e',
          );
        }
      }
    }

    final codeCacheDir = Directory(
      p.join(
        appSupportDir.parent.path,
        'code_cache',
      ),
    );

    if (!await codeCacheDir.exists()) {
      await codeCacheDir.create(
        recursive: true,
      );
    }

    final prootExecutable = File(
      p.join(
        codeCacheDir.path,
        'libproot.so',
      ),
    );

    if (!await prootExecutable.exists()) {
      try {
        final byteData = await rootBundle.load(
          'assets/native_libs/libproot.so',
        );

        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );

        await prootExecutable.writeAsBytes(
          bytes,
          flush: true,
        );
      } catch (e) {
        debugPrint(
          'Erro ao extrair libproot.so dos assets: $e',
        );
      }
    }

    if (await prootExecutable.exists()) {
      await Process.run(
        'chmod',
        [
          '755',
          prootExecutable.path,
        ],
      );
    } else {
      throw Exception(
        'Binário libproot.so não foi encontrado '
        'em assets/native_libs/\n'
        'Certifique-se de ter adicionado os arquivos '
        'na pasta assets/native_libs/ e rodado flutter pub get.',
      );
    }

    return {
      'prootPath': prootExecutable.path,
      'libDir': targetLibDir.path,
    };
  }
}