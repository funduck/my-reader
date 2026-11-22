import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_spike/main.dart' as app;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll 15k-word chapter', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    final list = find.byType(ScrollablePositionedList);
    await binding.traceAction(() async {
      for (var i = 0; i < 40; i++) {
        await tester.fling(list, const Offset(0, -700), 2500);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 20; i++) {
        await tester.fling(list, const Offset(0, 700), 2500);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'scroll_timeline');
  });
}
