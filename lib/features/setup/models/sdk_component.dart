enum SDKComponentType {
  flutter,
  java,
  androidSdk,
  buildTools,
  platformTools,
  androidPlatform,
  gradle,
  ndk,
  linuxRuntime,
  unknown,
}

enum SDKComponentStatus {
  notSelected,
  selected,
  validating,
  valid,
  invalid,
  installing,
  installed,
  error,
}

class SDKComponent {
  final SDKComponentType type;
  final String name;
  final String description;
  final String? expectedArchitecture;
  final String? expectedFileExtension;

  String? selectedFilePath;
  String? installedPath;

  SDKComponentStatus status;
  double progress;
  String? errorMessage;

  SDKComponent({
    required this.type,
    required this.name,
    required this.description,
    this.expectedArchitecture,
    this.expectedFileExtension,
    this.selectedFilePath,
    this.installedPath,
    this.status = SDKComponentStatus.notSelected,
    this.progress = 0.0,
    this.errorMessage,
  });

  bool get isSelected =>
      selectedFilePath != null &&
      selectedFilePath!.isNotEmpty;

  bool get isInstalled =>
      status == SDKComponentStatus.installed;

  bool get hasError =>
      status == SDKComponentStatus.invalid ||
      status == SDKComponentStatus.error;

  void selectFile(String path) {
    selectedFilePath = path;
    status = SDKComponentStatus.selected;
    errorMessage = null;
    progress = 0.0;
  }

  void startValidation() {
    status = SDKComponentStatus.validating;
    errorMessage = null;
  }

  void markValid() {
    status = SDKComponentStatus.valid;
    errorMessage = null;
  }

  void markInvalid(String message) {
    status = SDKComponentStatus.invalid;
    errorMessage = message;
  }

  void startInstallation() {
    status = SDKComponentStatus.installing;
    errorMessage = null;
    progress = 0.0;
  }

  void updateProgress(double value) {
    progress = value.clamp(0.0, 1.0).toDouble();
  }

  void markInstalled(String path) {
    installedPath = path;
    status = SDKComponentStatus.installed;
    progress = 1.0;
    errorMessage = null;
  }

  void markError(String message) {
    status = SDKComponentStatus.error;
    errorMessage = message;
  }

  String get statusText {
    switch (status) {
      case SDKComponentStatus.notSelected:
        return 'Não selecionado';

      case SDKComponentStatus.selected:
        return 'Arquivo selecionado';

      case SDKComponentStatus.validating:
        return 'Validando...';

      case SDKComponentStatus.valid:
        return 'Arquivo válido';

      case SDKComponentStatus.invalid:
        return 'Arquivo inválido';

      case SDKComponentStatus.installing:
        return 'Instalando...';

      case SDKComponentStatus.installed:
        return 'Instalado';

      case SDKComponentStatus.error:
        return 'Erro';
    }
  }

  void resetSelection() {
    selectedFilePath = null;
    status = SDKComponentStatus.notSelected;
    progress = 0.0;
    errorMessage = null;
  }

  SDKComponent copy() {
    return SDKComponent(
      type: type,
      name: name,
      description: description,
      expectedArchitecture: expectedArchitecture,
      expectedFileExtension: expectedFileExtension,
      selectedFilePath: selectedFilePath,
      installedPath: installedPath,
      status: status,
      progress: progress,
      errorMessage: errorMessage,
    );
  }
}