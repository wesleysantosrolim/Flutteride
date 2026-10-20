import 'dart:io';

import '../models/sdk_component.dart';
import '../models/sdk_file.dart';

class SDKDetectionResult {
  final bool success;
  final SDKComponentType componentType;
  final String? version;
  final String? architecture;
  final String message;

  const SDKDetectionResult({
    required this.success,
    required this.componentType,
    this.version,
    this.architecture,
    required this.message,
  });

  factory SDKDetectionResult.success({
    required SDKComponentType componentType,
    String? version,
    String? architecture,
    required String message,
  }) {
    return SDKDetectionResult(
      success: true,
      componentType: componentType,
      version: version,
      architecture: architecture,
      message: message,
    );
  }

  factory SDKDetectionResult.failure({
    required String message,
  }) {
    return SDKDetectionResult(
      success: false,
      componentType: SDKComponentType.unknown,
      message: message,
    );
  }
}

class SDKDetectorService {
  Future<SDKDetectionResult> detect(
    SDKFile file,
  ) async {
    final source = File(file.path);

    if (!await source.exists()) {
      return SDKDetectionResult.failure(
        message:
            'O arquivo selecionado não existe mais.',
      );
    }

    final size = await source.length();

    if (size <= 0) {
      return SDKDetectionResult.failure(
        message:
            'O arquivo selecionado está vazio.',
      );
    }

    final fileName = file.name.toLowerCase();

    if (!_isSupportedArchive(fileName)) {
      return SDKDetectionResult.failure(
        message:
            'Formato de arquivo não suportado.\n'
            'Utilize um arquivo .tar.gz.',
      );
    }

    final componentType =
        _detectComponentType(fileName);

    if (componentType == SDKComponentType.unknown) {
      return SDKDetectionResult.failure(
        message:
            'Não foi possível identificar o pacote.\n\n'
            'Os arquivos esperados são:\n'
            '• flutter-sdk.tar.gz\n'
            '• jdk-17.tar.gz\n'
            '• android-sdk.tar.gz',
      );
    }

    final architecture =
        _detectArchitecture(fileName);

    final version =
        _extractVersion(
      componentType,
      fileName,
    );

    return SDKDetectionResult.success(
      componentType: componentType,
      version: version,
      architecture: architecture,
      message: _buildMessage(
        componentType,
        version,
        architecture,
      ),
    );
  }

  bool isCompatible(
    SDKComponentType expected,
    SDKDetectionResult detected,
  ) {
    if (!detected.success) {
      return false;
    }

    return expected == detected.componentType;
  }

  bool _isSupportedArchive(String name) {
    return name.endsWith('.tar.gz') ||
        name.endsWith('.tgz') ||
        name.endsWith('.tar.xz') ||
        name.endsWith('.zip');
  }

  SDKComponentType _detectComponentType(
    String name,
  ) {
    if (_isFlutterFile(name)) {
      return SDKComponentType.flutter;
    }

    if (_isJavaFile(name)) {
      return SDKComponentType.java;
    }

    if (_isAndroidSdkFile(name)) {
      return SDKComponentType.androidSdk;
    }

    return SDKComponentType.unknown;
  }

  bool _isFlutterFile(String name) {
    return name == 'flutter-sdk.tar.gz' ||
        (name.contains('flutter') &&
            name.contains('sdk'));
  }

  bool _isJavaFile(String name) {
    return name == 'jdk-17.tar.gz' ||
        name.contains('jdk-17') ||
        name.contains('jdk17') ||
        name.contains('java-17') ||
        name.contains('java17');
  }

  bool _isAndroidSdkFile(String name) {
    return name == 'android-sdk.tar.gz' ||
        name.contains('android-sdk') ||
        name.contains('android_sdk');
  }

  String? _extractVersion(
    SDKComponentType type,
    String name,
  ) {
    switch (type) {
      case SDKComponentType.java:
        return _extractJavaVersion(name);

      case SDKComponentType.flutter:
        return _extractFlutterVersion(name);

      case SDKComponentType.androidSdk:
        return null;

      default:
        return null;
    }
  }

  String? _extractFlutterVersion(String name) {
    final regex = RegExp(
      r'flutter[-_]?(\d+\.\d+\.\d+)',
      caseSensitive: false,
    );

    return regex.firstMatch(name)?.group(1);
  }

  String? _extractJavaVersion(String name) {
    final regex = RegExp(
      r'(?:jdk|java)[-_]?(\d+)',
      caseSensitive: false,
    );

    return regex.firstMatch(name)?.group(1);
  }

  String? _detectArchitecture(String name) {
    final normalized =
        name.toLowerCase();

    if (normalized.contains('arm64') ||
        normalized.contains('aarch64')) {
      return 'arm64';
    }

    if (normalized.contains('armv8')) {
      return 'arm64';
    }

    if (normalized.contains('x86_64') ||
        normalized.contains('x64') ||
        normalized.contains('amd64')) {
      return 'x86_64';
    }

    if (normalized.contains('x86')) {
      return 'x86';
    }

    return null;
  }

  String _buildMessage(
    SDKComponentType type,
    String? version,
    String? architecture,
  ) {
    String base;

    switch (type) {
      case SDKComponentType.flutter:
        base = 'Flutter SDK detectado.';

      case SDKComponentType.java:
        base = 'JDK 17 detectado.';

      case SDKComponentType.androidSdk:
        base = 'Android SDK completo detectado.';

      default:
        base = 'Pacote SDK detectado.';
    }

    if (version != null) {
      base = '$base Versão: $version.';
    }

    if (architecture != null) {
      base = '$base Arquitetura: $architecture.';
    }

    return base;
  }
}