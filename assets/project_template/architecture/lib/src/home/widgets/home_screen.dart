import 'package:flutter/material.dart';
import 'package:{{package}}/src/_core/localization/localization.dart';

/// {@template home_screen}
/// The first screen of the app. Replace it with the real one.
/// {@endtemplate}
class HomeScreen extends StatelessWidget {
  /// {@macro home_screen}
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(localization.appTitle)),
      body: Center(child: Text(localization.homeMessage)),
    );
  }
}
