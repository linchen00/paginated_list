import 'package:flutter/material.dart';
import 'package:paginated_list/paginated_list.dart';

/// 手动控制数据和刷新结果，观察两者如何共同决定列表展示。
class ItemsStateExample extends StatefulWidget {
  const ItemsStateExample({super.key});

  @override
  State<ItemsStateExample> createState() => _ItemsStateExampleState();
}

class _ItemsStateExampleState extends State<ItemsStateExample> {
  PaginatedState<int> state = PaginatedState<int>();
  final headerStatus = ValueNotifier(RefreshStatus.idle);
  int nextId = 1;

  @override
  void dispose() {
    headerStatus.dispose();
    super.dispose();
  }

  Widget _buildHeader(RefreshStatus status) {
    // 仅观测 builder 收到的真实展示状态；不在构建期间通知外部组件，
    // 也不根据业务结果自行计时或修改业务快照。
    final snapshot = state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(state, snapshot) && state.items.isNotEmpty) {
        headerStatus.value = status;
      }
    });
    return SizedBox(
      height: 48,
      child: Center(
        child: Text(switch (status) {
          RefreshStatus.idle => '下拉刷新',
          RefreshStatus.canRefresh => '松开刷新',
          RefreshStatus.refreshing => '刷新中，已有数据仍然显示',
          RefreshStatus.completed => '刷新完成',
          RefreshStatus.failed => '刷新失败，已有数据仍然显示',
        }),
      ),
    );
  }

  void _addItem() {
    setState(() {
      state = state.copyWith(items: [...state.items, nextId++]);
    });
  }

  void _removeItem(int id) {
    setState(() {
      state = state.copyWith(
        items: state.items.where((item) => item != id).toList(),
      );
    });
  }

  void _startRefresh() {
    setState(() => state = state.startRefresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据增删与空状态')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('先添加一项，再删除最后一项，观察列表与空页面切换。'),
                  const SizedBox(height: 8),
                  Text(
                    '业务状态：items: ${state.items.length} · '
                    'refreshStatus: ${state.refreshStatus.name}',
                    key: const ValueKey('items-state-summary'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (state.items.isEmpty)
                    Text(switch (state.refreshStatus) {
                      RefreshStatus.refreshing => '界面展示：首屏加载中',
                      RefreshStatus.failed => '界面展示：首屏错误（保留至重试或重置）',
                      _ => '界面展示：空页面',
                    })
                  else
                    ValueListenableBuilder<RefreshStatus>(
                      valueListenable: headerStatus,
                      builder: (_, status, _) => Text(
                        '界面展示：Header ${status.name}',
                        key: const ValueKey('header-state-summary'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text('Header 提示自动收起，业务结果保留；「重置状态」才会清除业务结果。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add),
                        label: const Text('添加一项'),
                      ),
                      OutlinedButton(
                        onPressed: state.items.isEmpty
                            ? null
                            : () => _removeItem(state.items.last),
                        child: const Text('删除最后一项'),
                      ),
                      OutlinedButton(
                        onPressed: state.items.isEmpty
                            ? null
                            : () => setState(
                                () => state = state.copyWith(items: []),
                              ),
                        child: const Text('清空数据'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('这里不发送网络请求。开始刷新后，手动选择成功或失败；期间仍可增删数据。'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: state.isRefreshing ? null : _startRefresh,
                        child: const Text('开始刷新'),
                      ),
                      OutlinedButton(
                        onPressed: state.isRefreshing
                            ? () => setState(
                                () => state = state.refreshCompleted(),
                              )
                            : null,
                        child: const Text('刷新成功'),
                      ),
                      OutlinedButton(
                        onPressed: state.isRefreshing
                            ? () =>
                                  setState(() => state = state.refreshFailed())
                            : null,
                        child: const Text('刷新失败'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => state = state.refreshToIdle()),
                        child: const Text('重置状态'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PaginatedList<int>(
                state: state,
                onRefresh: () async => _startRefresh(),
                headerBuilder: _buildHeader,
                footerBuilder: (_) => const SizedBox.shrink(),
                firstPageEmptyIndicatorBuilder: () =>
                    const Center(child: Text('暂无数据，点击「添加一项」')),
                firstPageProgressIndicatorBuilder: () =>
                    const Center(child: Text('空列表正在刷新，请选择成功或失败')),
                firstPageErrorIndicatorBuilder: (onRetry) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('空列表刷新失败'),
                      TextButton(onPressed: onRetry, child: const Text('重试')),
                    ],
                  ),
                ),
                itemsBuilder: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final id = items[index];
                    return ListTile(
                      key: ValueKey('demo-item-$id'),
                      leading: CircleAvatar(child: Text('$id')),
                      title: Text('演示数据 $id'),
                      trailing: IconButton(
                        tooltip: '删除第 $id 项',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeItem(id),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
