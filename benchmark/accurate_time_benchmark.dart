import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:ntp_dart/ntp_dart.dart';

class AccurateTimeBenchmark extends AsyncBenchmarkBase {
  AccurateTimeBenchmark() : super('AccurateTime.now');

  @override
  Future<void> run() => AccurateTime.now();
}

Future<void> main() async {
  await AccurateTime.now();
  final benchmark = AccurateTimeBenchmark();
  await benchmark.report();
}
