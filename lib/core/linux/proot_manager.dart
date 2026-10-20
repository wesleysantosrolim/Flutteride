import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PRootManager {
  static const MethodChannel _platform =
      MethodChannel('com.flutteride.flutteride/native_path');

  Future<String?> _getNativeLibDir() async {
    try {
      final String? dir = await _platform.invokeMethod<String>(
        'getNativeLibDir',
      );

      return dir;
    } catch (e) {
      debugPrint('Aviso ao obter nativeLibDir: $e');
      return null;
    }
  }

  Future<File> get getPRootFile async {
    final appDir = await getApplicationSupportDirectory();

    final binDir = Directory(
      p.join(appDir.path, 'bin'),
    );

    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }

    return File(
      p.join(binDir.path, 'proot'),
    );
  }

  /// Verifica se existe um PRoot válido.
  ///
  /// O caminho principal é o libproot.so nativo empacotado
  /// no APK. O arquivo em ApplicationSupport/bin/proot
  /// permanece apenas como fallback.
  Future<bool> isAvailable() async {
    try {
      final nativeDir = await _getNativeLibDir();

      if (nativeDir != null) {
        final nativeProot = File(
          p.join(nativeDir, 'libproot.so'),
        );

        if (await nativeProot.exists()) {
          final size = await nativeProot.length();

          if (size > 50000) {
            return true;
          }

          debugPrint(
            'libproot.so nativo encontrado, porém inválido: '
            '$size bytes.',
          );
        }
      }

      final prootFile = await getPRootFile;

      if (await prootFile.exists()) {
        final size = await prootFile.length();

        if (size > 50000) {
          return true;
        }

        debugPrint(
          'PRoot fallback inválido: $size bytes.',
        );
      }

      return false;
    } catch (e) {
      debugPrint(
        'Erro ao verificar disponibilidade do PRoot: $e',
      );

      return false;
    }
  }

  Future<bool> ensureInstalled({
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      final nativeDir = await _getNativeLibDir();

      /*
       * O projeto atual utiliza o PRoot nativo empacotado
       * em android/app/src/main/jniLibs/arm64-v8a/.
       *
       * O Android disponibiliza o diretório dessas bibliotecas
       * através de applicationInfo.nativeLibraryDir.
       */
      if (nativeDir != null) {
        final nativeProot = File(
          p.join(nativeDir, 'libproot.so'),
        );

        if (await nativeProot.exists()) {
          final size = await nativeProot.length();

          if (size > 50000) {
            debugPrint(
              'PRoot nativo encontrado com sucesso em: '
              '${nativeProot.path} ($size bytes)',
            );

            try {
              await Process.run(
                'chmod',
                [
                  '755',
                  nativeProot.path,
                ],
              );
            } catch (_) {}

            onProgress?.call(1.0);

            return true;
          }

          debugPrint(
            'libproot.so encontrado, porém o arquivo é muito pequeno: '
            '$size bytes.',
          );
        } else {
          debugPrint(
            'libproot.so não encontrado em: ${nativeProot.path}',
          );
        }
      }

      /*
       * Fallback legado.
       *
       * Mantemos a possibilidade de existir um executável PRoot
       * em ApplicationSupport/bin/proot, mas não dependemos dele.
       *
       * O antigo assets/bin/proot estava inválido (404: Not Found),
       * portanto não tentamos carregá-lo automaticamente.
       */
      final prootFile = await getPRootFile;

      if (await prootFile.exists()) {
        final size = await prootFile.length();

        if (size > 50000) {
          try {
            await Process.run(
              'chmod',
              [
                '755',
                prootFile.path,
              ],
            );
          } catch (_) {}

          debugPrint(
            'PRoot fallback encontrado em: '
            '${prootFile.path} ($size bytes)',
          );

          onProgress?.call(1.0);

          return true;
        }

        debugPrint(
          'PRoot fallback inválido: $size bytes.',
        );
      }

      throw Exception(
        'PRoot não encontrado.\n'
        'O libproot.so nativo não foi localizado no APK '
        'e nenhum PRoot fallback válido foi encontrado.',
      );
    } catch (e, stackTrace) {
      debugPrint(
        'Erro detalhado PRootManager: '
        '$e\n$stackTrace',
      );

      throw Exception(
        'Falha no PRoot: $e',
      );
    }
  }
}