import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  testWidgets('No Internet screen shows the requested offline guidance',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoInternetScreen(onRefresh: () async => false),
      ),
    );

    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('Connect to the internet'), findsOneWidget);
    expect(
      find.text(
        'When your internet connection is restored: Explore various movies, TV series and more',
      ),
      findsOneWidget,
    );
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Open Wi-Fi Settings'), findsOneWidget);
  });
}
