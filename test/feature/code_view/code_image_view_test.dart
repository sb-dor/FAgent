import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_file_bars.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  Future<Image> pumpImage(WidgetTester tester, {required double width}) async {
    await tester.pumpWidget(
      testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 300,
            child: const CodeImageView(path: '/p/logo.png'),
          ),
        ),
      ),
    );
    return tester.widget<Image>(find.byType(Image));
  }

  int? decodedWidth(Image image) => (image.image as ResizeImage).width;

  testWidgets('an image is decoded at the pane size, not at full resolution', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await pumpImage(tester, width: 400);
    expect(image.image, isA<ResizeImage>());
    // The pane is 400 px less 2 × 24 px of padding, at 2 pixels per point: 704, rounded up to a
    // step of 256.
    expect(decodedWidth(image), 768);
  });

  testWidgets('a pane narrower than its padding still decodes at a width of at least 1', (
    tester,
  ) async {
    final image = await pumpImage(tester, width: 40);
    expect(tester.takeException(), isNull);
    expect(decodedWidth(image), greaterThanOrEqualTo(1));
  });

  testWidgets('dragging the divider by a few pixels does not decode the image again', (
    tester,
  ) async {
    final before = decodedWidth(await pumpImage(tester, width: 400));
    final after = decodedWidth(await pumpImage(tester, width: 410));
    expect(after, before);
  });

  testWidgets('a new decode keeps the old image until it is ready', (tester) async {
    final image = await pumpImage(tester, width: 400);
    expect(image.gaplessPlayback, isTrue);
  });
}
