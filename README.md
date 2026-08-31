# paginated_list

精简的 Flutter 分页滚动组件，支持下拉刷新、上拉加载和程序化指示器展示。分页状态是不可变值，可直接交给 Riverpod Notifier，也可使用普通 `setState`。

组件不管理页码、游标、网络请求、自动合并或过期响应。核心包运行时只依赖 Flutter。

## Riverpod 使用

业务项目自行添加 `flutter_riverpod`，应用入口使用 `ProviderScope`。包不要求代码生成或任何通知转发。

```dart
final usersProvider =
    NotifierProvider<UsersNotifier, PaginatedState<User>>(UsersNotifier.new);

class UsersNotifier extends Notifier<PaginatedState<User>> {
  @override
  PaginatedState<User> build() => PaginatedState<User>();

  Future<void> refresh() async {
    if (state.isRefreshing) return;
    state = state.startRefresh();
    try {
      final items = await repository.fetchFirstPage();
      if (!ref.mounted) return;
      state = state.refreshCompleted(items: items);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.refreshFailed();
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isNoMore) return;
    state = state.startLoading();
    try {
      final next = await repository.fetchNextPage();
      if (!ref.mounted) return;
      state = next.isEmpty
          ? state.loadNoData()
          : state.loadCompleted(items: [...state.items, ...next]);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.loadFailed();
    }
  }
}
```

以上片段中的 `User`、`repository` 和页码推进由业务提供。刷新与加载可以并发；业务必须隔离旧请求，避免刷新前的数据覆盖新结果。完整示例中的 `PaginationNotifier` 演示了响应代次检查。

在 Consumer 中直接使用分页状态：

```dart
final pagination = ref.watch(usersProvider);
final notifier = ref.read(usersProvider.notifier);

return PaginatedList<User>(
  state: pagination,
  onRefresh: notifier.refresh,
  onLoading: notifier.loadMore,
  bottomPadding: 24,
  headerBuilder: (status) => status == RefreshStatus.idle
      ? const SizedBox.shrink()
      : SizedBox(height: 48, child: Center(child: Text(status.name))),
  footerBuilder: (status) => status == LoadStatus.idle
      ? const SizedBox.shrink()
      : SizedBox(height: 48, child: Center(child: Text(status.name))),
  itemsBuilder: (items) => ListView.builder(
    itemCount: items.length,
    itemBuilder: (_, index) => ListTile(title: Text('${items[index]}')),
  ),
);
```

`ref.watch`、`ref.listen` 和 `select` 都直接观察同一个分页快照。只改变请求状态时复用 items 快照，因此 `select((state) => state.items)` 不会因单纯加载状态变化触发。

## 不可变状态 API

```dart
PaginatedState<T>({List<T> items = const []});

PaginatedState<T> copyWith({List<T>? items});
PaginatedState<T> startRefresh();
PaginatedState<T> refreshCompleted({List<T>? items});
PaginatedState<T> refreshFailed();
PaginatedState<T> refreshToIdle();
PaginatedState<T> startLoading();
PaginatedState<T> loadCompleted({List<T>? items});
PaginatedState<T> loadFailed();
PaginatedState<T> loadNoData({List<T>? items});
PaginatedState<T> resetNoData();
```

- 转换方法不修改原对象，必须发布返回值，例如 `state = state.startRefresh()`。
- `isRefreshing` 包括首屏请求，`isLoading` 表示加载下一页，`isNoMore` 表示没有更多。
- `items` 是完整替换列表；包不自动追加。`loadNoData(items: merged)` 可同时提交最后一页和终态。
- 合法的 `refreshCompleted()` 一次提交数据与结果，始终将加载状态重置为 `idle`，即使旧加载仍未返回；它不取消网络 Future。
- 非法完成操作不接受其中的数据更新；无效或重复操作返回原对象。
- `copyWith` 只替换数据，不改变请求状态。空调用返回原对象。
- 输入列表复制为不可修改快照，元素不深拷贝。修改元素时请提供新元素和新列表。
- 不定义深度相等比较；有效转换产生新对象，状态不需要 `dispose()`。

没有 Riverpod 时，在 StatefulWidget 中用 `setState(() => state = state.startRefresh())` 发布状态即可。可在首帧前准备 loading 快照；参见 `example/lib/pre_bound_refresh_example.dart`。

## 视图控制与请求契约

仅在需要按钮等程序化入口时创建 Controller：

```dart
final controller = PaginatedController();

// 传给 PaginatedList(controller: controller, ...)；完成布局后调用：
await controller.requestRefresh();
await controller.requestLoading();

// 由创建方在自身 dispose 中释放：
controller.dispose();
```

Controller 不保存数据。每个 Controller 同时只能绑定一个列表；一个不可变状态可同时供多个列表渲染。`isAttached` 表示已绑定，不保证布局已完成。

`request*()` 先通过视图临时状态展示指示器，再执行业务回调并等待完整 Future。同方向重复调用复用同一 Future，两个方向的展示动画串行，业务可以并发。

- 回调负责发布 `start*()` 和完成/失败状态，组件不会代为更新业务状态。
- 未挂载、未完成布局、已释放或必要回调缺失时返回错误。
- 动画中断或视图失效时，不启动尚未开始的业务；已经开始的业务不会因卸载而取消。
- 同方向业务已经进行中且没有可复用的本地 Future 时，调用直接完成，不重复执行业务。
- 程序调用错误由返回 Future 传播；手势和首屏重试入口捕获并报告错误。
- 手势在 `isNoMore` 时禁止加载。显式程序化加载仍可发起，业务可自行使用 `isNoMore` 拒绝。

普通状态快照更新不会重置滚动位置或打断动画。需要切换完整视图会话时，更换 `PaginatedList.key`；替换 Controller 会使旧入口尚未完成的展示操作失效。

## 首屏与指示器

首屏状态区分 `idle`、`loading`、`empty`、`error` 和 `completed`，可设置首屏进度、空数据和错误 builder。错误 builder 接收可选重试回调。未配置首屏 builder 时回退到 `itemsBuilder`。首屏展示期间也会调用 `itemsBuilder` 获取原始滚动配置，但只渲染指示器内容，保持方向、Controller 和视口 Key；自定义内容的 center/anchor 在内容恢复后再恢复。

Header/Footer 为必填 builder，尺寸来自实际输出，不提供默认尺寸、图标或文案。支持 ListView、GridView、CustomScrollView，支持横向、`reverse` 和 RTL。

业务状态与展示状态分离：

- `canRefresh` / `canLoading` 只用于展示手势阈值，不进入业务快照。
- 刷新业务保留 `completed` / `failed`；组件按 `refreshResultDuration` 收起提示后，Header 展示 `idle`，不写回业务状态。
- 已收起结果不因普通重建重播；新一轮相同结果仍可展示。
- 首次挂载不补播已有结果，首屏请求不展示普通 Header/Footer。
- 程序化动画期间可临时显示忙碌，但业务状态在回调发布新快照后才改变。

`loadingTriggerDistance` 使用真实滚动距离：长列表向末端滚动进入阈值时预加载；短列表只有主动上拉超过阈值并松手才加载。一次滚动手势最多触发一次加载。

`bottomPadding` 在 Footer 后添加随内容滚动的留白，默认 `0`，必须有限且非负；与原列表 padding 叠加。横向、reverse、RTL 下仍位于内容末端。

## 迁移

这是对旧可变 API 的替换，不提供兼容包装层：

| 迁移项 | 新用法 |
| --- | --- |
| 状态转换 | 保存并发布方法返回值 |
| 替换数据 | `state = state.copyWith(items: items)` |
| 请求成功 | `state = state.refreshCompleted(items: items)` |
| 加载完成 | `state = state.loadCompleted(items: merged)` |
| 没有更多 | `state.isNoMore` |
| 刷新完成选项 | 删除旧的加载重置参数；成功始终重置加载状态 |
| 程序化展示 | `controller.requestRefresh()` / `requestLoading()` |
| 状态生命周期 | 不再监听或释放状态；仅释放 Controller |
| 新数据源会话 | 更换 Widget Key，而非依赖状态实例换绑 |

## 范围与验证

不支持 NestedScrollView、自定义 ScrollView 子类、自动页码/游标、网络取消或自动数据合并。

```sh
flutter analyze
flutter test
cd example
flutter analyze
flutter test
```
