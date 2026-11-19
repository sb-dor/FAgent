import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_file_bars.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('an image is decoded at the pane size, not at full resolution', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      testApp(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 300, child: CodeImageView(path: '/p/logo.png')),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, lessThanOrEqualTo(400 * 2));
  });
}
