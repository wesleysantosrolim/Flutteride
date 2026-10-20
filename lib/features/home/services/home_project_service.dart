import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../terminal/services/ubuntu_path_service.dart';
import '../../terminal/services/ubuntu_session_manager.dart';
import '../models/home_project.dart';

class HomeProjectService {
  HomeProjectService({
    UbuntuSessionManager? sessionManager,
    UbuntuPathService? pathService,
  })  : _sessionManager =
            sessionManager ?? UbuntuSessionManager.instance,
        _pathService =
            pathService ?? UbuntuPathService.instance;

  final UbuntuSessionManager _sessionManager;
  final UbuntuPathService _pathService;

  static const String _projectsRoot =
      '/root/projects';

  Future<List<HomeProject>> listProjects() async {
    final physicalProjectsPath =
        await _pathService.toPhysicalPath(
      _projectsRoot,
    );

    final projectsDirectory =
        Directory(physicalProjectsPath);

    if (!await projectsDirectory.exists()) {
      await projectsDirectory.create(
        recursive: true,
      );
    }

    final projects = <HomeProject>[];

    await for (final entity
        in projectsDirectory.list(
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }

      final projectDirectory = entity;

      final pubspecFile = File(
        p.join(
          projectDirectory.path,
          'pubspec.yaml',
        ),
      );

      if (!await pubspecFile.exists()) {
        continue;
      }

      final projectName =
          p.basename(projectDirectory.path);

      final stat =
          await projectDirectory.stat();

      projects.add(
        HomeProject(
          name: projectName,
          path: '$_projectsRoot/$projectName',
          lastModified: stat.modified,
        ),
      );
    }

    projects.sort(
      (a, b) => b.lastModified.compareTo(
        a.lastModified,
      ),
    );

    return projects;
  }

  Future<HomeProjectCreationResult> createProject(
    String projectName,
  ) async {
    final escapedProjectName =
        _shellEscape(projectName);

    final session =
        await _sessionManager.createSession(
      workingDirectory: '/root',
      command: 'bash',
      arguments: [
        '-lc',
        '''
set -e

export HOME=/root
export TMPDIR=/tmp
export PUB_CACHE=/root/.pub-cache
export PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

mkdir -p /tmp
mkdir -p /root/.pub-cache
mkdir -p /root/projects

chmod 1777 /tmp

cd /root/projects

pwd

flutter create $escapedProjectName

PROJECT_PATH="/root/projects/$escapedProjectName"

if [ ! -d "\$PROJECT_PATH" ]; then
  echo ""
  echo "Erro: projeto Flutter não foi encontrado em:"
  echo "\$PROJECT_PATH"
  exit 1
fi

echo ""
echo "Configurando ambiente Android do projeto..."

SETTINGS_FILE="\$PROJECT_PATH/android/settings.gradle.kts"
WRAPPER_FILE="\$PROJECT_PATH/android/gradle/wrapper/gradle-wrapper.properties"

if [ ! -f "\$SETTINGS_FILE" ]; then
  echo ""
  echo "Erro: settings.gradle.kts não encontrado:"
  echo "\$SETTINGS_FILE"
  exit 1
fi

if [ ! -f "\$WRAPPER_FILE" ]; then
  echo ""
  echo "Erro: gradle-wrapper.properties não encontrado:"
  echo "\$WRAPPER_FILE"
  exit 1
fi

sed -i 's/id("com.android.application") version "9.1.0"/id("com.android.application") version "9.2.0"/' "\$SETTINGS_FILE"

sed -i 's/gradle-9.3.1-all.zip/gradle-9.4.1-all.zip/' "\$WRAPPER_FILE"

if ! grep -q 'id("com.android.application") version "9.2.0"' "\$SETTINGS_FILE"; then
  echo ""
  echo "Erro: não foi possível configurar o Android Gradle Plugin 9.2.0."
  exit 1
fi

if ! grep -q 'gradle-9.4.1-all.zip' "\$WRAPPER_FILE"; then
  echo ""
  echo "Erro: não foi possível configurar o Gradle 9.4.1."
  exit 1
fi

echo ""
echo "Configuração Android aplicada:"
echo "  AGP: 9.2.0"
echo "  Gradle: 9.4.1"
echo ""
echo "Projeto Flutter criado e preparado com sucesso."
''',
      ],
      loginShell: false,
    );

    final output = StringBuffer();

    final subscription =
        session.pty.output.listen(
      (data) {
        output.write(
          utf8.decode(data),
        );
      },
    );

    try {
      final exitCode =
          await session.pty.exitCode;

      return HomeProjectCreationResult(
        success: exitCode == 0,
        projectName: projectName,
        output: output.toString().trim(),
        exitCode: exitCode,
      );
    } finally {
      await subscription.cancel();

      if (!session.isClosed) {
        session.kill();
      }
    }
  }

  /// Exclui um projeto Flutter inteiro.
  ///
  /// O caminho recebido deve ser um caminho lógico do Ubuntu,
  /// por exemplo:
  ///
  /// /root/projects/meu_app
  ///
  /// A operação é limitada ao diretório /root/projects.
  Future<void> deleteProject(
    String projectPath,
  ) async {
    final projectName =
        _validateProjectPath(projectPath);

    final physicalPath =
        await _pathService.toPhysicalPath(
      projectPath,
    );

    final projectDirectory =
        Directory(physicalPath);

    if (!await projectDirectory.exists()) {
      throw FileSystemException(
        'Projeto não encontrado.',
        physicalPath,
      );
    }

    await projectDirectory.delete(
      recursive: true,
    );

    // Evita deixar uma mensagem de sucesso para
    // um caminho que não existe mais.
    if (await projectDirectory.exists()) {
      throw FileSystemException(
        'Não foi possível excluir o projeto.',
        physicalPath,
      );
    }

    // Mantém a variável usada para validar o nome
    // explicitamente durante a operação.
    projectName;
  }

  /// Renomeia um projeto Flutter.
  ///
  /// Exemplo:
  ///
  /// /root/projects/meu_app
  /// ->
  /// /root/projects/meu_app_novo
  Future<void> renameProject(
    String projectPath,
    String newName,
  ) async {
    _validateProjectPath(projectPath);

    final normalizedName =
        newName.trim();

    _validateProjectName(
      normalizedName,
    );

    final oldPhysicalPath =
        await _pathService.toPhysicalPath(
      projectPath,
    );

    final oldDirectory =
        Directory(oldPhysicalPath);

    if (!await oldDirectory.exists()) {
      throw FileSystemException(
        'Projeto não encontrado.',
        oldPhysicalPath,
      );
    }

    final newLogicalPath =
        '$_projectsRoot/$normalizedName';

    final newPhysicalPath =
        await _pathService.toPhysicalPath(
      newLogicalPath,
    );

    final newDirectory =
        Directory(newPhysicalPath);

    if (await newDirectory.exists()) {
      throw FileSystemException(
        'Já existe um projeto com o nome "$normalizedName".',
        newPhysicalPath,
      );
    }

    await oldDirectory.rename(
      newPhysicalPath,
    );
  }

  /// Exporta o projeto para um arquivo TAR.GZ.
  ///
  /// Por padrão o arquivo é criado em:
  ///
  /// /storage/emulated/0/Download/
  ///
  /// O caminho retornado é o caminho físico do arquivo
  /// de exportação.
  Future<String> exportProject(
    String projectPath, {
    String? outputDirectory,
  }) async {
    final projectName =
        _validateProjectPath(projectPath);

    final physicalProjectPath =
        await _pathService.toPhysicalPath(
      projectPath,
    );

    final projectDirectory =
        Directory(physicalProjectPath);

    if (!await projectDirectory.exists()) {
      throw FileSystemException(
        'Projeto não encontrado.',
        physicalProjectPath,
      );
    }

    final destination =
        outputDirectory ??
        '/storage/emulated/0/Download';

    final destinationDirectory =
        Directory(destination);

    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(
        recursive: true,
      );
    }

    final archivePath = p.join(
      destination,
      '$projectName.tar.gz',
    );

    final archiveFile =
        File(archivePath);

    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }

    final session =
        await _sessionManager.createSession(
      workingDirectory: '/root',
      command: 'bash',
      arguments: [
        '-lc',
        '''
set -e

PROJECT="/root/projects/${_shellEscape(projectName)}"
OUTPUT="${_shellEscape(archivePath)}"

if [ ! -d "\$PROJECT" ]; then
  echo "Erro: projeto não encontrado:"
  echo "\$PROJECT"
  exit 1
fi

mkdir -p "\$(dirname "\$OUTPUT")"

rm -f "\$OUTPUT"

cd /root/projects

tar -czf "\$OUTPUT" "\$(basename "\$PROJECT")"

if [ ! -f "\$OUTPUT" ]; then
  echo "Erro: arquivo de exportação não foi criado."
  exit 1
fi

echo "\$OUTPUT"
''',
      ],
      loginShell: false,
    );

    final output = StringBuffer();

    final subscription =
        session.pty.output.listen(
      (data) {
        output.write(
          utf8.decode(data),
        );
      },
    );

    try {
      final exitCode =
          await session.pty.exitCode;

      if (exitCode != 0) {
        throw FileSystemException(
          'Não foi possível exportar o projeto.\n'
          '${output.toString().trim()}',
        );
      }

      if (!await archiveFile.exists()) {
        throw FileSystemException(
          'A exportação terminou, mas o arquivo não foi encontrado.',
          archivePath,
        );
      }

      return archivePath;
    } finally {
      await subscription.cancel();

      if (!session.isClosed) {
        session.kill();
      }
    }
  }

  String _validateProjectPath(
    String projectPath,
  ) {
    final normalized =
        p.posix.normalize(projectPath);

    const prefix = '$_projectsRoot/';

    if (!normalized.startsWith(prefix)) {
      throw ArgumentError(
        'Caminho de projeto inválido: $projectPath',
      );
    }

    final projectName =
        normalized.substring(prefix.length);

    if (projectName.isEmpty ||
        projectName.contains('/')) {
      throw ArgumentError(
        'Projeto inválido: $projectPath',
      );
    }

    _validateProjectName(
      projectName,
    );

    return projectName;
  }

  void _validateProjectName(
    String projectName,
  ) {
    if (projectName.isEmpty) {
      throw ArgumentError(
        'O nome do projeto não pode ser vazio.',
      );
    }

    if (projectName == '.' ||
        projectName == '..') {
      throw ArgumentError(
        'Nome de projeto inválido.',
      );
    }

    if (projectName.contains('/') ||
        projectName.contains('\\')) {
      throw ArgumentError(
        'O nome do projeto não pode conter barras.',
      );
    }

    if (!RegExp(
      r'^[a-zA-Z0-9_.-]+$',
    ).hasMatch(projectName)) {
      throw ArgumentError(
        'Nome de projeto inválido. '
        'Use apenas letras, números, "_" , "-" e ".".',
      );
    }
  }

  String _shellEscape(
    String value,
  ) {
    if (value.isEmpty) {
      return "''";
    }

    if (RegExp(
      r'^[a-zA-Z0-9_./:=+-]+$',
    ).hasMatch(value)) {
      return value;
    }

    return "'${value.replaceAll(
      "'",
      "'\\''",
    )}'";
  }
}

class HomeProjectCreationResult {
  final bool success;
  final String projectName;
  final String output;
  final int exitCode;

  const HomeProjectCreationResult({
    required this.success,
    required this.projectName,
    required this.output,
    required this.exitCode,
  });
}