import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../terminal/services/ubuntu_path_service.dart';
import '../models/editor_file_node.dart';

class EditorFileService {
  EditorFileService({
    UbuntuPathService? pathService,
  }) : _pathService =
            pathService ?? UbuntuPathService.instance;

  final UbuntuPathService _pathService;

  String? _clipboardPath;
  bool _clipboardIsDirectory = false;

  // ---------------------------------------------------------------------------
  // ÁRVORE DO PROJETO
  // ---------------------------------------------------------------------------

  Future<List<EditorFileNode>> listProjectTree(
    String projectPath,
  ) async {
    final physicalProjectPath =
        await _pathService.toPhysicalPath(
      projectPath,
    );

    final projectDirectory =
        Directory(physicalProjectPath);

    if (!await projectDirectory.exists()) {
      throw Exception(
        'Diretório do projeto não existe: $projectPath',
      );
    }

    final root =
        _TreeDirectory(
      name: '',
      path: projectPath,
    );

    await _readDirectoryTree(
      directory: projectDirectory,
      logicalPath: projectPath,
      parent: root,
    );

    return root.children
        .map(
          (node) => node.toNode(),
        )
        .toList();
  }

  Future<void> _readDirectoryTree({
    required Directory directory,
    required String logicalPath,
    required _TreeDirectory parent,
  }) async {
    final entities =
        <FileSystemEntity>[];

    await for (final entity
        in directory.list(
      followLinks: false,
    )) {
      entities.add(entity);
    }

    entities.sort(
      (a, b) {
        final aIsDirectory =
            a is Directory;

        final bIsDirectory =
            b is Directory;

        if (aIsDirectory &&
            !bIsDirectory) {
          return -1;
        }

        if (!aIsDirectory &&
            bIsDirectory) {
          return 1;
        }

        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(
              p
                  .basename(b.path)
                  .toLowerCase(),
            );
      },
    );

    for (final entity in entities) {
      final name =
          p.basename(entity.path);

      final childLogicalPath =
          _joinPath(
        logicalPath,
        name,
      );

      if (entity is Directory) {
        final childDirectory =
            _TreeDirectory(
          name: name,
          path: childLogicalPath,
        );

        parent.children.add(
          childDirectory,
        );

        await _readDirectoryTree(
          directory: entity,
          logicalPath: childLogicalPath,
          parent: childDirectory,
        );
      } else {
        parent.children.add(
          _TreeFile(
            name: name,
            path: childLogicalPath,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LEITURA DE ARQUIVO
  // ---------------------------------------------------------------------------

  Future<String> readFile(
    String filePath,
  ) async {
    final physicalPath =
        await _pathService.toPhysicalPath(
      filePath,
    );

    final file =
        File(physicalPath);

    if (!await file.exists()) {
      throw Exception(
        'Arquivo não existe: $filePath',
      );
    }

    try {
      return await file.readAsString();
    } catch (error) {
      throw Exception(
        'Não foi possível ler o arquivo: $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SALVAMENTO DE ARQUIVO
  // ---------------------------------------------------------------------------

  Future<void> writeFile(
    String filePath,
    String content,
  ) async {
    final physicalPath =
        await _pathService.toPhysicalPath(
      filePath,
    );

    final file =
        File(physicalPath);

    if (!await file.exists()) {
      throw Exception(
        'Arquivo não existe: $filePath',
      );
    }

    try {
      await file.writeAsString(
        content,
      );
    } catch (error) {
      throw Exception(
        'Não foi possível salvar o arquivo: $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // NOVO ARQUIVO
  // ---------------------------------------------------------------------------

  Future<String> createFile(
    String directoryPath,
    String fileName, {
    String content = '',
  }) async {
    final cleanName =
        _validateName(
      fileName,
      'nome do arquivo',
    );

    final targetPath =
        _joinPath(
      directoryPath,
      cleanName,
    );

    final physicalDirectory =
        await _pathService.toPhysicalPath(
      directoryPath,
    );

    final directory =
        Directory(physicalDirectory);

    if (!await directory.exists()) {
      throw Exception(
        'A pasta de destino não existe.',
      );
    }

    final physicalTarget =
        p.join(
      physicalDirectory,
      cleanName,
    );

    final target =
        File(physicalTarget);

    if (await target.exists() ||
        await Directory(physicalTarget)
            .exists()) {
      throw Exception(
        'Já existe um item com esse nome: $cleanName',
      );
    }

    await target.writeAsString(
      content,
    );

    return targetPath;
  }

  // ---------------------------------------------------------------------------
  // NOVA PASTA
  // ---------------------------------------------------------------------------

  Future<String> createDirectory(
    String parentPath,
    String directoryName,
  ) async {
    final cleanName =
        _validateName(
      directoryName,
      'nome da pasta',
    );

    final targetPath =
        _joinPath(
      parentPath,
      cleanName,
    );

    final physicalParent =
        await _pathService.toPhysicalPath(
      parentPath,
    );

    final parent =
        Directory(physicalParent);

    if (!await parent.exists()) {
      throw Exception(
        'A pasta de destino não existe.',
      );
    }

    final physicalTarget =
        p.join(
      physicalParent,
      cleanName,
    );

    if (await File(physicalTarget).exists() ||
        await Directory(physicalTarget)
            .exists()) {
      throw Exception(
        'Já existe um item com esse nome: $cleanName',
      );
    }

    await Directory(
      physicalTarget,
    ).create();

    return targetPath;
  }

  // ---------------------------------------------------------------------------
  // RENOMEAR
  // ---------------------------------------------------------------------------

  Future<String> rename(
    String sourcePath,
    String newName,
  ) async {
    final cleanName =
        _validateName(
      newName,
      'novo nome',
    );

    final parentPath =
        p.dirname(sourcePath);

    if (parentPath == sourcePath) {
      throw Exception(
        'Não foi possível determinar a pasta pai.',
      );
    }

    final targetPath =
        _joinPath(
      parentPath,
      cleanName,
    );

    final physicalSource =
        await _pathService.toPhysicalPath(
      sourcePath,
    );

    final physicalTarget =
        await _pathService.toPhysicalPath(
      targetPath,
    );

    final sourceType =
        await FileSystemEntity.type(
      physicalSource,
      followLinks: false,
    );

    if (sourceType ==
        FileSystemEntityType.notFound) {
      throw Exception(
        'O item não existe mais.',
      );
    }

    final targetType =
        await FileSystemEntity.type(
      physicalTarget,
      followLinks: false,
    );

    if (targetType !=
        FileSystemEntityType.notFound) {
      throw Exception(
        'Já existe um item com esse nome.',
      );
    }

    final source =
        FileSystemEntity.isFileSync(
      physicalSource,
    )
        ? File(physicalSource)
        : Directory(physicalSource);

    await source.rename(
      physicalTarget,
    );

    if (_clipboardPath == sourcePath) {
      _clipboardPath =
          targetPath;
    }

    return targetPath;
  }

  // ---------------------------------------------------------------------------
  // DELETAR
  // ---------------------------------------------------------------------------

  Future<void> delete(
    String targetPath,
  ) async {
    final physicalPath =
        await _pathService.toPhysicalPath(
      targetPath,
    );

    final type =
        await FileSystemEntity.type(
      physicalPath,
      followLinks: false,
    );

    if (type ==
        FileSystemEntityType.notFound) {
      throw Exception(
        'O item não existe mais.',
      );
    }

    if (type ==
        FileSystemEntityType.directory) {
      await Directory(
        physicalPath,
      ).delete(
        recursive: true,
      );
    } else {
      await File(
        physicalPath,
      ).delete();
    }

    if (_clipboardPath == targetPath ||
        (_clipboardPath != null &&
            targetPath.startsWith(
              '${_clipboardPath!}/',
            ))) {
      clearClipboard();
    }
  }

  // ---------------------------------------------------------------------------
  // COPIAR
  // ---------------------------------------------------------------------------

  Future<void> copy(
    String sourcePath,
  ) async {
    final physicalSource =
        await _pathService.toPhysicalPath(
      sourcePath,
    );

    final type =
        await FileSystemEntity.type(
      physicalSource,
      followLinks: false,
    );

    if (type ==
        FileSystemEntityType.notFound) {
      throw Exception(
        'O item não existe mais.',
      );
    }

    if (type ==
        FileSystemEntityType.file) {
      _clipboardPath =
          sourcePath;

      _clipboardIsDirectory =
          false;

      return;
    }

    if (type ==
        FileSystemEntityType.directory) {
      _clipboardPath =
          sourcePath;

      _clipboardIsDirectory =
          true;

      return;
    }

    throw Exception(
      'Tipo de item desconhecido.',
    );
  }

  // ---------------------------------------------------------------------------
  // COLAR
  // ---------------------------------------------------------------------------

  Future<String> paste(
    String destinationDirectory,
  ) async {
    final sourcePath =
        _clipboardPath;

    if (sourcePath == null ||
        sourcePath.trim().isEmpty) {
      throw Exception(
        'Não há nenhum item copiado.',
      );
    }

    final physicalSource =
        await _pathService.toPhysicalPath(
      sourcePath,
    );

    final physicalDestination =
        await _pathService.toPhysicalPath(
      destinationDirectory,
    );

    final sourceType =
        await FileSystemEntity.type(
      physicalSource,
      followLinks: false,
    );

    if (sourceType ==
        FileSystemEntityType.notFound) {
      throw Exception(
        'O item copiado não existe mais.',
      );
    }

    final destination =
        Directory(
      physicalDestination,
    );

    if (!await destination.exists()) {
      throw Exception(
        'A pasta de destino não existe.',
      );
    }

    final name =
        p.basename(sourcePath);

    final targetPath =
        _joinPath(
      destinationDirectory,
      name,
    );

    final physicalTarget =
        p.join(
      physicalDestination,
      name,
    );

    final targetType =
        await FileSystemEntity.type(
      physicalTarget,
      followLinks: false,
    );

    if (targetType !=
        FileSystemEntityType.notFound) {
      throw Exception(
        "Já existe um item chamado '$name' "
        'na pasta de destino.',
      );
    }

    if (sourceType ==
        FileSystemEntityType.directory) {
      if (_isSamePathOrChild(
        sourcePath,
        destinationDirectory,
      )) {
        throw Exception(
          'Não é possível colar uma pasta dentro dela mesma.',
        );
      }

      await _copyDirectory(
        Directory(physicalSource),
        Directory(physicalTarget),
      );
    } else if (sourceType ==
        FileSystemEntityType.file) {
      await File(
        physicalSource,
      ).copy(
        physicalTarget,
      );
    } else {
      throw Exception(
        'Não é possível copiar este tipo de item.',
      );
    }

    return targetPath;
  }

  // ---------------------------------------------------------------------------
  // CLIPBOARD
  // ---------------------------------------------------------------------------

  bool get hasClipboardItem =>
      _clipboardPath != null &&
      _clipboardPath!.trim().isNotEmpty;

  bool get clipboardIsDirectory =>
      _clipboardIsDirectory;

  String? get clipboardPath =>
      _clipboardPath;

  void clearClipboard() {
    _clipboardPath = null;
    _clipboardIsDirectory = false;
  }

  // ---------------------------------------------------------------------------
  // IMPORTAR ARQUIVO
  // ---------------------------------------------------------------------------

  Future<String?> importFile(
    String destinationDirectory,
  ) async {
    final selectedFile =
        await FilePicker.pickFile();

    if (selectedFile == null) {
      return null;
    }

    final sourcePath =
        selectedFile.path;

    if (sourcePath == null ||
        sourcePath.trim().isEmpty) {
      throw Exception(
        'Não foi possível obter o caminho do arquivo selecionado.',
      );
    }

    final fileName =
        selectedFile.name.trim();

    if (fileName.isEmpty) {
      throw Exception(
        'Não foi possível obter o nome do arquivo selecionado.',
      );
    }

    final physicalDestination =
        await _pathService.toPhysicalPath(
      destinationDirectory,
    );

    final destination =
        Directory(
      physicalDestination,
    );

    if (!await destination.exists()) {
      throw Exception(
        'A pasta de destino não existe.',
      );
    }

    final physicalTarget =
        p.join(
      physicalDestination,
      fileName,
    );

    if (await File(physicalTarget).exists() ||
        await Directory(physicalTarget)
            .exists()) {
      throw Exception(
        "Já existe um item com o nome '$fileName' no destino.",
      );
    }

    await File(
      sourcePath,
    ).copy(
      physicalTarget,
    );

    return fileName;
  }

  // ---------------------------------------------------------------------------
  // IMPORTAR PASTA
  // ---------------------------------------------------------------------------

  Future<String?> importDirectory(
    String destinationDirectory,
  ) async {
    final selectedDirectory =
        await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecionar pasta',
    );

    if (selectedDirectory == null ||
        selectedDirectory.trim().isEmpty) {
      return null;
    }

    final sourceDirectory =
        Directory(
      selectedDirectory.trim(),
    );

    if (!await sourceDirectory.exists()) {
      throw Exception(
        'A pasta selecionada não está acessível.',
      );
    }

    final directoryName =
        p.basename(
      p.normalize(
        sourceDirectory.path,
      ),
    );

    if (directoryName.isEmpty ||
        directoryName == '/' ||
        directoryName == '.') {
      throw Exception(
        'Não foi possível obter o nome da pasta selecionada.',
      );
    }

    final physicalDestination =
        await _pathService.toPhysicalPath(
      destinationDirectory,
    );

    final destination =
        Directory(
      physicalDestination,
    );

    if (!await destination.exists()) {
      throw Exception(
        'A pasta de destino não existe.',
      );
    }

    final physicalTarget =
        p.join(
      physicalDestination,
      directoryName,
    );

    if (await File(physicalTarget).exists() ||
        await Directory(physicalTarget)
            .exists()) {
      throw Exception(
        "Já existe um item chamado '$directoryName' no destino.",
      );
    }

    await _copyDirectory(
      sourceDirectory,
      Directory(physicalTarget),
    );

    return directoryName;
  }

  // ---------------------------------------------------------------------------
  // EXPORTAR
  // ---------------------------------------------------------------------------

  Future<String?> export(
    String sourcePath,
  ) async {
    final physicalSource =
        await _pathService.toPhysicalPath(
      sourcePath,
    );

    final type =
        await FileSystemEntity.type(
      physicalSource,
      followLinks: false,
    );

    if (type ==
        FileSystemEntityType.notFound) {
      throw Exception(
        'O item não existe mais.',
      );
    }

    final baseName =
        p.basename(sourcePath);

    if (type ==
        FileSystemEntityType.file) {
      final bytes =
          await File(
        physicalSource,
      ).readAsBytes();

      final destination =
          await FilePicker.saveFile(
        dialogTitle: 'Exportar arquivo',
        fileName: baseName,
        bytes: bytes,
      );

      if (destination == null) {
        return null;
      }

      return destination.toString();
    }

    if (type ==
        FileSystemEntityType.directory) {
      final archiveBytes =
          await _createTarGzFromDirectory(
        Directory(physicalSource),
      );

      final destination =
          await FilePicker.saveFile(
        dialogTitle: 'Exportar pasta',
        fileName:
            '$baseName.tar.gz',
        bytes: archiveBytes,
      );

      if (destination == null) {
        return null;
      }

      return destination.toString();
    }

    throw Exception(
      'Não é possível exportar este tipo de item.',
    );
  }

  // ---------------------------------------------------------------------------
  // COPIAR DIRETÓRIO
  // ---------------------------------------------------------------------------

  Future<void> _copyDirectory(
    Directory source,
    Directory target,
  ) async {
    if (!await source.exists()) {
      throw Exception(
        'A pasta de origem não existe.',
      );
    }

    if (await target.exists()) {
      throw Exception(
        'A pasta de destino já existe.',
      );
    }

    await target.create(
      recursive: true,
    );

    await for (final entity
        in source.list(
      followLinks: false,
    )) {
      final name =
          p.basename(entity.path);

      final targetPath =
          p.join(
        target.path,
        name,
      );

      if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory(targetPath),
        );
      } else if (entity is File) {
        await entity.copy(
          targetPath,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CRIAR TAR.GZ PARA EXPORTAÇÃO
  // ---------------------------------------------------------------------------

  Future<Uint8List> _createTarGzFromDirectory(
    Directory sourceDirectory,
  ) async {
    final archive =
        Archive();

    final rootName =
        p.basename(
      p.normalize(
        sourceDirectory.path,
      ),
    );

    await _addDirectoryToTarArchive(
      archive,
      sourceDirectory,
      sourceDirectory.path,
      rootName,
    );

    final tarBytes =
        TarEncoder().encode(
      archive,
    );

    final gzipBytes =
        GZipEncoder().encode(
      tarBytes,
    );

    return Uint8List.fromList(
      gzipBytes,
    );
  }

  Future<void> _addDirectoryToTarArchive(
    Archive archive,
    Directory directory,
    String rootPath,
    String archiveRoot,
  ) async {
    await for (final entity
        in directory.list(
      followLinks: false,
    )) {
      final relativePath =
          p.relative(
        entity.path,
        from: rootPath,
      );

      final archivePath =
          p.posix.join(
        archiveRoot,
        relativePath
            .split(p.separator)
            .join('/'),
      );

      if (entity is Directory) {
        archive.addFile(
          ArchiveFile(
            '$archivePath/',
            0,
            <int>[],
          ),
        );

        await _addDirectoryToTarArchive(
          archive,
          entity,
          rootPath,
          archiveRoot,
        );
      } else if (entity is File) {
        final bytes =
            await entity.readAsBytes();

        archive.addFile(
          ArchiveFile(
            archivePath,
            bytes.length,
            bytes,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITÁRIOS
  // ---------------------------------------------------------------------------

  bool _isSamePathOrChild(
    String parent,
    String child,
  ) {
    final normalizedParent =
        p.normalize(parent);

    final normalizedChild =
        p.normalize(child);

    if (normalizedParent ==
        normalizedChild) {
      return true;
    }

    return normalizedChild.startsWith(
      '$normalizedParent/',
    );
  }

  String _joinPath(
    String parent,
    String child,
  ) {
    if (parent.endsWith('/')) {
      return '$parent$child';
    }

    return '$parent/$child';
  }

  String _validateName(
    String value,
    String description,
  ) {
    final name =
        value.trim();

    if (name.isEmpty) {
      throw Exception(
        'Informe um $description.',
      );
    }

    if (name == '.' ||
        name == '..') {
      throw Exception(
        'O $description informado não é válido.',
      );
    }

    if (name.contains('/') ||
        name.contains('\\')) {
      throw Exception(
        'O $description não pode conter "/" ou "\\".',
      );
    }

    return name;
  }
}

// =============================================================================
// MODELOS INTERNOS PARA CONSTRUÇÃO DA ÁRVORE
// =============================================================================

abstract class _TreeNode {
  final String name;
  final String path;

  _TreeNode({
    required this.name,
    required this.path,
  });

  EditorFileNode toNode();
}

class _TreeDirectory extends _TreeNode {
  final List<_TreeNode> children =
      <_TreeNode>[];

  _TreeDirectory({
    required super.name,
    required super.path,
  });

  @override
  EditorFileNode toNode() {
    final sortedChildren =
        <_TreeNode>[
      ...children,
    ];

    sortedChildren.sort(
      (a, b) {
        if (a is _TreeDirectory &&
            b is! _TreeDirectory) {
          return -1;
        }

        if (a is! _TreeDirectory &&
            b is _TreeDirectory) {
          return 1;
        }

        return a.name
            .toLowerCase()
            .compareTo(
              b.name.toLowerCase(),
            );
      },
    );

    return EditorFileNode(
      name: name,
      path: path,
      type:
          EditorFileNodeType.directory,
      children: sortedChildren
          .map(
            (child) => child.toNode(),
          )
          .toList(),
    );
  }
}

class _TreeFile extends _TreeNode {
  _TreeFile({
    required super.name,
    required super.path,
  });

  @override
  EditorFileNode toNode() {
    return EditorFileNode(
      name: name,
      path: path,
      type:
          EditorFileNodeType.file,
    );
  }
}