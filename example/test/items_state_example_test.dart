import 'package:example/items_state_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final result in ['failed', 'completed']) {
    testWidgets('demo 区分业务 $result 与提示收起后的 Header idle', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ItemsStateExample()));
      await tester.tap(find.text('添加一项'));
      await tester.pumpAndSettle();
      expect(find.text('界面展示：Header idle'), findsOneWidget);

      await tester.tap(find.text('开始刷新'));
      await tester.pumpAndSettle();
      expect(find.text('界面展示：Header refreshing'), findsOneWidget);
      await tester.tap(find.text(result == 'failed' ? '刷新失败' : '刷新成功'));
      await tester.pump();
      await tester.pump();
      expect(find.text('界面展示：Header $result'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('界面展示：Header idle'), findsOneWidget);
      expect(
        find.text('业务状态：items: 1 · refreshStatus: $result'),
        findsOneWidget,
      );
      expect(find.text('演示数据 1'), findsOneWidget);

      await tester.tap(find.text('删除最后一项'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('界面展示：Header idle'), findsNothing);
      expect(
        find.text(result == 'failed' ? '空列表刷新失败' : '暂无数据，点击「添加一项」'),
        findsOneWidget,
      );
      expect(
        find.text('业务状态：items: 0 · refreshStatus: $result'),
        findsOneWidget,
      );

      await tester.tap(find.text('重置状态'));
      await tester.pumpAndSettle();
      expect(find.text('业务状态：items: 0 · refreshStatus: idle'), findsOneWidget);
      expect(find.text('界面展示：空页面'), findsOneWidget);
    });
  }

  testWidgets('demo 添加、逐项删除和清空后正确显示空页面', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ItemsStateExample()));

    expect(find.text('暂无数据，点击「添加一项」'), findsOneWidget);
    await tester.tap(find.text('添加一项'));
    await tester.pump();
    expect(find.text('演示数据 1'), findsOneWidget);
    expect(find.text('暂无数据，点击「添加一项」'), findsNothing);

    await tester.tap(find.text('添加一项'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除第 1 项'));
    await tester.pump();
    expect(find.text('演示数据 1'), findsNothing);
    expect(find.text('演示数据 2'), findsOneWidget);

    await tester.tap(find.text('删除最后一项'));
    await tester.pump();
    expect(find.text('暂无数据，点击「添加一项」'), findsOneWidget);
    expect(find.text('业务状态：items: 0 · refreshStatus: idle'), findsOneWidget);

    await tester.tap(find.text('添加一项'));
    await tester.pump();
    await tester.tap(find.text('添加一项'));
    await tester.pump();
    await tester.tap(find.text('清空数据'));
    await tester.pump();
    expect(find.text('暂无数据，点击「添加一项」'), findsOneWidget);
    expect(find.text('业务状态：items: 0 · refreshStatus: idle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo 刷新期间增删数据保留状态，失败后可重试或重置', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ItemsStateExample()));
    await tester.tap(find.text('开始刷新'));
    await tester.pump();
    expect(find.text('空列表正在刷新，请选择成功或失败'), findsOneWidget);

    await tester.tap(find.text('添加一项'));
    await tester.pump();
    expect(find.text('演示数据 1'), findsOneWidget);
    expect(find.text('空列表正在刷新，请选择成功或失败'), findsNothing);
    expect(
      find.text('业务状态：items: 1 · refreshStatus: refreshing'),
      findsOneWidget,
    );

    await tester.tap(find.text('删除最后一项'));
    await tester.pump();
    expect(find.text('空列表正在刷新，请选择成功或失败'), findsOneWidget);
    await tester.tap(find.text('刷新失败'));
    await tester.pump();
    expect(find.text('空列表刷新失败'), findsOneWidget);

    await tester.tap(find.text('添加一项'));
    await tester.pump();
    expect(find.text('演示数据 2'), findsOneWidget);
    expect(find.text('空列表刷新失败'), findsNothing);
    expect(find.text('业务状态：items: 1 · refreshStatus: failed'), findsOneWidget);
    await tester.tap(find.text('删除最后一项'));
    await tester.pump();
    expect(find.text('空列表刷新失败'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('空列表正在刷新，请选择成功或失败'), findsOneWidget);
    await tester.tap(find.text('刷新成功'));
    await tester.pump();
    expect(find.text('暂无数据，点击「添加一项」'), findsOneWidget);
    expect(
      find.text('业务状态：items: 0 · refreshStatus: completed'),
      findsOneWidget,
    );

    await tester.tap(find.text('开始刷新'));
    await tester.pump();
    await tester.tap(find.text('重置状态'));
    await tester.pump();
    expect(find.text('暂无数据，点击「添加一项」'), findsOneWidget);
    expect(find.text('业务状态：items: 0 · refreshStatus: idle'), findsOneWidget);
  });
}
