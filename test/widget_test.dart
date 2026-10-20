import 'package:flutter_test/flutter_test.dart';

import 'package:flutteride/app.dart';

void main() {
  testWidgets('FlutterIDE inicia corretamente', (tester) async {
    await tester.pumpWidget(const FlutterIdeApp());

    expect(find.text('FlutterIDE'), findsWidgets);
  });
}