import 'package:flutter_monaco/flutter_monaco.dart';

/// Shared route observer for the example app.
///
/// Register once on [MaterialApp.navigatorObservers] (done in
/// `complete_example.dart`) and pass to [MonacoFocusGuard.modalRouteObserver]
/// in every page that hosts a [MonacoEditor]. The guard uses it to detect
/// dialog/popup pushes and toggle iframe interaction on the web so overlays
/// stay clickable.
final MonacoRouteObserver monacoRouteObserver = MonacoRouteObserver();
