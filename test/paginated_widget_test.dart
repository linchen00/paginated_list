import 'dart:async';

import 'package:flutter/material.dart';
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
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    final callback = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: PaginatedList<int>(
            state: state,
            footerBuilder: _emptyFooter,
            requestRefreshDuration: Duration.zero,
            onRefresh: () {
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
    );
    await tester.pump();

    final first = state.requestRefresh();
    final second = state.requestRefresh();
    expect(identical(first, second), isTrue);
    await tester.pumpAndSettle();
    await tester.pump();
    expect(calls, 1);
    expect(state.refreshStatus, RefreshStatus.refreshing);

    callback.complete();
    await first;
  });

  testWidgets('状态变化只缓存 itemsBuilder', (tester) async {
    final state = PaginatedState<int>(items: [1]);
    var itemBuilds = 0;
    var headerBuilds = 0;
    var footerBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
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
    );
    await tester.pump();
    state.startRefresh();
    await tester.pump();

    expect(itemBuilds, 1);
    expect(headerBuilds, 2);
    expect(footerBuilds, 2);

    state.items = [2];
    await tester.pump();
    expect(itemBuilds, 2);
    expect(headerBuilds, 3);
    expect(footerBuilds, 3);
  });

  testWidgets('刷新结果按配置时长恢复 idle', (tester) async {
    final state = PaginatedState<int>();
    state.startRefresh();
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          refreshResultDuration: const Duration(milliseconds: 100),
          itemsBuilder: (_) => ListView(),
        ),
      ),
    );
    state.refreshCompleted();
    await tester.pump();
    expect(state.refreshStatus, RefreshStatus.completed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.refreshStatus, RefreshStatus.idle);
  });

  testWidgets('同一 state 不能同时绑定两个列表', (tester) async {
    final state = PaginatedState<int>();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: PaginatedList<int>(
                state: state,
                headerBuilder: _emptyHeader,
                footerBuilder: _emptyFooter,
                itemsBuilder: (_) => ListView(),
              ),
            ),
            Expanded(
              child: PaginatedList<int>(
                state: state,
                headerBuilder: _emptyHeader,
                footerBuilder: _emptyFooter,
                itemsBuilder: (_) => ListView(),
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('竖向边缘拖动达到阈值后才触发刷新', (tester) async {
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          refreshTriggerDistance: 60,
          onRefresh: () async {
            calls++;
            state.refreshCompleted();
          },
          itemsBuilder: (items) => ListView.builder(
            itemExtent: 40,
            itemCount: items.length,
            itemBuilder: (_, index) => Text('${items[index]}'),
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
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
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
    );
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(state.refreshStatus, RefreshStatus.idle);
  });

  testWidgets('canRefresh Header 跟随下拉且跨阈值不产生额外跳动', (tester) async {
    const firstItemKey = ValueKey<String>('first-item');
    const canRefreshKey = ValueKey<String>('can-refresh');
    final controller = ScrollController();
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          footerBuilder: _emptyFooter,
          refreshTriggerDistance: 75,
          onRefresh: () async => state.refreshToIdle(),
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
    expect(state.refreshStatus, RefreshStatus.idle);
    expect(
      controller.position.minScrollExtent - controller.position.pixels,
      lessThan(75),
    );

    await gesture.moveBy(const Offset(0, 15));
    await tester.pump();

    expect(state.refreshStatus, RefreshStatus.canRefresh);
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
    expect(state.refreshStatus, RefreshStatus.idle);
    await gesture.up();
    controller.dispose();
  });

  testWidgets('回弹刷新时 Header 占位且不覆盖列表内容', (tester) async {
    const firstItemKey = ValueKey<String>('refreshing-first-item');
    const refreshingHeaderKey = ValueKey<String>('refreshing-header');
    final callback = Completer<void>();
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          footerBuilder: _emptyFooter,
          refreshTriggerDistance: 60,
          onRefresh: () => callback.future,
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
    );
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();

    expect(state.refreshStatus, RefreshStatus.refreshing);
    expect(
      find.byKey(refreshingHeaderKey, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(find.byKey(refreshingHeaderKey)).dy,
      closeTo(tester.getTopLeft(find.byKey(firstItemKey)).dy, 0.1),
    );

    callback.complete();
    state.refreshToIdle();
    await tester.pumpAndSettle();
  });

  testWidgets('松手进入回弹时立即从 canRefresh 切换为 refreshing', (tester) async {
    final controller = ScrollController();
    final callback = Completer<void>();
    final state = PaginatedState<int>(items: List.generate(30, (i) => i));
    double? pixelsAtRefreshing;
    state.addListener(() {
      if (state.refreshStatus == RefreshStatus.refreshing &&
          controller.hasClients) {
        pixelsAtRefreshing ??= controller.position.pixels;
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          footerBuilder: _emptyFooter,
          refreshTriggerDistance: 60,
          onRefresh: () => callback.future,
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
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(state.refreshStatus, RefreshStatus.canRefresh);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(state.refreshStatus, RefreshStatus.refreshing);
    expect(pixelsAtRefreshing, isNotNull);
    expect(pixelsAtRefreshing!, lessThan(controller.position.minScrollExtent));

    callback.complete();
    state.refreshToIdle();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('短内容只在主动末端拖动后加载', (tester) async {
    final state = PaginatedState<int>(items: [1]);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          loadingTriggerDistance: 15,
          onLoading: () async {
            calls++;
            state.loadComplete();
          },
          itemsBuilder: (items) =>
              ListView(children: items.map((item) => Text('$item')).toList()),
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
    final state = PaginatedState<int>(items: List.generate(50, (i) => i));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          onLoading: () async {
            calls++;
            state.loadComplete();
          },
          itemsBuilder: (items) => ListView.builder(
            itemExtent: 40,
            itemCount: items.length,
            itemBuilder: (_, index) => Text('${items[index]}'),
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
    final state = PaginatedState<int>(items: List.generate(50, (i) => i));
    final callback = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          loadingTriggerDistance: 20,
          onLoading: () {
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
    );
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent - 30);
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(state.loadStatus, LoadStatus.loading);
    expect(calls, 1);

    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(state.loadStatus, LoadStatus.loading);
    expect(calls, 1);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 32));
    expect(calls, 1);
    callback.complete();
    state.loadComplete();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('短内容 canLoading Footer 跟随内容且松手后连续进入 loading', (tester) async {
    const itemKey = ValueKey<String>('short-load-item');
    const canLoadingKey = ValueKey<String>('short-can-loading');
    const loadingKey = ValueKey<String>('short-loading');
    final callback = Completer<void>();
    final state = PaginatedState<int>(items: [1]);
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          loadingTriggerDistance: 20,
          onLoading: () => callback.future,
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
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();

    expect(state.loadStatus, LoadStatus.canLoading);
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
    expect(state.loadStatus, LoadStatus.loading);
    expect(find.byKey(loadingKey), findsOneWidget);

    callback.complete();
    state.loadComplete();
    await tester.pumpAndSettle();
  });

  testWidgets('惯性滚动进入末端阈值时立即加载', (tester) async {
    final controller = ScrollController();
    final state = PaginatedState<int>(items: List.generate(50, (i) => i));
    final callback = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaginatedList<int>(
          state: state,
          headerBuilder: _emptyHeader,
          footerBuilder: _emptyFooter,
          loadingTriggerDistance: 15,
          onLoading: () {
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
    expect(state.loadStatus, LoadStatus.loading);

    callback.complete();
    state.loadComplete();
    await tester.pumpAndSettle();
  });

  for (final testCase in directionCases) {
    testWidgets('${testCase.name} 的 leading/trailing 手势方向正确', (tester) async {
      final state = PaginatedState<int>(items: [1]);
      var refreshCalls = 0;
      var loadingCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: testCase.textDirection,
            child: PaginatedList<int>(
              state: state,
              headerBuilder: _emptyHeader,
              footerBuilder: _emptyFooter,
              refreshTriggerDistance: 30,
              loadingTriggerDistance: 15,
              onRefresh: () async {
                refreshCalls++;
                state.refreshToIdle();
              },
              onLoading: () async {
                loadingCalls++;
                state.loadComplete();
              },
              itemsBuilder: (items) => ListView(
                scrollDirection: testCase.axis,
                reverse: testCase.reverse,
                children: items.map((item) => Text('$item')).toList(),
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
