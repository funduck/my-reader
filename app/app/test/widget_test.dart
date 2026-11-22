import 'package:flutter_test/flutter_test.dart';
import 'package:my_reader_app/main.dart';

void main() {
  testWidgets('shows the My reader screen', (tester) async {
    await tester.pumpWidget(const MyReaderApp());
    expect(find.text('My reader'), findsOneWidget);
  });
}
