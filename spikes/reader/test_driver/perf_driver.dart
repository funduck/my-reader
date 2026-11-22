import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final timeline = driver.Timeline.fromJson(
      data['scroll_timeline'] as Map<String, dynamic>,
    );
    final summary = driver.TimelineSummary.summarize(timeline);
    await summary.writeTimelineToFile(
      'scroll_timeline',
      pretty: true,
      includeSummary: true,
    );
    final j = summary.summaryJson;
    print(
      'P99 build ms:  ${j['99th_percentile_frame_build_time_millis']}\n'
      'P99 raster ms: ${j['99th_percentile_frame_rasterizer_time_millis']}\n'
      'avg build ms:  ${j['average_frame_build_time_millis']}\n'
      'frames: ${j['frame_count']}  '
      'missed build budget: ${j['missed_frame_build_budget_count']}',
    );
  },
);
