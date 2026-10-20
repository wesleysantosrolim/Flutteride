import 'dart:io';

import 'sdk_component.dart';

class SDKFile {
  final String path;
  final SDKComponentType componentType;

  final String name;
  final int sizeBytes;

  SDKFile({
    required this.path,
    required this.componentType,
    required this.name,
    required this.sizeBytes,
  });

  factory SDKFile.fromPath({
    required String path,
    required SDKComponentType componentType,
  }) {
    final file = File(path);

    return SDKFile(
      path: path,
      componentType: componentType,
      name: _extractFileName(path),
      sizeBytes: file.existsSync() ? file.lengthSync() : 0,
    );
  }

  static String _extractFileName(String path) {
    final normalizedPath = path.replaceAll('\\', '/');
    final parts = normalizedPath.split('/');

    return parts.isNotEmpty ? parts.last : path;
  }

  String get extension {
    final lowerName = name.toLowerCase();

    if (lowerName.endsWith('.tar.gz')) {
      return '.tar.gz';
    }

    if (lowerName.endsWith('.tar.xz')) {
      return '.tar.xz';
    }

    if (lowerName.endsWith('.tar.bz2')) {
      return '.tar.bz2';
    }

    final index = name.lastIndexOf('.');

    if (index == -1) {
      return '';
    }

    return name.substring(index).toLowerCase();
  }

  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }

    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }

    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get exists {
    return File(path).existsSync();
  }

  SDKFile copy() {
    return SDKFile(
      path: path,
      componentType: componentType,
      name: name,
      sizeBytes: sizeBytes,
    );
  }

  @override
  String toString() {
    return 'SDKFile('
        'name: $name, '
        'path: $path, '
        'size: $formattedSize, '
        'component: $componentType'
        ')';
  }
}