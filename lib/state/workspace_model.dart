import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';

class FileNode {
  FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    List<FileNode>? children,
  }) : children = children ?? <FileNode>[];

  String name;
  String path;
  bool isDir;
  List<FileNode> children;

  bool get isPython => !isDir && name.endsWith('.py');
}

class OpenBuffer {
  OpenBuffer(this.controller, this.savedText);

  final CodeLineEditingController controller;
  String savedText;

  bool get isDirty => controller.text != savedText;
}

/// The user's workspace: a real folder tree under the app's documents
/// directory, with editor buffers for open files.
class WorkspaceModel extends ChangeNotifier {
  String root = '';
  List<FileNode> tree = <FileNode>[];
  final Map<String, OpenBuffer> buffers = <String, OpenBuffer>{};
  final List<String> openTabs = <String>[];
  String? activePath;
  bool treeExpanded = true;
  bool focusMode = false;

  void setFocusMode(bool value) {
    focusMode = value;
    notifyListeners();
  }

  bool get hasActive => activePath != null && buffers.containsKey(activePath);

  OpenBuffer? get activeBuffer => activePath == null ? null : buffers[activePath];

  CodeLineEditingController? controllerFor(String? path) =>
      path == null ? null : buffers[path]?.controller;

  String textOf(String? path) =>
      path == null ? '' : (buffers[path]?.controller.text ?? '');

  bool isDirty(String path) => buffers[path]?.isDirty ?? false;

  int get dirtyCount =>
      buffers.entries.where((e) => e.value.isDirty).length;

  // ---------------------------------------------------------------------

  Future<void> init() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    root = '${docs.path}${Platform.pathSeparator}workspace';
    final Directory workspace = Directory(root);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
      _seedWorkspace(root);
    }
    await refresh();
    final String? firstPy = _firstPythonFile(tree);
    if (firstPy != null) {
      await openFile(firstPy);
    }
  }

  void _seedWorkspace(String rootPath) {
    _write('$rootPath/hello.py', '''# Welcome to PyForge! 🐍
# A full Python IDE that lives on your phone.
# Tap the ▶ button to run this file.

name = "world"
print(f"Hello, {name}!")

for i in range(5):
    print(i, "squared is", i * i)

# TODO: change the greeting and run again
# FIXME: try removing this line to see the error lens
''');
    _write('$rootPath/learning/variables.py', '''# Lesson 1 playground: variables and types
age = 12          # int
height = 1.52     # float
nickname = "Byte"  # str
is_coder = True    # bool

print(age, height, nickname, is_coder)
''');
    Directory('$root/learning').createSync(recursive: true);
  }

  void _write(String path, String content) {
    final File file = File(path);
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String? _firstPythonFile(List<FileNode> nodes) {
    for (final FileNode node in nodes) {
      if (node.isDir) {
        final String? found = _firstPythonFile(node.children);
        if (found != null) return found;
      } else if (node.isPython) {
        return node.path;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    tree = await _buildTree(root);
    // Drop tabs for deleted files.
    openTabs.removeWhere((String p) => !File(p).existsSync());
    buffers.removeWhere((String p, OpenBuffer _) => !File(p).existsSync());
    if (activePath != null && !openTabs.contains(activePath)) {
      activePath = openTabs.isNotEmpty ? openTabs.last : null;
    }
    notifyListeners();
  }

  Future<List<FileNode>> _buildTree(String path) async {
    final List<FileNode> nodes = <FileNode>[];
    final List<FileSystemEntity> entities =
        Directory(path).listSync(followLinks: false).toList()
          ..sort((FileSystemEntity a, FileSystemEntity b) {
            final bool aDir = a is Directory;
            final bool bDir = b is Directory;
            if (aDir != bDir) return aDir ? -1 : 1;
            return a.path.compareTo(b.path);
          });
    for (final FileSystemEntity entity in entities) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        nodes.add(FileNode(
          name: name,
          path: entity.path,
          isDir: true,
          children: await _buildTree(entity.path),
        ));
      } else if (entity is File) {
        nodes.add(FileNode(name: name, path: entity.path, isDir: false));
      }
    }
    return nodes;
  }

  // ---------------------------------------------------------------------

  Future<void> openFile(String path) async {
    if (!path.endsWith('.py') && !path.endsWith('.txt')) return;
    if (!buffers.containsKey(path)) {
      final String text = File(path).existsSync()
          ? await File(path).readAsString()
          : '';
      buffers[path] = OpenBuffer(CodeLineEditingController.fromText(text), text);
      openTabs.add(path);
    }
    activePath = path;
    notifyListeners();
  }

  void closeTab(String path) {
    buffers.remove(path);
    openTabs.remove(path);
    if (activePath == path) {
      activePath = openTabs.isNotEmpty ? openTabs.last : null;
    }
    notifyListeners();
  }

  Future<void> saveActive() async {
    final String? path = activePath;
    if (path == null) return;
    final OpenBuffer? buffer = buffers[path];
    if (buffer == null) return;
    await File(path).writeAsString(buffer.controller.text);
    buffer.savedText = buffer.controller.text;
    notifyListeners();
  }

  Future<void> saveAll() async {
    for (final MapEntry<String, OpenBuffer> entry in buffers.entries) {
      await File(entry.key).writeAsString(entry.value.controller.text);
      entry.value.savedText = entry.value.controller.text;
    }
    notifyListeners();
  }

  /// Creates a file (or folder when [asFolder]) inside [parentDir].
  /// Returns the new path, or null when the name is invalid/taken.
  Future<String?> createNode(String parentDir, String name,
      {bool asFolder = false}) async {
    final String clean = name.trim().replaceAll(RegExp(r'[/\\]'), '_');
    if (clean.isEmpty) return null;
    final String path = '$parentDir${Platform.pathSeparator}$clean';
    if (File(path).existsSync() || Directory(path).existsSync()) return null;
    if (asFolder) {
      Directory(path).createSync(recursive: true);
    } else {
      File(path).createSync(recursive: true);
    }
    await refresh();
    return path;
  }

  Future<void> deleteNode(String path) async {
    if (path == root) return;
    if (Directory(path).existsSync()) {
      Directory(path).deleteSync(recursive: true);
    } else if (File(path).existsSync()) {
      File(path).deleteSync();
    }
    await refresh();
  }

  Future<String?> renameNode(String oldPath, String newName) async {
    final String clean = newName.trim().replaceAll(RegExp(r'[/\\]'), '_');
    if (clean.isEmpty) return null;
    final String parent = oldPath.substring(0, oldPath.lastIndexOf(Platform.pathSeparator));
    final String newPath = '$parent${Platform.pathSeparator}$clean';
    if (newPath == oldPath) return null;
    if (File(newPath).existsSync() || Directory(newPath).existsSync()) {
      return null;
    }
    if (File(oldPath).existsSync()) {
      File(oldPath).renameSync(newPath);
    } else if (Directory(oldPath).existsSync()) {
      Directory(oldPath).renameSync(newPath);
    }
    // Remap every open buffer under the renamed path (folder renames move
    // all descendant buffers too).
    final List<String> keys = buffers.keys.toList();
    for (final String key in keys) {
      String mapped = key;
      if (key == oldPath) {
        mapped = newPath;
      } else if (key.startsWith('$oldPath${Platform.pathSeparator}')) {
        mapped = '$newPath${key.substring(oldPath.length)}';
      }
      if (mapped != key) {
        final OpenBuffer buffer = buffers.remove(key)!;
        buffers[mapped] = buffer;
        final int index = openTabs.indexOf(key);
        if (index >= 0) openTabs[index] = mapped;
        if (activePath == key) activePath = mapped;
      }
    }
    await refresh();
    return newPath;
  }

  void toggleTree() {
    treeExpanded = !treeExpanded;
    notifyListeners();
  }

  /// Inserts [snippet] at the caret of the active buffer.
  void insertSnippet(String snippet) {
    final CodeLineEditingController? controller = controllerFor(activePath);
    if (controller == null) return;
    controller.replaceSelection(snippet);
    notifyListeners();
  }

  /// Replaces the whole active buffer (used by the AI fix-apply flow).
  void insertReplacement(String newText) {
    final CodeLineEditingController? controller = controllerFor(activePath);
    if (controller == null) return;
    controller.text = newText;
    notifyListeners();
  }

  /// Replaces the buffer for a specific path (AI fix applies to the file
  /// that was submitted, even if the user switched tabs meanwhile).
  void setTextFor(String path, String newText) {
    final CodeLineEditingController? controller = controllerFor(path);
    if (controller == null) return;
    controller.text = newText;
    notifyListeners();
  }
}
