import 'package:flutter_code_agent/src/feature/file_mention/data/project_files_repository.dart';
import 'package:flutter_code_agent/src/feature/workspace/controller/project_files_controller.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ProjectFiles implements IProjectFilesRepository {
  final List<String> roots = <String>[];

  @override
  Future<List<String>> list(String root, {int limit = 5000}) async {
    roots.add(root);
    return <String>['lib/main.dart', 'pubspec.yaml'];
  }

  @override
  Future<List<String>> insideProject(String root, List<String> paths) async => paths;
}

void main() {
  test('list asks the repository for the files of the root', () async {
    final repository = _ProjectFiles();
    final controller = ProjectFilesController(repository: repository);

    expect(await controller.list('/p'), <String>['lib/main.dart', 'pubspec.yaml']);
    expect(await controller.list('/q'), hasLength(2));
    expect(repository.roots, <String>['/p', '/q']);
  });
}
