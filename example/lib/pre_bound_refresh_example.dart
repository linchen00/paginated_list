import 'dart:async';

import 'package:flutter/material.dart';
import 'package:paginated_list/paginated_list.dart';

/// 展示 PaginatedState 在绑定 PaginatedList 前已经开始刷新的场景。
class PreBoundRefreshExample extends StatefulWidget {
  const PreBoundRefreshExample({super.key});

  @override
  State<PreBoundRefreshExample> createState() => _PreBoundRefreshExampleState();
}

class _PreBoundRefreshExampleState extends State<PreBoundRefreshExample> {
  late final PaginatedState<int> state;

  @override
  void initState() {
    super.initState();

    // 先切换状态，再由 build() 创建 PaginatedList 并完成绑定。
    state = PaginatedState<int>()..startRefresh();
    unawaited(_fetchFirstPage());
  }

  Future<void> _fetchFirstPage() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      state.items = List.generate(20, (index) => index + 1);
      state.refreshCompleted();
    } catch (_) {
      if (mounted) state.refreshFailed();
    }
  }

  Future<void> _refresh() {
    state.startRefresh();
    return _fetchFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('绑定前刷新示例')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'PaginatedState 在 initState 中先进入 refreshing，随后才绑定 PaginatedList。',
            ),
          ),
          Expanded(
            child: PaginatedList<int>(
              state: state,
              onRefresh: _refresh,
              headerBuilder: (status) => switch (status) {
                RefreshStatus.idle => const SizedBox.shrink(),
                RefreshStatus.refreshing => const SizedBox(
                  key: ValueKey<String>('pre-bound-refreshing'),
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('绑定前已进入 refreshing'),
                    ],
                  ),
                ),
                RefreshStatus.canRefresh => const SizedBox(
                  height: 56,
                  child: Center(child: Text('松开刷新')),
                ),
                RefreshStatus.completed => const SizedBox(
                  height: 56,
                  child: Center(child: Text('刷新完成')),
                ),
                RefreshStatus.failed => const SizedBox(
                  height: 56,
                  child: Center(child: Text('刷新失败')),
                ),
              },
              footerBuilder: (_) => const SizedBox.shrink(),
              itemsBuilder: (items) => ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, index) => ListTile(
                  leading: CircleAvatar(child: Text('${items[index]}')),
                  title: Text('预绑定刷新第 ${items[index]} 项'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }
}
