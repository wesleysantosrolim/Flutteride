enum EditorFileNodeType {
  directory,
  file,
}

class EditorFileNode {
  final String name;
  final String path;
  final EditorFileNodeType type;
  final List<EditorFileNode> children;

  const EditorFileNode({
    required this.name,
    required this.path,
    required this.type,
    this.children = const [],
  });

  bool get isDirectory =>
      type == EditorFileNodeType.directory;

  bool get isFile =>
      type == EditorFileNodeType.file;
}