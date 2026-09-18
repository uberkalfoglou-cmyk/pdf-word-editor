import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists signature/stamp PNGs — already background-removed, alpha-
/// transparent, exactly as they land on the page — to a folder inside the
/// app's own documents directory, so a signature drawn or picked once can
/// be reused across pages and documents later without redrawing or
/// re-picking it every single time. Deliberately just files on disk, no
/// database: there's no metadata worth tracking beyond "here's a PNG",
/// and a plain file listing is trivial to show as a picker grid.
class SignatureStore {
  static const _dirName = 'signatures';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves [pngBytes] as a new signature file and returns it. Filenames
  /// are timestamp-based so [list] can sort newest-first by name alone.
  Future<File> save(Uint8List pngBytes) async {
    final dir = await _dir();
    final name = 'sig_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$name');
    return file.writeAsBytes(pngBytes, flush: true);
  }

  /// All previously saved signatures, most recently saved first.
  Future<List<File>> list() async {
    final dir = await _dir();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> delete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
