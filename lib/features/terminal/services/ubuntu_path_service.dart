import 'package:path/path.dart' as p;

import 'ubuntu_session_manager.dart';

class UbuntuPathService {
  UbuntuPathService({
    UbuntuSessionManager? sessionManager,
  }) : _sessionManager =
            sessionManager ?? UbuntuSessionManager.instance;

  UbuntuPathService._internal()
      : _sessionManager = UbuntuSessionManager.instance;

  static final UbuntuPathService instance =
      UbuntuPathService._internal();

  final UbuntuSessionManager _sessionManager;

  /// Converte um caminho lógico do Ubuntu para o caminho
  /// físico correspondente no sistema Android.
  ///
  /// Exemplos:
  ///
  /// /root/projects/teste
  /// ->
  /// <appSupport>/ubuntu_rootfs/root/projects/teste
  ///
  /// /storage/emulated/0/AndroidFlutter
  /// ->
  /// /storage/emulated/0/AndroidFlutter
  Future<String> toPhysicalPath(
    String ubuntuPath,
  ) async {
    final normalizedPath = _normalizeAbsolutePath(
      ubuntuPath,
    );

    if (_isSharedStoragePath(normalizedPath)) {
      return normalizedPath;
    }

    if (_isSdcardPath(normalizedPath)) {
      return _sdcardToStoragePath(
        normalizedPath,
      );
    }

    final rootfsPath = p.normalize(
      await _sessionManager.getRootfsPath(),
    );

    if (normalizedPath == '/') {
      return rootfsPath;
    }

    return p.join(
      rootfsPath,
      normalizedPath.substring(1),
    );
  }

  /// Converte um caminho físico do Android para o caminho
  /// lógico correspondente dentro do Ubuntu.
  ///
  /// Exemplos:
  ///
  /// <appSupport>/ubuntu_rootfs/root/projects/teste
  /// ->
  /// /root/projects/teste
  ///
  /// /storage/emulated/0/AndroidFlutter
  /// ->
  /// /storage/emulated/0/AndroidFlutter
  Future<String> toUbuntuPath(
    String physicalPath,
  ) async {
    final normalizedPath = p.normalize(
      physicalPath,
    );

    if (_isSharedStoragePath(normalizedPath)) {
      return normalizedPath;
    }

    final rootfsPath = p.normalize(
      await _sessionManager.getRootfsPath(),
    );

    if (normalizedPath == rootfsPath) {
      return '/';
    }

    final rootfsPrefix = '$rootfsPath${p.separator}';

    if (!normalizedPath.startsWith(rootfsPrefix)) {
      throw ArgumentError(
        'O caminho não pertence ao Ubuntu rootfs: '
        '$physicalPath',
      );
    }

    final relativePath = p.relative(
      normalizedPath,
      from: rootfsPath,
    );

    if (relativePath == '.') {
      return '/';
    }

    return '/$relativePath';
  }

  String _normalizeAbsolutePath(
    String path,
  ) {
    final trimmed = path.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError(
        'O caminho não pode estar vazio.',
      );
    }

    if (!p.isAbsolute(trimmed)) {
      throw ArgumentError(
        'O caminho do Ubuntu precisa ser absoluto: $path',
      );
    }

    return p.normalize(trimmed);
  }

  bool _isSharedStoragePath(
    String path,
  ) {
    return path == '/storage/emulated/0' ||
        path.startsWith('/storage/emulated/0/');
  }

  bool _isSdcardPath(
    String path,
  ) {
    return path == '/sdcard' ||
        path.startsWith('/sdcard/');
  }

  String _sdcardToStoragePath(
    String path,
  ) {
    if (path == '/sdcard') {
      return '/storage/emulated/0';
    }

    final relativePath = path.substring(
      '/sdcard/'.length,
    );

    return p.normalize(
      p.join(
        '/storage/emulated/0',
        relativePath,
      ),
    );
  }
}