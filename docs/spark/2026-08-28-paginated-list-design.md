# PaginatedList 设计规格

## 1. 目标

`PaginatedList` 是一个精简的 Flutter 分页滚动组件，在 `flutter_pulltorefresh` 的核心交互基础上，仅保留：

- 下拉刷新；
- 上拉加载更多；
- 可自定义 Header/Footer；
- 业务方自主管理列表数据；
- UI 挂载后的手势请求和程序化请求；
- UI 挂载前即可进入刷新或加载状态。

本包不负责页码、游标、网络请求、错误模型或数据合并策略。

## 2. 方案选择

### 2.1 已选：可变 `PaginatedState extends ChangeNotifier`

`PaginatedState<T>` 同时持有 items、刷新状态、加载状态和语义化状态操作。业务以下列方式直接使用：

```dart
state.startRefresh();
state.items = firstPage;
state.refreshCompleted();
```

选择理由：

- 与期望的直接可变 API 一致；
- 多个相关字段可在一次操作中原子更新，然后只通知一次；
- 比为 items、RefreshStatus 和 LoadStatus 分别暴露可写 `ValueNotifier` 更难被绕过状态机；
- 业务仍可用 Provider/Riverpod/Bloc 持有该对象，`PaginatedList` 直接监听对象变化。

### 2.2 未选：不可变 State + ValueNotifier Controller

该方案与 `infinite_scroll_pagination` 类似：State 是不可变值对象，Controller 继承 `ValueNotifier<State>`。它的状态管理边界更纯粹，但会将 API 改为 `controller.value = controller.value.copyWith(...)`，不符合本项目期望的直接调用方式。

### 2.3 未选：多个公开 ValueNotifier

为 items、RefreshStatus 和 LoadStatus 各自公开一个 `ValueNotifier` 可以精确重建，但业务可直接修改 `.value`，从而绕过 `startRefresh()`、`loadNoData()` 等状态机方法。

## 3. 公开类型

### 3.1 状态枚举

```dart
enum RefreshStatus {
  idle,
  canRefresh,
  refreshing,
  completed,
  failed,
}

enum LoadStatus {
  idle,
  canLoading,
  loading,
  noMore,
  failed,
}
```

`canRefresh` 和 `canLoading` 是手势瞬态，不对外提供直接 setter。

### 3.2 Builder

```dart
typedef PaginatedItemsBuilder<T> = ScrollView Function(
  List<T> items,
);

typedef PaginatedHeaderBuilder = Widget Function(
  RefreshStatus status,
);

typedef PaginatedFooterBuilder = Widget Function(
  LoadStatus status,
);
```

约束：

- 三个 builder 均不接收 `BuildContext`；
- `itemsBuilder` 必须返回 `ScrollView`，类型系统直接阻止返回 `Column` 等普通 Widget；
- `headerBuilder` 和 `footerBuilder` 可空，为空时使用包内置的极简默认指示器；
- Header/Footer builder 返回普通 Widget，等价于在包内部 Header/Footer 的 child 位置上按状态执行 Builder；
- 包不强制 Header/Footer 的高度、宽度、显隐和内容动画；
- builder 必须返回主轴尺寸有限的 Widget；
- 若 idle 时需要隐藏，业务方返回 `SizedBox.shrink()`；包不会擅自隐藏自定义内容；
- 业务需要尺寸过渡时，在 builder 内自行使用 `AnimatedSize` 等组件。

### 3.3 PaginatedState

```dart
class PaginatedState<T> extends ChangeNotifier {
  PaginatedState({List<T> items = const []});

  List<T> get items;
  set items(List<T> value);

  RefreshStatus get refreshStatus;
  LoadStatus get loadStatus;

  Future<void> requestRefresh();
  Future<void> requestLoading();

  void startRefresh();
  void startLoading();

  void refreshCompleted({bool resetLoadStatus = true});
  void refreshFailed();
  void refreshToIdle();

  void loadComplete();
  void loadFailed();
  void loadNoData();
  void resetNoData();
}
```

规则：

- 构造时 RefreshStatus 和 LoadStatus 固定为 `idle`；
- 构造器和 items setter 都通过 `List.unmodifiable(...)` 保存浅层不可变副本；
- `state.items.add(...)` 抛出 `UnsupportedError`；
- 更新数据必须重新赋值，例如 `state.items = [...state.items, ...nextPage]`；
- RefreshStatus 和 LoadStatus 只读，只能通过语义化方法修改；
- `PaginatedState` 由业务方创建和 dispose，`PaginatedList` 不释放外部传入的 state。

### 3.4 PaginatedList

```dart
class PaginatedList<T> extends StatefulWidget {
  const PaginatedList({
    super.key,
    required this.state,
    required this.itemsBuilder,
    this.headerBuilder,
    this.footerBuilder,
    this.onRefresh,
    this.onLoading,
    this.refreshTriggerDistance = 80,
    this.loadingTriggerDistance = 15,
    this.requestRefreshDuration = const Duration(milliseconds: 500),
    this.requestLoadingDuration = const Duration(milliseconds: 300),
    this.refreshResultDuration = const Duration(milliseconds: 500),
    this.requestCurve = Curves.linear,
  });

  final PaginatedState<T> state;
  final PaginatedItemsBuilder<T> itemsBuilder;
  final PaginatedHeaderBuilder? headerBuilder;
  final PaginatedFooterBuilder? footerBuilder;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoading;

  final double refreshTriggerDistance;
  final double loadingTriggerDistance;
  final Duration requestRefreshDuration;
  final Duration requestLoadingDuration;
  final Duration refreshResultDuration;
  final Curve requestCurve;
}
```

`onRefresh` 和 `onLoading` 为空时，分别禁用对应的手势触发。`startRefresh()` 和 `startLoading()` 仍可用，因为业务可以在其他入口启动请求。

## 4. 数据与重建

`refreshCompleted()` 和 `loadComplete()` 不修改 items。替换、追加和清空数据均由业务方通过 items setter 完成。

```dart
state.items = firstPage;
state.refreshCompleted();

state.items = [...state.items, ...nextPage];
state.loadComplete();
```

`PaginatedList` 在监听到 `ChangeNotifier` 后会对比上一次的 items 引用、RefreshStatus 和 LoadStatus：

- items 改变时才重新执行 `itemsBuilder`；
- RefreshStatus 改变只重建 Header；
- LoadStatus 改变只重建 Footer；
- `refreshCompleted(resetLoadStatus: true)` 可在一次 `notifyListeners()` 中同时更新 Header 和 Footer。

父 Widget 提供了新的 `itemsBuilder`、`headerBuilder` 或 `footerBuilder` 实例时，对应区域也必须使用新 builder 重建。

## 5. UI 绑定与生命周期

一个 `PaginatedState` 同一时刻只能绑定一个 `PaginatedList`。第二个 UI 同时绑定时抛出 `FlutterError`，避免 `requestRefresh()` 无法判断应驱动哪个滚动位置。

UI 销毁后自动解绑，state 仍可继续保存 items 和业务状态。

UI 挂载时对 RefreshStatus 进行恢复：

| 挂载前状态 | 挂载行为 |
|---|---|
| `refreshing` | 保留，首帧即显示 Loading |
| `completed` | 在首次调用 Header builder 前归一为 `idle` |
| `failed` | 在首次调用 Header builder 前归一为 `idle` |
| `idle` / `canRefresh` | 归一为 `idle` |

这保证正在进行的请求在进入页面后可见，但不补播用户错过的成功/失败短动画。

LoadStatus 的 `loading`、`failed` 和 `noMore` 都在挂载时保留；`failed` 和 `noMore` 是持久的 Footer 状态。

## 6. 请求 API

### 6.1 requestRefresh / requestLoading

```dart
Future<void> requestRefresh();
Future<void> requestLoading();
```

两个 request 方法：

- 必须在 state 已绑定且 ScrollPosition 已 attach 的 UI 上使用；
- UI 未准备好时抛出带明确提示的 `StateError`，不仅依赖 debug assert；
- 对应回调为空时抛出 `StateError`；
- 先执行 UI 展示动画，再进入 `refreshing` / `loading`，然后调用回调；
- 返回的 Future 等待 UI 动画和对应的完整异步回调；
- 不自动根据 Future 成功或失败调用 complete/failed；
- 同类请求已在进行时不重复执行，返回已完成的 Future；
- 刷新和加载之间不互斥，可以同时为 `refreshing` 和 `loading`；
- `requestLoading()` 可以从 `failed` 或 `noMore` 程序化地强制进入 loading。

request API 不提供 `needMove` 和 `needCallback` 参数。UI 动画+回调是 request 的固定语义。

### 6.2 startRefresh / startLoading

```dart
void startRefresh();
void startLoading();
```

两个 start 方法：

- 不需要 UI；
- 不执行滚动动画；
- 不触发 `onRefresh` / `onLoading`；
- 只切换对应状态；
- 当已处于相同进行中状态时是幂等无操作；
- 可从其他终态直接进入 `refreshing` / `loading`；
- 开始新刷新时，作废旧的刷新结果展示计时器。

推荐业务回调主动调用 start，使同一方法也可被其他入口直接复用。由 request/手势调用时，start 因为幂等而不会重复通知。

```dart
Future<void> onRefresh() async {
  try {
    state.startRefresh();
    state.items = await fetchFirstPage();
    state.refreshCompleted();
  } catch (_) {
    state.refreshFailed();
  }
}
```

## 7. 状态机

### 7.1 RefreshStatus

```text
idle --下拉到阈值--> canRefresh
canRefresh --回拉到阈值内--> idle
canRefresh --松手--> refreshing + onRefresh()
idle/completed/failed --start/request--> refreshing
refreshing --refreshCompleted()--> completed
refreshing --refreshFailed()--> failed
* --refreshToIdle()--> idle
completed/failed --结果展示超时--> idle
```

UI 已挂载时，`completed` / `failed` 保留 `refreshResultDuration`，然后自动回到 `idle`。`refreshToIdle()` 跳过结果展示并立即收起 Header。

结果计时器必须使用操作序号或状态二次校验，防止旧计时器将新的 `refreshing` 错误改为 `idle`。

### 7.2 LoadStatus

```text
idle --到达末端阈值--> canLoading
canLoading --离开阈值--> idle
canLoading --松手/惯性确认--> loading + onLoading()
idle/failed/noMore --start/request--> loading
loading --loadComplete()--> idle
loading --loadFailed()--> failed
loading --loadNoData()--> noMore
noMore --resetNoData()--> idle
```

补充规则：

- `failed` 允许用户再次上拉重试；
- `noMore` 禁止手势加载，直到 `resetNoData()`；
- `resetNoData()` 在非 `noMore` 状态下无操作；
- `loadComplete()` 立即将状态切为 `idle`，不携带数据也不追加数据。

### 7.3 refreshCompleted 与 LoadStatus

```dart
void refreshCompleted({bool resetLoadStatus = true});
```

- 默认将任意 LoadStatus 重置为 `idle`；
- 传 `false` 时完全保留当前 LoadStatus；
- 重置加载 UI 状态不会取消业务已发出的异步加载请求；
- 刷新与加载同时执行时，旧加载结果的数据竞争由业务层处理。

## 8. 手势与滚动布局

### 8.1 触发时机

- 拖动达到阈值后只进入 `canRefresh` / `canLoading`；
- 手指松开后才正式进入请求状态并调用回调；
- 内容不足一屏时不自动加载；
- 内容不足一屏时，用户主动向末端拖动并松手仍可加载。

### 8.2 方向

`reverse: true` 不支持，检测到时抛出明确的 `FlutterError`。

| `scrollDirection` | Header / Refresh | Footer / Loading |
|---|---|---|
| `Axis.vertical` | 顶部，下拉触发 | 底部，上拉触发 |
| `Axis.horizontal` | 左侧，向右拉触发 | 右侧，向左拉触发 |

方向从 `itemsBuilder` 返回的 ScrollView 读取，不在 `PaginatedList` 上重复传入。

### 8.3 ScrollView 整合

`PaginatedList` 使用与 `SmartRefresher` 同类的思路：读取 `itemsBuilder` 生成的 ScrollView，将 Header、原内容 Sliver 和 Footer 组合到同一个滚动视口。

实现必须尽可能保留原 ScrollView 的：

- controller / primary；
- physics；
- padding；
- scrollDirection；
- cacheExtent；
- semanticChildCount；
- dragStartBehavior；
- keyboardDismissBehavior；
- restorationId；
- clipBehavior；
- CustomScrollView 的 center / anchor 等有效配置。

Header/Footer 位于内容 padding 之外。包注入的 ScrollPhysics 必须允许短内容在起始/末端被主动拖动，同时尊重 `NeverScrollableScrollPhysics` 的禁止滚动语义。

`NestedScrollView` 不在支持范围内，它本身也不是 `ScrollView` 子类。

## 9. 默认 Header/Footer

当对应 builder 为空时，包提供无文案、无本地化依赖的极简 UI：

- `refreshing` / `loading`：小型不确定进度指示器；
- `completed`：完成图标；
- `failed`：错误图标；
- `canRefresh` / `canLoading`：按当前轴向显示简单方向提示；
- `idle` / `noMore`：`SizedBox.shrink()`。

默认指示器根据竖向/横向选择主轴尺寸，不向公开 builder 额外传递 axis。

## 10. 错误与异步处理

- 业务回调负责调用 `refreshFailed()` / `loadFailed()`；
- 包不根据 Future 异常自动转换状态；
- 程序调用 `request*()` 时，未捕获的回调异常由返回的 Future 向调用方传播；
- 手势调用时，无调用方可 await，因此未捕获异常交由 `FlutterError.reportError` 报告；
- UI 在 request 动画中解绑时，本次 request 以 `StateError` 结束且不启动回调；
- UI 在业务回调执行中解绑时，不取消业务 Future，state 仍可被回调更新。

## 11. 使用示例

```dart
late final PaginatedState<Item> state;

@override
void initState() {
  super.initState();
  state = PaginatedState<Item>();

  // 可在 PaginatedList 尚未挂载时开始。
  refresh();
}

Future<void> refresh() async {
  try {
    state.startRefresh();
    state.items = await api.fetchFirstPage();
    state.refreshCompleted(); // 默认同时重置 LoadStatus
  } catch (_) {
    state.refreshFailed();
  }
}

Future<void> loadMore() async {
  try {
    state.startLoading();
    final nextPage = await api.fetchNextPage();

    if (nextPage.isEmpty) {
      state.loadNoData();
      return;
    }

    state.items = [...state.items, ...nextPage];
    state.loadComplete();
  } catch (_) {
    state.loadFailed();
  }
}

@override
Widget build(BuildContext context) {
  return PaginatedList<Item>(
    state: state,
    onRefresh: refresh,
    onLoading: loadMore,
    itemsBuilder: (items) => ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => ItemTile(items[index]),
    ),
    headerBuilder: (status) => switch (status) {
      RefreshStatus.idle => const SizedBox.shrink(),
      RefreshStatus.refreshing => const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        ),
      _ => const SizedBox(height: 48),
    },
  );
}

@override
void dispose() {
  state.dispose();
  super.dispose();
}
```

## 12. 测试策略

### 12.1 PaginatedState 单元测试

- 初始 items 被复制并且不可修改；
- items setter 每次产生新的不可变 List 并通知；
- 各个刷新/加载状态转移正确；
- 同状态 start 幂等；
- `refreshCompleted()` 默认将 LoadStatus 重置为 idle；
- `refreshCompleted(resetLoadStatus: false)` 保留 LoadStatus；
- `resetNoData()` 只处理 noMore；
- 复合状态更新只发出一次 ChangeNotifier 通知。

### 12.2 Widget 测试

- 竖向下拉刷新与上拉加载；
- 横向左侧刷新与右侧加载；
- 未达阈值松手不调用回调；
- 达阈值后松手只调用一次；
- failed 后可再次上拉，noMore 下手势不加载；
- 短内容不会在静止布局时自动加载；
- 短内容的主动末端拖动可加载；
- `startRefresh()` 在 UI 挂载前调用，挂载首帧显示 refreshing；
- 挂载前的 completed/failed 不在挂载后补播；
- UI 已挂载时的 completed/failed 在指定时长后回到 idle；
- 旧的结果计时器不会结束新刷新；
- `request*()` 等待完整回调；
- UI 未挂载或回调未配置时，`request*()` 抛出清晰错误；
- 刷新和加载可同时进行；
- 单 state 绑定多个 UI 时抛出错误；
- reverse ScrollView 抛出错误；
- items、Header 和 Footer 按变化类型精确重建；
- ListView、GridView 和 CustomScrollView 的核心滚动配置被保留。

## 13. 不在范围内

第一版明确不支持：

- `reverse: true`；
- `NestedScrollView`；
- 二楼刷新；
- Header 的 Follow/UnFollow/Behind/Front 多模式；
- Footer 的 ShowAlways/HideAlways/ShowWhenLoading 多模式；
- 实时 pulledExtent/progress builder 参数；
- 震动、全局配置、自动填满一屏、点击 Footer 重试等扩展功能；
- 页码、游标、API 调用、异步取消和数据竞争策略；
- items 自动替换、追加或清空。

## 14. 验收标准

实现完成时必须满足：

1. 文档中的公开 API 可编译，不存在旧的 Calculator 示例 API。
2. 所有 PaginatedState 状态转移都有单元测试。
3. 竖向和横向的刷新/加载 Widget 测试通过。
4. UI 挂载前的 `startRefresh()` 能在首帧显示 loading，且不触发回调。
5. `requestRefresh()` / `requestLoading()` 在 UI 可用时执行动画并等待完整回调，UI 不可用时给出明确错误。
6. 列表数据与状态终止方法保持分离，任何 complete 方法都不隐式替换或追加 items。
7. 刷新和加载可同时处于进行中状态。
8. items 对外始终是不可修改 List，且状态变化不会无意义重建 items ScrollView。
9. Flutter analyzer 与全部测试通过。
