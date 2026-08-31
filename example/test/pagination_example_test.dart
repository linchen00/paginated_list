import 'dart:async';

import 'package:example/main.dart';
import 'package:example/pagination_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:example/pre_bound_refresh_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('示例首页可以构建', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ExampleApp()));
    expect(find.text('PaginatedList · 0 项'), findsOneWidget);
    expect(find.byTooltip('程序化刷新'), findsOneWidget);
    expect(find.byTooltip('绑定前刷新示例'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('PaginatedList · 20 项'), findsOneWidget);
  });

  testWidgets('PaginatedState 可在绑定 UI 前进入刷新状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PreBoundRefreshExample()));
    await tester.pump();

    expect(find.text('绑定前刷新示例'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pre-bound-refreshing')),
      findsOneWidget,
    );
    expect(find.text('挂载前已进入 loading'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('预绑定刷新第 1 项'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });

  test('Provider 已释放时异步请求不再发布状态', () async {
    final pending = Completer<List<int>>();
    final container = ProviderContainer(
      overrides: [fetchPageProvider.overrideWithValue((_) => pending.future)],
    );
    container.listen(paginationProvider, (_, _) {});
    final notifier = container.read(paginationProvider.notifier);
    final request = notifier.refresh();
    container.dispose();
    pending.complete([1]);
    await request;
  });

  test('刷新结果不会被旧加载响应覆盖', () async {
    final pending = <Completer<List<int>>>[];
    final container = ProviderContainer.test(
      overrides: [
        fetchPageProvider.overrideWithValue((_) {
          final request = Completer<List<int>>();
          pending.add(request);
          return request.future;
        }),
      ],
    );
    container.listen(paginationProvider, (_, _) {});
    final notifier = container.read(paginationProvider.notifier);
    final initial = notifier.refresh();
    pending[0].complete([1]);
    await initial;
    final loading = notifier.loadMore();
    final refreshing = notifier.refresh();
    pending[2].complete([10]);
    await refreshing;
    pending[1].complete([2]);
    await loading;
    expect(container.read(paginationProvider).items, [10]);
  });
  test('刷新失败后不遗留已失效加载的 loading 状态', () async {
    final pending = <Completer<List<int>>>[];
    final container = ProviderContainer.test(
      overrides: [
        fetchPageProvider.overrideWithValue((_) {
          final request = Completer<List<int>>();
          pending.add(request);
          return request.future;
        }),
      ],
    );
    container.listen(paginationProvider, (_, _) {});
    final notifier = container.read(paginationProvider.notifier);
    final initial = notifier.refresh();
    pending[0].complete([1]);
    await initial;
    final loading = notifier.loadMore();
    final refresh = notifier.refresh();
    pending[2].completeError(StateError('refresh failed'));
    await refresh;
    expect(container.read(paginationProvider).isLoading, isFalse);
    pending[1].complete([2]);
    await loading;
    expect(container.read(paginationProvider).items, [1]);
  });
}
