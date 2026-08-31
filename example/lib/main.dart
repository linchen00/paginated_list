import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paginated_list/paginated_list.dart';

import 'pre_bound_refresh_example.dart';
import 'pagination_notifier.dart';

void main() => runApp(const ProviderScope(child: ExampleApp()));

Widget _buildHeader(RefreshStatus status) => switch (status) {
  RefreshStatus.idle => SizedBox(
    height: 48,
    child: Center(child: Text('下拉刷新')),
  ),
  RefreshStatus.canRefresh => const SizedBox(
    height: 48,
    child: Center(child: Text('松开刷新')),
  ),
  RefreshStatus.refreshing => const SizedBox(
    height: 48,
    child: Center(child: CircularProgressIndicator()),
  ),
  RefreshStatus.completed => const SizedBox(
    height: 48,
    child: Center(child: Text('刷新完成')),
  ),
  RefreshStatus.failed => const SizedBox(
    height: 48,
    child: Center(child: Text('刷新失败')),
  ),
};

Widget _buildFooter(LoadStatus status) => switch (status) {
  LoadStatus.idle => const SizedBox.shrink(),
  LoadStatus.canLoading => const SizedBox(
    height: 48,
    child: Center(child: Text('松开加载')),
  ),
  LoadStatus.loading => const SizedBox(
    height: 48,
    child: Center(child: CircularProgressIndicator()),
  ),
  LoadStatus.noMore => const SizedBox(
    height: 48,
    child: Center(child: Text('没有更多了')),
  ),
  LoadStatus.failed => const SizedBox(
    height: 48,
    child: Center(child: Text('加载失败')),
  ),
};

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PaginationExample());
  }
}

class PaginationExample extends ConsumerStatefulWidget {
  const PaginationExample({super.key});

  @override
  ConsumerState<PaginationExample> createState() => _PaginationExampleState();
}

class _PaginationExampleState extends ConsumerState<PaginationExample> {
  final controller = PaginatedController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(paginationProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paginationProvider);
    final notifier = ref.read(paginationProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text('PaginatedList · ${state.items.length} 项'),
        actions: [
          IconButton(
            tooltip: '绑定前刷新示例',
            icon: const Icon(Icons.hourglass_top),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PreBoundRefreshExample(),
              ),
            ),
          ),
        ],
      ),
      body: PaginatedList<int>(
        bottomPadding: 24,
        loadingTriggerDistance: 100,
        state: state,
        controller: controller,
        headerBuilder: _buildHeader,
        footerBuilder: _buildFooter,
        onRefresh: notifier.refresh,
        onLoading: notifier.loadMore,
        itemsBuilder: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, index) => ListTile(
            leading: CircleAvatar(child: Text('${items[index]}')),
            title: Text('第 ${items[index]} 项'),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => controller.requestRefresh().catchError((Object error) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }),
        tooltip: '程序化刷新',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
