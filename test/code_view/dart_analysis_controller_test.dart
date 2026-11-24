import 'package:flutter_code_agent/_core/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/_core/dart_analysis/models/lsp_location.dart';
import 'package:flutter_code_agent/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/code_view/controller/dart_analysis_controller.dart';
import 'package:flutter_code_agent/code_view/models/dart_analysis_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../support/memory_code_files_repository.dart';
import '../support/memory_dart_analysis_repository.dart';

void main() {
  const path = '/p/lib/main.dart';
  late MemoryCodeFilesRepository files;
  late MemoryDartAnalysisRepository repository;
  late DartAnalysisController controller;

  setUp(() {
    files = MemoryCodeFilesRepository(files: <String, String>{path: 'void  main( ){}\n'});
    repository = MemoryDartAnalysisRepository();
    controller = DartAnalysisController(repository: repository);
  });

  test('status follows the repository', () {
    expect(controller.status.value, const DartAnalysisStatus.ready());

    repository.status.value = const DartAnalysisStatus.unavailable(reason: 'dart not found');

    expect(controller.status.value, const DartAnalysisStatus.unavailable(reason: 'dart not found'));
  });

  test('restart restarts the repository', () async {
    await controller.restart();
    await controller.restart();

    expect(repository.restarts, 2);
  });

  test('format applies the edits of the repository to the document', () async {
    repository.onFormat = (path, text) => <LspTextEdit>[
      const LspTextEdit(
        range: LspRange(
          start: LspPosition(line: 0, character: 4),
          end: LspPosition(line: 0, character: 5),
        ),
        newText: '',
      ),
    ];
    final document = await CodeDocument.open(path, files: files);
    addTearDown(document.dispose);

    await controller.format(document);

    expect(document.editing.text, 'void main( ){}\n');
  });

  test('completionFor asks the repository about the document', () async {
    repository.onComplete = (path, text, position) => const <DartCompletion>[];
    final document = await CodeDocument.open(path, files: files);
    addTearDown(document.dispose);
    final completion = controller.completionFor(document);
    addTearDown(completion.dispose);

    document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
    document.editing.replaceSelection('m');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(repository.calls.map((call) => (call.$1, call.$2)), contains(('complete', path)));
  });

  test('navigationFor asks the repository about the document', () async {
    final document = await CodeDocument.open(path, files: files);
    addTearDown(document.dispose);
    final navigation = controller.navigationFor(document);
    addTearDown(navigation.dispose);
    const declaration = LspLocation(
      path: '/p/lib/other.dart',
      range: LspRange(
        start: LspPosition(line: 3, character: 0),
        end: LspPosition(line: 3, character: 4),
      ),
    );
    repository.onDefinition = (path, text, position) => <LspLocation>[declaration];
    document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 7);

    final jump = await navigation.definitionAtCaret();

    expect(jump?.name, 'main');
    expect(jump?.locations, <LspLocation>[declaration]);
  });
}
