import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

/// Test-only state owner: publishes immutable snapshots via a normal rebuild.
class PaginationTestHost<T> extends ValueNotifier<PaginatedState<T>> {
  PaginationTestHost({List<T> items = const []})
    : super(PaginatedState<T>(items: items)) {
    addTearDown(dispose);
  }

  final controller = PaginatedController();

  Widget build(Widget Function() builder) => ValueListenableBuilder(
    valueListenable: this,
    builder: (_, _, _) => builder(),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
