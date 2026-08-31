import 'dart:async';

import 'package:flutter/material.dart';

import 'support/pagination_test_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginated_list/paginated_list.dart';

Widget _emptyHeader(RefreshStatus _) => const SizedBox.shrink();

Widget _emptyFooter(LoadStatus _) => const SizedBox.shrink();

void main() {
  final directionCases =
      <
        ({
          String name,
          Axis axis,
          bool reverse,
          TextDirection textDirection,
          Offset leadingDrag,
        })
      >[
        (
          name: '竖向',
          axis: Axis.vertical,
          reverse: false,
          textDirection: TextDirection.ltr,
          leadingDrag: const Offset(0, 120),
        ),
        (
          name: '竖向 reverse',
          axis: Axis.vertical,
          reverse: true,
          textDirection: TextDirection.ltr,
          leadingDrag: const Offset(0, -120),
        ),
        (
          name: '横向 LTR',
          axis: Axis.horizontal,
          reverse: false,
          textDirection: TextDirection.ltr,
          leadingDrag: const Offset(120, 0),
        ),
        (
          name: '横向 LTR reverse',
          axis: Axis.horizontal,
          reverse: true,
          textDirection: TextDirection.ltr,
          leadingDrag: const Offset(-120, 0),
        ),
        (
          name: '横向 RTL',
          axis: Axis.horizontal,
          reverse: false,
          textDirection: TextDirection.rtl,
          leadingDrag: const Offset(-120, 0),
        ),
        (
          name: '横向 RTL reverse',
          axis: Axis.horizontal,
          reverse: true,
          textDirection: TextDirection.rtl,
          leadingDrag: const Offset(120, 0),
        ),
      ];

  testWidgets('程序刷新复用 Future 并等待完整回调', (tester) async {
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    final callback = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: SizedBox(
            height: 300,
            child: PaginatedList<int>(
              state: state.value,
              controller: state.controller,
              footerBuilder: _emptyFooter,
              requestRefreshDuration: Duration.zero,
              onRefresh: () {
                state.value = state.value.startRefresh();
                calls++;
                return callback.future;
              },
              itemsBuilder: (items) => ListView.builder(
                itemExtent: 30,
                itemCount: items.length,
                itemBuilder: (_, index) => Text('${items[index]}'),
              ),
              headerBuilder: (status) => status == RefreshStatus.idle
                  ? const SizedBox.shrink()
                  : const SizedBox(height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final first = state.controller.requestRefresh();
    final second = state.controller.requestRefresh();
    expect(identical(first, second), isTrue);
    await tester.pumpAndSettle();
    await tester.pump();
    expect(calls, 1);
    expect(state.value.refreshStatus, RefreshStatus.refreshing);

    callback.complete();
    await first;
  });

  testWidgets('首屏状态保留 PaginatedList 绑定并在完成后进入分页模式', (tester) async {
    final state = PaginationTestHost<int>();
    final refreshCallback = Completer<void>();
    var loadingCalls = 0;

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            firstPageEmptyIndicatorBuilder: () => const Text('first-empty'),
            firstPageProgressIndicatorBuilder: () =>
                const Text('first-loading'),
            firstPageErrorIndicatorBuilder: (_) => const Text('first-error'),
            onRefresh: () {
              state.value = state.value.startRefresh();
              return refreshCallback.future;
            },
            onLoading: () async {
              state.value = state.value.startLoading();
              loadingCalls++;
              state.value = state.value.loadCompleted();
            },
            itemsBuilder: (items) => ListView(
              children: items.map((item) => Text('item$item')).toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('first-empty'), findsOneWidget);
    final refresh = state.controller.requestRefresh();
    await tester.pumpAndSettle();
    expect(state.value.firstPageStatus, FirstPageStatus.loading);
    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(find.text('first-loading'), findsOneWidget);

    state.value = state.value.copyWith(items: [1]);
    state.value = state.value.refreshCompleted();
    refreshCallback.complete();
    await refresh;
    await tester.pump();

    expect(state.value.firstPageStatus, FirstPageStatus.completed);
    expect(find.text('item1'), findsOneWidget);

    final loading = state.controller.requestLoading();
    await tester.pumpAndSettle();
    await loading;
    expect(loadingCalls, 1);
  });

  testWidgets('首屏失败状态通过同一个 requestRefresh 重试', (tester) async {
    final state = PaginationTestHost<int>();
    VoidCallback? retry;
    var refreshCalls = 0;

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            firstPageErrorIndicatorBuilder: (onTryAgain) {
              retry = onTryAgain;
              return const Text('first-error');
            },
            onRefresh: () async {
              state.value = state.value.startRefresh();
              refreshCalls++;
              state.value = state.value.refreshFailed();
            },
            itemsBuilder: (_) => ListView(),
          ),
        ),
      ),
    );
    await tester.pump();

    final firstRefresh = state.controller.requestRefresh();
    await tester.pumpAndSettle();
    await firstRefresh;
    await tester.pump();
    expect(state.value.firstPageStatus, FirstPageStatus.error);
    expect(find.text('first-error'), findsOneWidget);
    expect(retry, isNotNull);

    retry!();
    await tester.pumpAndSettle();
    expect(refreshCalls, 2);
    expect(state.value.firstPageStatus, FirstPageStatus.error);
  });

  testWidgets('首屏 Indicator 未配置时回退到 itemsBuilder', (tester) async {
    final state = PaginationTestHost<int>();

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            itemsBuilder: (_) =>
                ListView(children: const [Text('items-builder-empty')]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(state.value.firstPageStatus, FirstPageStatus.idle);
    expect(find.text('items-builder-empty'), findsOneWidget);

    state.value = state.value.startRefresh();
    await tester.pump();
    expect(state.value.firstPageStatus, FirstPageStatus.loading);
    expect(find.text('items-builder-empty'), findsOneWidget);

    state.value = state.value.refreshFailed();
    await tester.pump();
    expect(state.value.firstPageStatus, FirstPageStatus.error);
    expect(find.text('items-builder-empty'), findsOneWidget);
  });

  testWidgets('首屏未完成时不构建或布局 Header 和 Footer', (tester) async {
    final state = PaginationTestHost<int>();
    var headerBuilds = 0;
    var footerBuilds = 0;

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: (_) {
              headerBuilds++;
              return const SizedBox(height: 48, child: Text('page-header'));
            },
            firstPageEmptyIndicatorBuilder: () => const Text('first-page'),
            footerBuilder: (_) {
              footerBuilds++;
              return const SizedBox(height: 48, child: Text('page-footer'));
            },
            itemsBuilder: (items) =>
                ListView(children: items.map((item) => Text('$item')).toList()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(headerBuilds, 0);
    expect(footerBuilds, 0);
    expect(find.text('page-header'), findsNothing);
    expect(find.text('page-footer'), findsNothing);

    state.value = state.value.startRefresh();
    state.value = state.value.copyWith(items: [1]);
    state.value = state.value.refreshCompleted();
    await tester.pump();

    expect(state.value.firstPageStatus, FirstPageStatus.completed);
    expect(headerBuilds, 1);
    expect(footerBuilds, 1);
    expect(find.text('page-footer'), findsOneWidget);
  });

  testWidgets('状态变化按正常重建语义调用 itemsBuilder', (tester) async {
    final state = PaginationTestHost<int>(items: [1]);
    var itemBuilds = 0;
    var headerBuilds = 0;
    var footerBuilds = 0;

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            itemsBuilder: (items) {
              itemBuilds++;
              return ListView(children: [Text('${items.single}')]);
            },
            headerBuilder: (status) {
              headerBuilds++;
              return const SizedBox.shrink();
            },
            footerBuilder: (status) {
              footerBuilds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    state.value = state.value.startRefresh();
    await tester.pump();

    expect(itemBuilds, 2);
    expect(headerBuilds, 2);
    expect(footerBuilds, 2);

    state.value = state.value.copyWith(items: [2]);
    await tester.pump();
    expect(itemBuilds, 3);
    expect(headerBuilds, 3);
    expect(footerBuilds, 3);
  });

  testWidgets('刷新提示收起不修改业务结果', (tester) async {
    final state = PaginationTestHost<int>(items: [1]);
    state.value = state.value.startRefresh();
    RefreshStatus? presented;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: (status) {
              presented = status;
              return const SizedBox.shrink();
            },
            footerBuilder: _emptyFooter,
            refreshResultDuration: const Duration(milliseconds: 100),
            itemsBuilder: (_) => ListView(),
          ),
        ),
      ),
    );
    state.value = state.value.refreshCompleted();
    await tester.pump();
    expect(state.value.refreshStatus, RefreshStatus.completed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(presented, RefreshStatus.idle);
    expect(state.value.refreshStatus, RefreshStatus.completed);
  });

  testWidgets('completed 在页面回弹到边界后才恢复 idle', (tester) async {
    final controller = ScrollController();
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    double? pixelsAtIdle;
    state.value = state.value.startRefresh();

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            refreshResultDuration: const Duration(milliseconds: 100),
            headerBuilder: (status) {
              if (status == RefreshStatus.idle && controller.hasClients) {
                pixelsAtIdle = controller.position.pixels;
              }
              return const SizedBox(height: 48);
            },
            footerBuilder: _emptyFooter,
            itemsBuilder: (items) => ListView.builder(
              controller: controller,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    state.value = state.value.refreshCompleted();
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    expect(state.value.refreshStatus, RefreshStatus.completed);
    await tester.pump();
    expect(state.value.refreshStatus, RefreshStatus.completed);

    await tester.pumpAndSettle();
    expect(state.value.refreshStatus, RefreshStatus.completed);
    expect(pixelsAtIdle, closeTo(controller.position.minScrollExtent, 0.5));
    controller.dispose();
  });

  testWidgets('同一 Controller 不能同时绑定两个列表', (tester) async {
    final state = PaginationTestHost<int>();
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: Row(
            children: [
              Expanded(
                child: PaginatedList<int>(
                  state: state.value,
                  controller: state.controller,
                  headerBuilder: _emptyHeader,
                  footerBuilder: _emptyFooter,
                  itemsBuilder: (_) => ListView(),
                ),
              ),
              Expanded(
                child: PaginatedList<int>(
                  state: state.value,
                  controller: state.controller,
                  headerBuilder: _emptyHeader,
                  footerBuilder: _emptyFooter,
                  itemsBuilder: (_) => ListView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('竖向边缘拖动达到阈值后才触发刷新', (tester) async {
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    var calls = 0;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            refreshTriggerDistance: 60,
            onRefresh: () async {
              state.value = state.value.startRefresh();
              calls++;
              state.value = state.value.refreshCompleted();
            },
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 30));
    await tester.pump();
    expect(calls, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('未配置 onRefresh 时下拉不会进入 canRefresh', (tester) async {
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            refreshTriggerDistance: 20,
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(state.value.refreshStatus, RefreshStatus.idle);
  });

  testWidgets('canRefresh Header 跟随下拉且跨阈值不产生额外跳动', (tester) async {
    const firstItemKey = ValueKey<String>('first-item');
    const canRefreshKey = ValueKey<String>('can-refresh');
    final controller = ScrollController();
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            footerBuilder: _emptyFooter,
            refreshTriggerDistance: 75,
            onRefresh: () async => state.value = state.value.refreshToIdle(),
            headerBuilder: (status) => status == RefreshStatus.canRefresh
                ? const SizedBox(
                    key: canRefreshKey,
                    height: 48,
                    child: Text('release'),
                  )
                : const SizedBox.shrink(),
            itemsBuilder: (items) => ListView.builder(
              controller: controller,
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => SizedBox(
                key: index == 0 ? firstItemKey : null,
                child: Text('${items[index]}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    final itemTopBeforeThreshold = tester
        .getTopLeft(find.byKey(firstItemKey))
        .dy;
    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(
      controller.position.minScrollExtent - controller.position.pixels,
      lessThan(75),
    );

    await gesture.moveBy(const Offset(0, 15));
    await tester.pump();

    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(
      controller.position.minScrollExtent - controller.position.pixels,
      greaterThanOrEqualTo(75),
    );
    expect(find.byKey(canRefreshKey), findsOneWidget);
    final itemTopAfterThreshold = tester
        .getTopLeft(find.byKey(firstItemKey))
        .dy;
    expect(
      itemTopAfterThreshold - itemTopBeforeThreshold,
      lessThanOrEqualTo(15),
    );
    expect(
      tester.getBottomLeft(find.byKey(canRefreshKey)).dy,
      closeTo(itemTopAfterThreshold, 0.1),
    );

    final headerBottomBeforeMorePull = tester
        .getBottomLeft(find.byKey(canRefreshKey))
        .dy;
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    expect(
      tester.getBottomLeft(find.byKey(canRefreshKey)).dy -
          headerBottomBeforeMorePull,
      closeTo(
        tester.getTopLeft(find.byKey(firstItemKey)).dy - itemTopAfterThreshold,
        0.1,
      ),
    );

    await gesture.moveBy(const Offset(0, -95));
    await tester.pump();
    expect(state.value.refreshStatus, RefreshStatus.idle);
    await gesture.up();
    controller.dispose();
  });

  testWidgets('idle Header 初始隐藏且仅在下拉时露出', (tester) async {
    const idleHeaderKey = ValueKey<String>('idle-header');
    const firstItemKey = ValueKey<String>('idle-first-item');
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: (status) => status == RefreshStatus.idle
                ? const SizedBox(
                    key: idleHeaderKey,
                    height: 48,
                    child: Text('pull to refresh'),
                  )
                : const SizedBox.shrink(),
            footerBuilder: _emptyFooter,
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => SizedBox(
                key: index == 0 ? firstItemKey : null,
                child: Text('${items[index]}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(find.byKey(idleHeaderKey), findsNothing);

    final initialItemTop = tester.getTopLeft(find.byKey(firstItemKey)).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();

    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(
      tester.getTopLeft(find.byKey(firstItemKey)).dy,
      greaterThan(initialItemTop),
    );
    expect(
      tester.getBottomLeft(find.byKey(idleHeaderKey)).dy,
      closeTo(tester.getTopLeft(find.byKey(firstItemKey)).dy, 0.1),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('回弹刷新时 Header 占位且不覆盖列表内容', (tester) async {
    const firstItemKey = ValueKey<String>('refreshing-first-item');
    const refreshingHeaderKey = ValueKey<String>('refreshing-header');
    final callback = Completer<void>();
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            footerBuilder: _emptyFooter,
            refreshTriggerDistance: 60,
            onRefresh: () {
              state.value = state.value.startRefresh();
              return callback.future;
            },
            headerBuilder: (status) => switch (status) {
              RefreshStatus.canRefresh => const SizedBox(
                height: 48,
                child: Text('release'),
              ),
              RefreshStatus.refreshing => const SizedBox(
                key: refreshingHeaderKey,
                height: 48,
                child: Text('refreshing'),
              ),
              _ => const SizedBox.shrink(),
            },
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => SizedBox(
                key: index == 0 ? firstItemKey : null,
                child: Text('${items[index]}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();

    expect(state.value.refreshStatus, RefreshStatus.refreshing);
    expect(
      find.byKey(refreshingHeaderKey, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(find.byKey(refreshingHeaderKey)).dy,
      closeTo(tester.getTopLeft(find.byKey(firstItemKey)).dy, 0.1),
    );

    callback.complete();
    state.value = state.value.refreshToIdle();
    await tester.pumpAndSettle();
  });

  testWidgets('松手进入回弹时立即从 canRefresh 切换为 refreshing', (tester) async {
    final controller = ScrollController();
    final callback = Completer<void>();
    final state = PaginationTestHost<int>(items: List.generate(30, (i) => i));
    double? pixelsAtRefreshing;
    state.addListener(() {
      if (state.value.refreshStatus == RefreshStatus.refreshing &&
          controller.hasClients) {
        pixelsAtRefreshing ??= controller.position.pixels;
      }
    });

    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            footerBuilder: _emptyFooter,
            refreshTriggerDistance: 60,
            onRefresh: () {
              state.value = state.value.startRefresh();
              return callback.future;
            },
            headerBuilder: (status) => switch (status) {
              RefreshStatus.canRefresh => const SizedBox(
                height: 48,
                child: Text('release'),
              ),
              RefreshStatus.refreshing => const SizedBox(
                height: 48,
                child: Text('refreshing'),
              ),
              _ => const SizedBox.shrink(),
            },
            itemsBuilder: (items) => ListView.builder(
              controller: controller,
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(state.value.refreshStatus, RefreshStatus.idle);
    expect(find.text('release'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(state.value.refreshStatus, RefreshStatus.refreshing);
    expect(pixelsAtRefreshing, isNotNull);
    expect(pixelsAtRefreshing!, lessThan(controller.position.minScrollExtent));

    callback.complete();
    state.value = state.value.refreshToIdle();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('短内容只在主动末端拖动后加载', (tester) async {
    final state = PaginationTestHost<int>(items: [1]);
    var calls = 0;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            loadingTriggerDistance: 15,
            onLoading: () async {
              state.value = state.value.startLoading();
              calls++;
              state.value = state.value.loadCompleted();
            },
            itemsBuilder: (items) =>
                ListView(children: items.map((item) => Text('$item')).toList()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('用户滚动触底后自动加载更多', (tester) async {
    final state = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    var calls = 0;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            onLoading: () async {
              state.value = state.value.startLoading();
              calls++;
              state.value = state.value.loadCompleted();
            },
            itemsBuilder: (items) => ListView.builder(
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      5000,
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('长列表拖动进入预加载阈值时立即加载', (tester) async {
    final controller = ScrollController();
    final state = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final callback = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            loadingTriggerDistance: 20,
            onLoading: () {
              state.value = state.value.startLoading();
              calls++;
              return callback.future;
            },
            itemsBuilder: (items) => ListView.builder(
              controller: controller,
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent - 30);
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(state.value.loadStatus, LoadStatus.loading);
    expect(calls, 1);

    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(state.value.loadStatus, LoadStatus.loading);
    expect(calls, 1);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 32));
    expect(calls, 1);
    callback.complete();
    state.value = state.value.loadCompleted();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('短内容 canLoading Footer 跟随内容且松手后连续进入 loading', (tester) async {
    const itemKey = ValueKey<String>('short-load-item');
    const canLoadingKey = ValueKey<String>('short-can-loading');
    const loadingKey = ValueKey<String>('short-loading');
    final callback = Completer<void>();
    final state = PaginationTestHost<int>(items: [1]);
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            loadingTriggerDistance: 20,
            onLoading: () {
              state.value = state.value.startLoading();
              return callback.future;
            },
            footerBuilder: (status) => switch (status) {
              LoadStatus.canLoading => const SizedBox(
                key: canLoadingKey,
                height: 48,
                child: Text('release loading'),
              ),
              LoadStatus.loading => const SizedBox(
                key: loadingKey,
                height: 48,
                child: Text('loading'),
              ),
              _ => const SizedBox.shrink(),
            },
            itemsBuilder: (items) => ListView(
              children: const [
                SizedBox(key: itemKey, height: 200, child: Text('item')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();

    expect(state.value.loadStatus, LoadStatus.idle);
    expect(find.byKey(canLoadingKey), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(canLoadingKey)).dy,
      closeTo(tester.getBottomLeft(find.byKey(itemKey)).dy, 0.1),
    );

    final footerTop = tester.getTopLeft(find.byKey(canLoadingKey)).dy;
    final itemTop = tester.getTopLeft(find.byKey(itemKey)).dy;
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(canLoadingKey)).dy - footerTop,
      closeTo(tester.getTopLeft(find.byKey(itemKey)).dy - itemTop, 0.1),
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(state.value.loadStatus, LoadStatus.loading);
    expect(find.byKey(loadingKey), findsOneWidget);

    callback.complete();
    state.value = state.value.loadCompleted();
    await tester.pumpAndSettle();
  });

  testWidgets('惯性滚动进入末端阈值时立即加载', (tester) async {
    final controller = ScrollController();
    final state = PaginationTestHost<int>(items: List.generate(50, (i) => i));
    final callback = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      state.build(
        () => MaterialApp(
          home: PaginatedList<int>(
            state: state.value,
            controller: state.controller,
            headerBuilder: _emptyHeader,
            footerBuilder: _emptyFooter,
            loadingTriggerDistance: 15,
            onLoading: () {
              state.value = state.value.startLoading();
              calls++;
              return callback.future;
            },
            itemsBuilder: (items) => ListView.builder(
              controller: controller,
              itemExtent: 40,
              itemCount: items.length,
              itemBuilder: (_, index) => Text('${items[index]}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent - 70);
    await tester.pump();

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -50),
      3000,
    );
    for (var frame = 0; frame < 10 && calls == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(calls, 1);
    expect(state.value.loadStatus, LoadStatus.loading);

    callback.complete();
    state.value = state.value.loadCompleted();
    await tester.pumpAndSettle();
  });

  for (final testCase in directionCases) {
    testWidgets('${testCase.name} 的 leading/trailing 手势方向正确', (tester) async {
      final state = PaginationTestHost<int>(items: [1]);
      var refreshCalls = 0;
      var loadingCalls = 0;
      await tester.pumpWidget(
        state.build(
          () => MaterialApp(
            home: Directionality(
              textDirection: testCase.textDirection,
              child: PaginatedList<int>(
                state: state.value,
                controller: state.controller,
                headerBuilder: _emptyHeader,
                footerBuilder: _emptyFooter,
                refreshTriggerDistance: 30,
                loadingTriggerDistance: 15,
                onRefresh: () async {
                  state.value = state.value.startRefresh();
                  refreshCalls++;
                  state.value = state.value.refreshToIdle();
                },
                onLoading: () async {
                  state.value = state.value.startLoading();
                  loadingCalls++;
                  state.value = state.value.loadCompleted();
                },
                itemsBuilder: (items) => ListView(
                  scrollDirection: testCase.axis,
                  reverse: testCase.reverse,
                  children: items.map((item) => Text('$item')).toList(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.drag(find.byType(CustomScrollView), testCase.leadingDrag);
      await tester.pumpAndSettle();
      expect(refreshCalls, 1);

      await tester.drag(find.byType(CustomScrollView), -testCase.leadingDrag);
      await tester.pumpAndSettle();
      expect(loadingCalls, 1);
    });
  }
}
