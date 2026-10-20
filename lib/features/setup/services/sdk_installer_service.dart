import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/sdk_component.dart';
import '../models/sdk_file.dart';

class SDKInstallProgress {
  final String message;
  final double progress;

  const SDKInstallProgress({
    required this.message,
    required this.progress,
  });
}

class SDKInstallResult {
  final bool success;
  final String message;
  final String? installPath;

  const SDKInstallResult({
    required this.success,
    required this.message,
    this.installPath,
  });
}

class SDKInstallerService {
  SDKInstallerService();

  static const String _stateFileName =
      'installed_sdk_components.json';

  static const String _environmentStartMarker =
      '# >>> FlutterIDE environment >>>';

  static const String _environmentEndMarker =
      '# <<< FlutterIDE environment <<<';

  String? _rootfsPath;

  Future<String> getRootfsPath() async {
    if (_rootfsPath != null) {
      final cached =
          Directory(_rootfsPath!);

      if (await cached.exists()) {
        return _rootfsPath!;
      }

      _rootfsPath = null;
    }

    final appDirectory =
        await getApplicationSupportDirectory();

    final rootfs = Directory(
      '${appDirectory.path}/ubuntu_rootfs',
    );

    if (!await rootfs.exists()) {
      throw Exception(
        'O Ubuntu ainda não está instalado.',
      );
    }

    final bash =
        File('${rootfs.path}/bin/bash');

    final usrBash =
        File('${rootfs.path}/usr/bin/bash');

    if (!await bash.exists() &&
        !await usrBash.exists()) {
      throw Exception(
        'A instalação do Ubuntu está incompleta.',
      );
    }

    _rootfsPath = rootfs.path;

    return _rootfsPath!;
  }

  Future<File> _getStateFile() async {
    final rootfs =
        await getRootfsPath();

    final stateDirectory =
        Directory('$rootfs/.flutteride');

    if (!await stateDirectory.exists()) {
      await stateDirectory.create(
        recursive: true,
      );
    }

    return File(
      '${stateDirectory.path}/$_stateFileName',
    );
  }

  Future<Map<String, dynamic>>
      loadInstallationState() async {
    try {
      final file =
          await _getStateFile();

      if (!await file.exists()) {
        return {};
      }

      final content =
          await file.readAsString();

      if (content.trim().isEmpty) {
        return {};
      }

      final decoded =
          jsonDecode(content);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveInstallationState(
    SDKComponentType type,
    String installPath,
  ) async {
    final file =
        await _getStateFile();

    final state =
        await loadInstallationState();

    state[_typeKey(type)] = {
      'installed': true,
      'path': installPath,
      'installedAt':
          DateTime.now().toIso8601String(),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(state),
      flush: true,
    );
  }

  Future<String?> getInstalledPath(
    SDKComponentType type,
  ) async {
    try {
      final state =
          await loadInstallationState();

      final data =
          state[_typeKey(type)];

      if (data is! Map) {
        return null;
      }

      if (data['installed'] != true) {
        return null;
      }

      final path =
          data['path']?.toString();

      if (path == null ||
          path.isEmpty) {
        return null;
      }

      final physicalPath =
          _toPhysicalPath(path);

      if (!await Directory(
        physicalPath,
      ).exists()) {
        return null;
      }

      return path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isComponentInstalled(
    SDKComponentType type,
  ) async {
    try {
      final path =
          await getInstalledPath(type);

      if (path == null) {
        return false;
      }

      final validation =
          await validateInstallation(
        type,
        path,
      );

      return validation.success;
    } catch (_) {
      return false;
    }
  }

  Future<void> restoreComponentStates(
    List<SDKComponent> components,
  ) async {
    for (final component in components) {
      try {
        final path =
            await getInstalledPath(
          component.type,
        );

        if (path == null) {
          continue;
        }

        final validation =
            await validateInstallation(
          component.type,
          path,
        );

        if (validation.success) {
          component.markInstalled(
            validation.installPath ?? path,
          );
        }
      } catch (_) {}
    }
  }

  String _typeKey(
    SDKComponentType type,
  ) {
    switch (type) {
      case SDKComponentType.flutter:
        return 'flutter';

      case SDKComponentType.java:
        return 'java';

      case SDKComponentType.androidSdk:
        return 'androidSdk';

      case SDKComponentType.buildTools:
        return 'buildTools';

      case SDKComponentType.platformTools:
        return 'platformTools';

      case SDKComponentType.androidPlatform:
        return 'androidPlatform';

      case SDKComponentType.gradle:
        return 'gradle';

      case SDKComponentType.ndk:
        return 'ndk';

      case SDKComponentType.linuxRuntime:
        return 'linuxRuntime';

      case SDKComponentType.unknown:
        return 'unknown';
    }
  }

  Future<String> getInstallPath(
    SDKComponentType type,
  ) async {
    final rootfs =
        await getRootfsPath();

    switch (type) {
      case SDKComponentType.flutter:
        return '$rootfs/opt/flutter';

      case SDKComponentType.java:
        return '$rootfs/opt/java';

      case SDKComponentType.androidSdk:
        return '$rootfs/opt/android_sdk';

      case SDKComponentType.buildTools:
      case SDKComponentType.platformTools:
      case SDKComponentType.androidPlatform:
      case SDKComponentType.gradle:
      case SDKComponentType.ndk:
        throw Exception(
          'Este componente não é instalado '
          'separadamente. Ele faz parte do '
          'Android SDK completo.',
        );

      case SDKComponentType.linuxRuntime:
        return rootfs;

      case SDKComponentType.unknown:
        throw Exception(
          'Componente desconhecido.',
        );
    }
  }

  Future<String> getLogicalInstallPath(
    SDKComponentType type,
  ) async {
    switch (type) {
      case SDKComponentType.flutter:
        return '/opt/flutter';

      case SDKComponentType.java:
        return '/opt/java';

      case SDKComponentType.androidSdk:
        return '/opt/android_sdk';

      case SDKComponentType.buildTools:
      case SDKComponentType.platformTools:
      case SDKComponentType.androidPlatform:
      case SDKComponentType.gradle:
      case SDKComponentType.ndk:
        throw Exception(
          'Este componente não é instalado '
          'separadamente. Ele faz parte do '
          'Android SDK completo.',
        );

      case SDKComponentType.linuxRuntime:
        return '/';

      case SDKComponentType.unknown:
        throw Exception(
          'Componente desconhecido.',
        );
    }
  }

  Stream<SDKInstallProgress> install(
    SDKFile file,
    SDKComponentType type,
  ) async* {
    try {
      yield const SDKInstallProgress(
        message:
            'Preparando instalação...',
        progress: 0.03,
      );

      if (!_isSupportedInstallType(type)) {
        throw Exception(
          'Este componente não é instalado '
          'separadamente.',
        );
      }

      final source =
          File(file.path);

      if (!await source.exists()) {
        throw Exception(
          'O arquivo selecionado não existe mais.',
        );
      }

      final size =
          await source.length();

      if (size <= 0) {
        throw Exception(
          'O arquivo selecionado está vazio.',
        );
      }

      yield SDKInstallProgress(
        message:
            'Arquivo encontrado '
            '(${_formatBytes(size)}).',
        progress: 0.08,
      );

      final destination =
          await getInstallPath(type);

      final logicalDestination =
          await getLogicalInstallPath(type);

      yield SDKInstallProgress(
        message:
            'Destino: $logicalDestination',
        progress: 0.12,
      );

      final destinationDirectory =
          Directory(destination);

      if (!await destinationDirectory.exists()) {
        await destinationDirectory.create(
          recursive: true,
        );
      }

      final fileName =
          file.name.toLowerCase();

      if (fileName.endsWith('.zip')) {
        yield* _installZip(
          source.path,
          destination,
        );
      } else if (fileName.endsWith('.tar.gz') ||
          fileName.endsWith('.tgz')) {
        yield* _installTarGz(
          source.path,
          destination,
        );
      } else if (fileName.endsWith('.tar.xz')) {
        yield* _installTarXz(
          source.path,
          destination,
        );
      } else {
        throw Exception(
          'Formato de arquivo não suportado.',
        );
      }

      yield const SDKInstallProgress(
        message:
            'Organizando a instalação...',
        progress: 0.78,
      );

      final normalizedPath =
          await _normalizeInstallation(
        type,
        destination,
      );

      yield const SDKInstallProgress(
        message:
            'Preparando arquivos executáveis...',
        progress: 0.84,
      );

      await _prepareExecutables(
        normalizedPath,
        type,
      );

      yield const SDKInstallProgress(
        message:
            'Validando instalação...',
        progress: 0.90,
      );

      final validation =
          await validateInstallation(
        type,
        _toLogicalPath(
          normalizedPath,
        ),
      );

      if (!validation.success) {
        throw Exception(
          validation.message,
        );
      }

      final logicalPath =
          validation.installPath ??
          _toLogicalPath(
            normalizedPath,
          );

      await _saveInstallationState(
        type,
        logicalPath,
      );

      /*
       * Configuração automática do ambiente.
       *
       * A Rootfs do Ubuntu possui um /etc/profile próprio.
       * Em vez de executar o Flutter diretamente pelo Android
       * host, escrevemos a configuração diretamente nesse
       * arquivo.
       *
       * Isso faz com que novas sessões:
       *
       *   JAVA_HOME
       *   ANDROID_HOME
       *   ANDROID_SDK_ROOT
       *   PATH
       *
       * já estejam configurados automaticamente.
       *
       * A configuração é executada sempre que Flutter, Java
       * ou Android SDK for instalado, pois qualquer um deles
       * pode ser o último componente necessário para completar
       * o ambiente.
       */
      if (type == SDKComponentType.flutter ||
          type == SDKComponentType.java ||
          type == SDKComponentType.androidSdk) {
        yield const SDKInstallProgress(
          message:
              'Configurando ambiente Flutter...',
          progress: 0.98,
        );

        await _configureFlutterEnvironment();
      }

      yield SDKInstallProgress(
        message:
            'Componente instalado em: '
            '$logicalPath',
        progress: 0.99,
      );

      yield const SDKInstallProgress(
        message:
            'Instalação concluída.',
        progress: 1.0,
      );
    } catch (e) {
      yield SDKInstallProgress(
        message:
            'Erro durante a instalação: $e',
        progress: 0.0,
      );
    }
  }

  bool _isSupportedInstallType(
    SDKComponentType type,
  ) {
    return type ==
            SDKComponentType.flutter ||
        type == SDKComponentType.java ||
        type == SDKComponentType.androidSdk;
  }

  Stream<SDKInstallProgress> _installZip(
    String archive,
    String destination,
  ) async* {
    yield const SDKInstallProgress(
      message:
          'Extraindo arquivo ZIP...',
      progress: 0.25,
    );

    final result =
        await Process.run(
      'unzip',
      [
        '-o',
        archive,
        '-d',
        destination,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Erro ao extrair ZIP:\n'
        '${result.stderr}',
      );
    }

    yield const SDKInstallProgress(
      message:
          'ZIP extraído.',
      progress: 0.72,
    );
  }

  Stream<SDKInstallProgress> _installTarGz(
    String archive,
    String destination,
  ) async* {
    yield const SDKInstallProgress(
      message:
          'Extraindo arquivo TAR.GZ...',
      progress: 0.25,
    );

    final result =
        await Process.run(
      'tar',
      [
        '-xzf',
        archive,
        '-C',
        destination,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Erro ao extrair TAR.GZ:\n'
        '${result.stderr}',
      );
    }

    yield const SDKInstallProgress(
      message:
          'TAR.GZ extraído.',
      progress: 0.72,
    );
  }

  Stream<SDKInstallProgress> _installTarXz(
    String archive,
    String destination,
  ) async* {
    yield const SDKInstallProgress(
      message:
          'Extraindo arquivo TAR.XZ...',
      progress: 0.25,
    );

    final result =
        await Process.run(
      'tar',
      [
        '-xJf',
        archive,
        '-C',
        destination,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Erro ao extrair TAR.XZ:\n'
        '${result.stderr}',
      );
    }

    yield const SDKInstallProgress(
      message:
          'TAR.XZ extraído.',
      progress: 0.72,
    );
  }

  Future<String> _normalizeInstallation(
    SDKComponentType type,
    String destination,
  ) async {
    switch (type) {
      case SDKComponentType.flutter:
        return _normalizeFlutter(
          destination,
        );

      case SDKComponentType.java:
        return _normalizeJava(
          destination,
        );

      case SDKComponentType.androidSdk:
        return _normalizeAndroidSdk(
          destination,
        );

      case SDKComponentType.buildTools:
      case SDKComponentType.platformTools:
      case SDKComponentType.androidPlatform:
      case SDKComponentType.gradle:
      case SDKComponentType.ndk:
      case SDKComponentType.linuxRuntime:
      case SDKComponentType.unknown:
        return destination;
    }
  }

  Future<String> _normalizeFlutter(
    String destination,
  ) async {
    final direct =
        File('$destination/bin/flutter');

    if (await direct.exists()) {
      return destination;
    }

    final nested =
        await _findDirectoryContainingFile(
      Directory(destination),
      'bin/flutter',
      maxDepth: 4,
    );

    if (nested == null ||
        nested == destination) {
      return destination;
    }

    final flutterRoot =
        _removeSuffix(
          nested,
          '/bin/flutter',
        );

    await _moveContentsToRoot(
      Directory(flutterRoot),
      Directory(destination),
    );

    return destination;
  }

  Future<String> _normalizeJava(
    String destination,
  ) async {
    final directJava =
        File('$destination/bin/java');

    final directJavac =
        File('$destination/bin/javac');

    if (await directJava.exists() &&
        await directJavac.exists()) {
      return destination;
    }

    final nested =
        await _findDirectoryContainingFile(
      Directory(destination),
      'bin/java',
      maxDepth: 4,
    );

    if (nested == null ||
        nested == destination) {
      return destination;
    }

    final javaRoot =
        _removeSuffix(
          nested,
          '/bin/java',
        );

    await _moveContentsToRoot(
      Directory(javaRoot),
      Directory(destination),
    );

    return destination;
  }

  Future<String> _normalizeAndroidSdk(
    String destination,
  ) async {
    if (await _hasAndroidSdkContent(
      destination,
    )) {
      return destination;
    }

    final nested =
        await _findDirectoryContainingAny(
      Directory(destination),
      const [
        'platform-tools',
        'build-tools',
        'platforms',
        'cmdline-tools',
      ],
      maxDepth: 4,
    );

    if (nested == null ||
        nested == destination) {
      return destination;
    }

    await _moveContentsToRoot(
      Directory(nested),
      Directory(destination),
    );

    return destination;
  }

  Future<bool> _hasAndroidSdkContent(
    String path,
  ) async {
    final platformTools =
        Directory(
      '$path/platform-tools',
    );

    final buildTools =
        Directory(
      '$path/build-tools',
    );

    final platforms =
        Directory(
      '$path/platforms',
    );

    final cmdlineTools =
        Directory(
      '$path/cmdline-tools',
    );

    return await platformTools.exists() ||
        await buildTools.exists() ||
        await platforms.exists() ||
        await cmdlineTools.exists();
  }

  Future<void> _moveContentsToRoot(
    Directory source,
    Directory destination,
  ) async {
    if (!await source.exists()) {
      return;
    }

    if (!await destination.exists()) {
      await destination.create(
        recursive: true,
      );
    }

    final entities =
        await source.list(
          followLinks: false,
        ).toList();

    for (final entity in entities) {
      final name =
          _basename(entity.path);

      final target =
          '${destination.path}/$name';

      try {
        if (entity is Directory) {
          final targetDirectory =
              Directory(target);

          if (await targetDirectory.exists()) {
            await _mergeDirectories(
              entity,
              targetDirectory,
            );
          } else {
            await entity.rename(
              target,
            );
          }
        } else if (entity is File) {
          final targetFile =
              File(target);

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await entity.rename(
            target,
          );
        }
      } catch (_) {}
    }

    try {
      if (source.path != destination.path) {
        await source.delete(
          recursive: true,
        );
      }
    } catch (_) {}
  }

  Future<void> _mergeDirectories(
    Directory source,
    Directory destination,
  ) async {
    if (!await destination.exists()) {
      await destination.create(
        recursive: true,
      );
    }

    final entities =
        await source.list(
          followLinks: false,
        ).toList();

    for (final entity in entities) {
      final name =
          _basename(entity.path);

      final target =
          '${destination.path}/$name';

      try {
        if (entity is Directory) {
          await _mergeDirectories(
            entity,
            Directory(target),
          );
        } else if (entity is File) {
          final targetFile =
              File(target);

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await entity.rename(
            target,
          );
        }
      } catch (_) {}
    }

    try {
      await source.delete(
        recursive: true,
      );
    } catch (_) {}
  }

  Future<String?> _findDirectoryContainingFile(
    Directory root,
    String relativePath, {
    int maxDepth = 2,
  }) async {
    if (!await root.exists()) {
      return null;
    }

    final direct =
        File(
      '${root.path}/$relativePath',
    );

    if (await direct.exists()) {
      return root.path;
    }

    if (maxDepth <= 0) {
      return null;
    }

    try {
      await for (final entity
          in root.list(
        followLinks: false,
      )) {
        if (entity is! Directory) {
          continue;
        }

        final result =
            await _findDirectoryContainingFile(
          entity,
          relativePath,
          maxDepth:
              maxDepth - 1,
        );

        if (result != null) {
          return result;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _findDirectoryContainingAny(
    Directory root,
    List<String> names, {
    int maxDepth = 2,
  }) async {
    if (!await root.exists()) {
      return null;
    }

    for (final name in names) {
      if (await Directory(
        '${root.path}/$name',
      ).exists()) {
        return root.path;
      }

      if (await File(
        '${root.path}/$name',
      ).exists()) {
        return root.path;
      }
    }

    if (maxDepth <= 0) {
      return null;
    }

    try {
      await for (final entity
          in root.list(
        followLinks: false,
      )) {
        if (entity is! Directory) {
          continue;
        }

        final result =
            await _findDirectoryContainingAny(
          entity,
          names,
          maxDepth:
              maxDepth - 1,
        );

        if (result != null) {
          return result;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _prepareExecutables(
    String path,
    SDKComponentType type,
  ) async {
    try {
      await Process.run(
        'chmod',
        [
          '-R',
          'u+rwX',
          path,
        ],
      );

      final executables =
          <String>[];

      switch (type) {
        case SDKComponentType.flutter:
          executables.addAll([
            '$path/bin/flutter',
            '$path/bin/dart',
            '$path/bin/cache/dart-sdk/bin/dart',
            '$path/bin/cache/dart-sdk/bin/dartaotruntime',
            '$path/bin/cache/dart-sdk/bin/dartvm',
          ]);
          break;

        case SDKComponentType.java:
          executables.addAll([
            '$path/bin/java',
            '$path/bin/javac',
            '$path/bin/jar',
            '$path/bin/javadoc',
            '$path/bin/javap',
          ]);
          break;

        case SDKComponentType.androidSdk:
          executables.addAll([
            '$path/platform-tools/adb',
            '$path/platform-tools/fastboot',
          ]);
          break;

        case SDKComponentType.buildTools:
        case SDKComponentType.platformTools:
        case SDKComponentType.androidPlatform:
        case SDKComponentType.gradle:
        case SDKComponentType.ndk:
        case SDKComponentType.linuxRuntime:
        case SDKComponentType.unknown:
          break;
      }

      for (final executable
          in executables) {
        final file =
            File(executable);

        if (await file.exists()) {
          await Process.run(
            'chmod',
            [
              'u+x',
              executable,
            ],
          );
        }
      }

      final flutterBin =
          Directory('$path/bin');

      if (type ==
              SDKComponentType.flutter &&
          await flutterBin.exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            'u+x',
            flutterBin.path,
          ],
        );
      }

      final dartBin =
          Directory(
        '$path/bin/cache/dart-sdk/bin',
      );

      if (type ==
              SDKComponentType.flutter &&
          await dartBin.exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            'u+x',
            dartBin.path,
          ],
        );
      }

      final androidPlatformTools =
          Directory(
        '$path/platform-tools',
      );

      if (type ==
              SDKComponentType.androidSdk &&
          await androidPlatformTools.exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            'u+x',
            androidPlatformTools.path,
          ],
        );
      }

      final androidBuildTools =
          Directory(
        '$path/build-tools',
      );

      if (type ==
              SDKComponentType.androidSdk &&
          await androidBuildTools.exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            'u+x',
            androidBuildTools.path,
          ],
        );
      }

      final ndkToolchains =
          Directory(
        '$path/ndk',
      );

      if (type ==
              SDKComponentType.androidSdk &&
          await ndkToolchains.exists()) {
        await Process.run(
          'chmod',
          [
            '-R',
            'u+x',
            ndkToolchains.path,
          ],
        );
      }
    } catch (_) {}
  }

  /// Configura automaticamente o ambiente de desenvolvimento
  /// dentro da Rootfs do Ubuntu.
  ///
  /// A configuração é gravada diretamente no:
  ///
  ///   /etc/profile
  ///
  /// da Rootfs.
  ///
  /// Isso evita executar binários da Rootfs diretamente pelo
  /// Android host, o que seria incorreto sem passar pelo PRoot.
  ///
  /// O método:
  ///
  /// - detecta automaticamente o JDK instalado;
  /// - configura JAVA_HOME;
  /// - configura ANDROID_HOME;
  /// - configura ANDROID_SDK_ROOT;
  /// - configura Flutter no PATH;
  /// - configura Android platform-tools no PATH;
  /// - configura Android cmdline-tools no PATH;
  /// - preserva o restante do /etc/profile;
  /// - substitui somente o bloco criado pelo FlutterIDE;
  /// - não cria entradas duplicadas.
  Future<void> _configureFlutterEnvironment() async {
    try {
      final rootfs =
          await getRootfsPath();

      final etcDirectory =
          Directory('$rootfs/etc');

      if (!await etcDirectory.exists()) {
        await etcDirectory.create(
          recursive: true,
        );
      }

      final flutterDirectory =
          Directory('$rootfs/opt/flutter');

      final androidSdkDirectory =
          Directory('$rootfs/opt/android_sdk');

      final javaDirectory =
          Directory('$rootfs/opt/java');

      final hasFlutter =
          await File(
            '$rootfs/opt/flutter/bin/flutter',
          ).exists();

      final hasAndroidSdk =
          await _hasAndroidSdkContent(
            androidSdkDirectory.path,
          );

      final javaHome =
          await _findJavaHome(
            javaDirectory,
          );

      /*
       * Não há nada para configurar enquanto nenhum dos
       * componentes principais estiver disponível.
       */
      if (!hasFlutter &&
          !hasAndroidSdk &&
          javaHome == null) {
        return;
      }

      /*
       * Construímos o bloco somente com caminhos que
       * realmente existem.
       */
      final lines =
          <String>[
        _environmentStartMarker,
      ];

      if (javaHome != null) {
        final logicalJavaHome =
            _toLogicalPath(javaHome);

        lines.add(
          'export JAVA_HOME=$logicalJavaHome',
        );
      }

      if (hasAndroidSdk) {
        lines.add(
          'export ANDROID_HOME=/opt/android_sdk',
        );

        lines.add(
          'export ANDROID_SDK_ROOT=/opt/android_sdk',
        );
      }

      final pathEntries =
          <String>[];

      if (javaHome != null) {
        pathEntries.add(
          '${_toLogicalPath(javaHome)}/bin',
        );
      }

      if (hasFlutter &&
          await flutterDirectory.exists()) {
        pathEntries.add(
          '/opt/flutter/bin',
        );
      }

      if (hasAndroidSdk) {
        final platformTools =
            Directory(
          '$rootfs/opt/android_sdk/platform-tools',
        );

        final commandLineTools =
            Directory(
          '$rootfs/opt/android_sdk/cmdline-tools/latest/bin',
        );

        if (await platformTools.exists()) {
          pathEntries.add(
            '/opt/android_sdk/platform-tools',
          );
        }

        if (await commandLineTools.exists()) {
          pathEntries.add(
            '/opt/android_sdk/cmdline-tools/latest/bin',
          );
        }
      }

      if (pathEntries.isNotEmpty) {
        lines.add(
          'export PATH="${pathEntries.join(':')}:\$PATH"',
        );
      }

      lines.add(
        _environmentEndMarker,
      );

      final environmentBlock =
          lines.join('\n');

      final profileFile =
          File('$rootfs/etc/profile');

      String currentProfile = '';

      if (await profileFile.exists()) {
        try {
          currentProfile =
              await profileFile.readAsString();
        } catch (_) {
          currentProfile = '';
        }
      }

      /*
       * Remove somente o bloco anteriormente criado
       * pelo FlutterIDE.
       *
       * Isso também corrige uma Rootfs onde o bloco antigo
       * tenha sido criado manualmente durante os testes.
       */
      final startIndex =
          currentProfile.indexOf(
        _environmentStartMarker,
      );

      final endIndex =
          currentProfile.indexOf(
        _environmentEndMarker,
      );

      if (startIndex >= 0 &&
          endIndex >= startIndex) {
        final endOfBlock =
            endIndex +
                _environmentEndMarker.length;

        currentProfile =
            currentProfile.substring(
                  0,
                  startIndex,
                ) +
                currentProfile.substring(
                  endOfBlock,
                );
      }

      /*
       * Remove espaços e quebras excessivas somente nas
       * extremidades. O conteúdo existente do profile é
       * preservado.
       */
      currentProfile =
          currentProfile.trimRight();

      final updatedProfile =
          currentProfile.isEmpty
              ? environmentBlock
              : '$currentProfile\n\n$environmentBlock';

      await profileFile.writeAsString(
        '$updatedProfile\n',
        flush: true,
      );

      /*
       * Também mantemos /etc/environment coerente para
       * processos que não utilizem shell de login.
       *
       * Não colocamos PATH aqui, porque /etc/environment
       * não interpreta "$PATH" como o shell interpreta.
       * O PATH completo continua sendo responsabilidade
       * do /etc/profile.
       */
      final environmentFile =
          File('$rootfs/etc/environment');

      String currentEnvironment = '';

      if (await environmentFile.exists()) {
        try {
          currentEnvironment =
              await environmentFile.readAsString();
        } catch (_) {
          currentEnvironment = '';
        }
      }

      currentEnvironment =
          _removeEnvironmentVariable(
        currentEnvironment,
        'JAVA_HOME',
      );

      currentEnvironment =
          _removeEnvironmentVariable(
        currentEnvironment,
        'ANDROID_HOME',
      );

      currentEnvironment =
          _removeEnvironmentVariable(
        currentEnvironment,
        'ANDROID_SDK_ROOT',
      );

      final environmentLines =
          <String>[];

      if (javaHome != null) {
        environmentLines.add(
          'JAVA_HOME=${_toLogicalPath(javaHome)}',
        );
      }

      if (hasAndroidSdk) {
        environmentLines.add(
          'ANDROID_HOME=/opt/android_sdk',
        );

        environmentLines.add(
          'ANDROID_SDK_ROOT=/opt/android_sdk',
        );
      }

      currentEnvironment =
          currentEnvironment.trimRight();

      final environmentContent =
          <String>[
        if (currentEnvironment.isNotEmpty)
          currentEnvironment,
        if (environmentLines.isNotEmpty)
          environmentLines.join('\n'),
      ].join('\n\n');

      await environmentFile.writeAsString(
        environmentContent.isEmpty
            ? ''
            : '$environmentContent\n',
        flush: true,
      );
    } catch (_) {
      /*
       * A configuração do ambiente é complementar à
       * instalação. Uma falha aqui não invalida o SDK
       * que já foi instalado e validado.
       */
    }
  }

  /// Procura o JDK real instalado em /opt/java.
  ///
  /// São aceitos os dois formatos:
  ///
  /// /opt/java/bin/java
  ///
  /// ou:
  ///
  /// /opt/java/jdk-26.0.2.1/bin/java
  ///
  /// Dessa forma a versão do JDK não fica fixa no código.
  Future<String?> _findJavaHome(
    Directory javaRoot,
  ) async {
    if (!await javaRoot.exists()) {
      return null;
    }

    final directJava =
        File(
      '${javaRoot.path}/bin/java',
    );

    final directJavac =
        File(
      '${javaRoot.path}/bin/javac',
    );

    if (await directJava.exists() &&
        await directJavac.exists()) {
      return javaRoot.path;
    }

    return _findDirectoryContainingJava(
      javaRoot,
      maxDepth: 4,
    );
  }

  Future<String?> _findDirectoryContainingJava(
    Directory root, {
    int maxDepth = 4,
  }) async {
    if (!await root.exists()) {
      return null;
    }

    final java =
        File(
      '${root.path}/bin/java',
    );

    final javac =
        File(
      '${root.path}/bin/javac',
    );

    if (await java.exists() &&
        await javac.exists()) {
      return root.path;
    }

    if (maxDepth <= 0) {
      return null;
    }

    try {
      await for (final entity
          in root.list(
        followLinks: false,
      )) {
        if (entity is! Directory) {
          continue;
        }

        final result =
            await _findDirectoryContainingJava(
          entity,
          maxDepth:
              maxDepth - 1,
        );

        if (result != null) {
          return result;
        }
      }
    } catch (_) {}

    return null;
  }

  String _removeEnvironmentVariable(
    String content,
    String variable,
  ) {
    if (content.trim().isEmpty) {
      return '';
    }

    final lines =
        content.split('\n');

    final filtered =
        lines.where(
      (line) {
        final trimmed =
            line.trim();

        if (trimmed.isEmpty) {
          return true;
        }

        if (trimmed.startsWith(
          '$variable=',
        )) {
          return false;
        }

        if (trimmed.startsWith(
          '$variable ',
        )) {
          return false;
        }

        if (trimmed.startsWith(
          'export $variable=',
        )) {
          return false;
        }

        return true;
      },
    ).toList();

    return filtered.join('\n');
  }

  Future<SDKInstallResult>
      validateInstallation(
    SDKComponentType type,
    String logicalPath,
  ) async {
    try {
      await getRootfsPath();
    } catch (e) {
      return SDKInstallResult(
        success: false,
        message: e.toString(),
      );
    }

    final path =
        _toPhysicalPath(logicalPath);

    switch (type) {
      case SDKComponentType.flutter:
        return _validateFlutter(path);

      case SDKComponentType.java:
        return _validateJava(path);

      case SDKComponentType.androidSdk:
        return _validateAndroidSdk(path);

      case SDKComponentType.buildTools:
      case SDKComponentType.platformTools:
      case SDKComponentType.androidPlatform:
      case SDKComponentType.gradle:
      case SDKComponentType.ndk:
        return const SDKInstallResult(
          success: false,
          message:
              'Este componente faz parte do '
              'Android SDK e não é instalado '
              'separadamente.',
        );

      case SDKComponentType.linuxRuntime:
        return _validateLinuxRuntime(path);

      case SDKComponentType.unknown:
        return const SDKInstallResult(
          success: false,
          message:
              'Componente desconhecido.',
        );
    }
  }

  Future<SDKInstallResult> _validateFlutter(
    String path,
  ) async {
    final flutter =
        File('$path/bin/flutter');

    final dart =
        File(
      '$path/bin/cache/dart-sdk/bin/dart',
    );

    if (!await flutter.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'bin/flutter não encontrado.',
      );
    }

    if (!await dart.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'Dart SDK não encontrado dentro do Flutter.',
      );
    }

    return SDKInstallResult(
      success: true,
      message:
          'Flutter encontrado.',
      installPath:
          _toLogicalPath(path),
    );
  }

  Future<SDKInstallResult> _validateJava(
    String path,
  ) async {
    final java =
        File('$path/bin/java');

    final javac =
        File('$path/bin/javac');

    if (!await java.exists() ||
        !await javac.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'bin/java ou bin/javac não encontrado.',
      );
    }

    return SDKInstallResult(
      success: true,
      message:
          'JDK encontrado.',
      installPath:
          _toLogicalPath(path),
    );
  }

  Future<SDKInstallResult>
      _validateAndroidSdk(
    String path,
  ) async {
    final directory =
        Directory(path);

    if (!await directory.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'Diretório do Android SDK não encontrado.',
      );
    }

    final platformTools =
        Directory(
      '$path/platform-tools',
    );

    final buildTools =
        Directory(
      '$path/build-tools',
    );

    final platforms =
        Directory(
      '$path/platforms',
    );

    final cmdlineTools =
        Directory(
      '$path/cmdline-tools',
    );

    final hasPlatformTools =
        await platformTools.exists();

    final hasBuildTools =
        await buildTools.exists();

    final hasPlatforms =
        await platforms.exists();

    final hasCommandLineTools =
        await cmdlineTools.exists();

    final componentCount = [
      hasPlatformTools,
      hasBuildTools,
      hasPlatforms,
      hasCommandLineTools,
    ].where((value) => value).length;

    if (componentCount < 2) {
      return const SDKInstallResult(
        success: false,
        message:
            'A estrutura do Android SDK está '
            'incompleta. Era esperado encontrar '
            'os componentes internos do SDK.',
      );
    }

    final adb =
        File('$path/platform-tools/adb');

    if (hasPlatformTools &&
        !await adb.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'platform-tools foi encontrado, '
            'mas o executável adb não existe.',
      );
    }

    return SDKInstallResult(
      success: true,
      message:
          'Android SDK completo encontrado.',
      installPath:
          _toLogicalPath(path),
    );
  }

  Future<SDKInstallResult>
      _validateLinuxRuntime(
    String path,
  ) async {
    final directory =
        Directory(path);

    if (!await directory.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'Ubuntu não encontrado.',
      );
    }

    final bash =
        File('$path/bin/bash');

    final usrBash =
        File('$path/usr/bin/bash');

    if (!await bash.exists() &&
        !await usrBash.exists()) {
      return const SDKInstallResult(
        success: false,
        message:
            'Executável bash do Ubuntu não encontrado.',
      );
    }

    return SDKInstallResult(
      success: true,
      message:
          'Ubuntu encontrado.',
      installPath: '/',
    );
  }

  String _toLogicalPath(
    String physicalPath,
  ) {
    final normalized =
        physicalPath.replaceAll('\\', '/');

    final rootfs =
        _rootfsPath;

    if (rootfs == null) {
      return normalized;
    }

    final normalizedRoot =
        rootfs.replaceAll('\\', '/');

    if (normalized.startsWith(
      '$normalizedRoot/',
    )) {
      return normalized.substring(
        normalizedRoot.length,
      );
    }

    if (normalized == normalizedRoot) {
      return '/';
    }

    return normalized;
  }

  String _toPhysicalPath(
    String path,
  ) {
    if (!path.startsWith('/')) {
      return path;
    }

    final rootfs =
        _rootfsPath;

    if (rootfs == null) {
      return path;
    }

    return '$rootfs$path';
  }

  String _removeSuffix(
    String value,
    String suffix,
  ) {
    if (value.endsWith(suffix)) {
      return value.substring(
        0,
        value.length - suffix.length,
      );
    }

    return value;
  }

  String _basename(String path) {
    final normalized =
        path.replaceAll('\\', '/');

    final index =
        normalized.lastIndexOf('/');

    if (index == -1) {
      return normalized;
    }

    return normalized.substring(
      index + 1,
    );
  }

  String _formatBytes(
    int bytes,
  ) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes <
        1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes <
        1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}