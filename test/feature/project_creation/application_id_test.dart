import 'dart:io';

import 'package:flutter_code_agent/src/feature/project_creation/data/application_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('identifiers', () {
    test('the org is every segment but the last', () {
      expect(applicationIdOrg('com.example.shop'), 'com.example');
      expect(applicationIdOrg('tj.avera.pos.app'), 'tj.avera.pos');
      expect(applicationIdOrg('com.shop'), 'com');
    });

    test('Android keeps the name, Apple camelCases it and drops underscores', () {
      expect(androidIdentifier('com.example', 'avera_booking'), 'com.example.avera_booking');
      expect(appleIdentifier('com.example', 'avera_booking'), 'com.example.averaBooking');
      expect(appleIdentifier('com.my_co', 'shop'), 'com.myco.shop');
      expect(appleIdentifier('com.example', 'shop'), 'com.example.shop');
    });

    test('the pattern takes two or more lowercase segments', () {
      for (final good in const <String>['com.example.shop', 'tj.avera_pos.app2', 'com.shop']) {
        expect(applicationIdPattern.hasMatch(good), isTrue, reason: good);
      }
      for (final bad in const <String>[
        'shop',
        'com.example.',
        'Com.Example.Shop',
        'com.1x.shop',
        'com..shop',
        'com.example.my-shop',
      ]) {
        expect(applicationIdPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('applyApplicationId', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('application_id_'));
    tearDown(() => root.deleteSync(recursive: true));

    File file(String relative) => File(p.joinAll(<String>[root.path, ...relative.split('/')]));

    void write(String relative, String text) {
      file(relative)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    /// The files `flutter create --org com.example --project-name avera_booking` writes, cut down.
    void flutterCreate() {
      write('android/app/build.gradle.kts', '''
android {
    namespace = "com.example.avera_booking"
    defaultConfig {
        applicationId = "com.example.avera_booking"
    }
}
''');
      write(
        'android/app/src/main/kotlin/com/example/avera_booking/MainActivity.kt',
        'package com.example.avera_booking\n\nclass MainActivity : FlutterActivity()\n',
      );
      write('ios/Runner.xcodeproj/project.pbxproj', '''
				PRODUCT_BUNDLE_IDENTIFIER = com.example.averaBooking;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.averaBooking.RunnerTests;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.averaBookingPro;
''');
      write('macos/Runner/Configs/AppInfo.xcconfig', '''
PRODUCT_NAME = avera_booking
PRODUCT_BUNDLE_IDENTIFIER = com.example.averaBooking
PRODUCT_COPYRIGHT = Copyright © 2026 com.example. All rights reserved.
''');
      write('linux/CMakeLists.txt', 'set(APPLICATION_ID "com.example.avera_booking")\n');
    }

    Future<List<String>> apply(String applicationId) => applyApplicationId(
      root.path,
      org: 'com.example',
      package: 'avera_booking',
      applicationId: applicationId,
    );

    test('writes the ID on every platform and moves MainActivity', () async {
      flutterCreate();

      final changed = await apply('tj.avera.booking');

      expect(
        changed,
        unorderedEquals(<String>[
          'android/app/build.gradle.kts',
          'android/app/src/main/kotlin/tj/avera/booking/MainActivity.kt',
          'linux/CMakeLists.txt',
          'ios/Runner.xcodeproj/project.pbxproj',
          'macos/Runner/Configs/AppInfo.xcconfig',
        ]),
      );
      final gradle = file('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('namespace = "tj.avera.booking"'));
      expect(gradle, contains('applicationId = "tj.avera.booking"'));
      expect(
        file('android/app/src/main/kotlin/tj/avera/booking/MainActivity.kt').readAsStringSync(),
        startsWith('package tj.avera.booking\n'),
      );
      expect(Directory(p.join(root.path, 'android/app/src/main/kotlin/com')).existsSync(), isFalse);
      expect(
        file('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        allOf(
          contains('PRODUCT_BUNDLE_IDENTIFIER = tj.avera.booking;'),
          contains('PRODUCT_BUNDLE_IDENTIFIER = tj.avera.booking.RunnerTests;'),
          // Another ID that only starts the same is left alone.
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.averaBookingPro;'),
        ),
      );
      expect(
        file('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
        allOf(
          contains('PRODUCT_BUNDLE_IDENTIFIER = tj.avera.booking\n'),
          contains('Copyright © 2026 com.example.'),
        ),
      );
      expect(
        file('linux/CMakeLists.txt').readAsStringSync(),
        'set(APPLICATION_ID "tj.avera.booking")\n',
      );
    });

    test('the ID flutter create made changes nothing', () async {
      flutterCreate();

      expect(await apply('com.example.avera_booking'), isEmpty);
      expect(
        file('android/app/src/main/kotlin/com/example/avera_booking/MainActivity.kt').existsSync(),
        isTrue,
      );
    });

    test('Apple gets the ID without underscores', () async {
      flutterCreate();

      await apply('com.my_co.pos_app');

      expect(
        file('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.myco.posApp;'),
      );
      expect(
        file('android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.my_co.pos_app"'),
      );
    });

    test('a Java MainActivity and missing platforms', () async {
      write('android/app/build.gradle', '''
    namespace "com.example.avera_booking"
    applicationId "com.example.avera_booking"
''');
      write(
        'android/app/src/main/java/com/example/avera_booking/MainActivity.java',
        'package com.example.avera_booking;\n',
      );

      await apply('com.example.shop');

      // Groovy without `=`: the quoted ID is replaced wherever it stands.
      expect(
        file('android/app/build.gradle').readAsStringSync(),
        '    namespace "com.example.shop"\n    applicationId "com.example.shop"\n',
      );
      expect(
        file('android/app/src/main/java/com/example/shop/MainActivity.java').readAsStringSync(),
        'package com.example.shop;\n',
      );
      // `com/example` still holds the new package.
      expect(
        Directory(p.join(root.path, 'android/app/src/main/java/com/example/avera_booking'))
            .existsSync(),
        isFalse,
      );
    });
  });
}
