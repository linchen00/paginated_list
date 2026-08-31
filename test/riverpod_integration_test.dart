import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

final paginationProvider =
    NotifierProvider<TestPaginationNotifier, PaginatedState<int>>(
      TestPaginationNotifier.new,
    );

class TestPaginationNotifier extends Notifier<PaginatedState<int>> {
  @override
  PaginatedState<int> build() => PaginatedState<int>(items: [1]);

  void startRefresh() => state = state.startRefresh();
  void complete(List<int> items) =>
      state = state.refreshCompleted(items: items);
  void noMore() => state = state.loadNoData();
  void resetNoData() => state = state.resetNoData();
  void startLoading() => state = state.startLoading();
  void replace(List<int> items) => state = state.copyWith(items: items);
}

void main() {
  test('Provider 直接发布分页快照，listen 与 select 观察原子结果', () {
    final container = ProviderContainer.test();
    final changes = <(PaginatedState<int>?, PaginatedState<int>)>[];
    final itemChanges = <List<int>>[];
    final refreshingChanges = <bool>[];
    final noMoreChanges = <bool>[];
    container.listen(
      paginationProvider,
      (old, next) => changes.add((old, next)),
    );
    container.listen(
      paginationProvider.select((s) => s.items),
      (_, next) => itemChanges.add(next),
    );
    container.listen(
      paginationProvider.select((s) => s.isRefreshing),
      (_, next) => refreshingChanges.add(next),
    );
    container.listen(
      paginationProvider.select((s) => s.isNoMore),
      (_, next) => noMoreChanges.add(next),
    );
    final notifier = container.read(paginationProvider.notifier);
    final original = container.read(paginationProvider);

    notifier.complete([99]); // 非法转换，连数据也不接受。
    expect(changes, isEmpty);
    notifier.noMore();
    notifier.noMore(); // 重复操作无通知。
    expect(changes, hasLength(1));
    notifier.resetNoData();
    notifier.noMore();
    notifier.startRefresh();
    notifier.startRefresh();
    expect(itemChanges, isEmpty);
    expect(refreshingChanges, [true]);
    final before = container.read(paginationProvider);
    final count = changes.length;
    notifier.complete([2, 3]);
    expect(changes.length, count + 1);
    expect(identical(changes.last.$1, before), isTrue);
    final result = changes.last.$2;
    expect(result.items, [2, 3]);
    expect(result.refreshStatus, RefreshStatus.completed);
    expect(result.loadStatus, LoadStatus.idle);
    expect(result.isNoMore, isFalse);
    expect(itemChanges, [
      [2, 3],
    ]);
    expect(refreshingChanges, [true, false]);
    expect(noMoreChanges, [true, false, true, false]);
    expect(original.items, [1]);
    expect(original.refreshStatus, RefreshStatus.idle);
    expect(before.isNoMore, isTrue);
    notifier.startLoading();
    expect(itemChanges, hasLength(1));
    notifier.replace([4]);
    expect(itemChanges, [
      [2, 3],
      [4],
    ]);
  });

  testWidgets('ref.watch 直接驱动列表和外部消费者；提示收起不通知 Provider', (tester) async {
    final container = ProviderContainer.test();
    var pageBuilds = 0;
    RefreshStatus? presented;
    final changes = <PaginatedState<int>>[];
    container.listen(paginationProvider, (_, next) => changes.add(next));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              pageBuilds++;
              final pagination = ref.watch(paginationProvider);
              return Column(
                children: [
                  Text('count:${pagination.items.length}'),
                  Expanded(
                    child: PaginatedList<int>(
                      state: pagination,
                      refreshResultDuration: const Duration(milliseconds: 20),
                      headerBuilder: (status) {
                        presented = status;
                        return SizedBox(
                          height: status == RefreshStatus.idle ? 0 : 48,
                        );
                      },
                      footerBuilder: (_) => const SizedBox.shrink(),
                      itemsBuilder: (items) => ListView(
                        children: [
                          for (final item in items) Text('item:$item'),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('count:1'), findsOneWidget);
    expect(find.text('item:1'), findsOneWidget);
    final notifier = container.read(paginationProvider.notifier);
    notifier.startRefresh();
    await tester.pump();
    expect(pageBuilds, 2);
    notifier.complete([2, 3]);
    await tester.pump();
    expect(pageBuilds, 3);
    expect(find.text('count:2'), findsOneWidget);
    expect(find.text('item:2'), findsOneWidget);
    expect(find.text('item:3'), findsOneWidget);
    expect(find.text('item:1'), findsNothing);
    final result = container.read(paginationProvider);
    await tester.pumpAndSettle(const Duration(milliseconds: 30));
    expect(pageBuilds, 3);
    expect(changes, hasLength(2));
    expect(identical(container.read(paginationProvider), result), isTrue);
    expect(result.refreshStatus, RefreshStatus.completed);
    expect(presented, RefreshStatus.idle);
  });
}
