import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_view/main.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
 

  testWidgets('shows URL entry form', (WidgetTester tester) async {
    await tester.pumpWidget(const GyroWebViewApp());

    expect(find.text('Gyro WebView'), findsOneWidget);
    expect(find.text('Open full screen'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('rejects an invalid URL', (WidgetTester tester) async {
    await tester.pumpWidget(const GyroWebViewApp());

    await tester.tap(find.text('Open full screen'));
    await tester.pump();

    expect(find.text('Enter a valid http or https URL'), findsOneWidget);
  });
}