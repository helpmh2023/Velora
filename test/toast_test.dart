import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velora/widgets/toast.dart';

void main() {
  testWidgets('a new message replaces the old one instead of overlapping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showToast(context, 'Starting pre-buffer: Episode 20');
                showToast(context, 'Pre-buffering Episode 20.');
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Starting pre-buffer: Episode 20'), findsNothing);
    expect(find.text('Pre-buffering Episode 20.'), findsOneWidget);

    // It goes away by itself.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Pre-buffering Episode 20.'), findsNothing);
  });
}
