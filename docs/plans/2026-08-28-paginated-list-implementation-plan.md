# PaginatedList 实施计划

## 1. 计划目标

本计划将 [PaginatedList 设计规格](../spark/2026-08-28-paginated-list-design.md) 拆分为 12 个可独立实施、测试和验收的 Task。实施期间不增加规格外功能，不引入第三方运行时依赖。

## 2. 任务依赖

```text
Task 1
  ├─→ Task 2 ─→ Task 3
  └─→ Task 4 ─→ Task 5 ─→ Task 6

Task 3 + Task 6 ─→ Task 7 ─→ Task 8
                              ├─→ Task 9
                              └─→ Task 10

Task 8 + Task 9 + Task 10 ─→ Task 11 ─→ Task 12
```

关键路径是 Task 4–8：ScrollView 重组、边缘手势、Indicator 布局和 request 动画必须在同一滚动模型上完成。

## 3. 通用执行规则

每个 Task 都必须：

1. 只修改该 Task 声明的范围，不顺手扩展功能。
2. 先写或更新对应测试，再完成实现。
3. 至少运行该 Task 相关的定向测试。
4. 保持 `dart format` 和 analyzer 通过。
5. 不修改用户已有的无关工作树变更。
6. 如果 Flutter SDK 内部 API 与规格假设不一致，停在当前 Task 记录证据，不通过放宽公开 API 绕过问题。

---

## Task 1：建立公开 API 骨架

### 目标

建立包的文件边界、枚举、typedef 和对外导出，让后续 Task 在稳定的命名上开发。

### 涉及文件

- `lib/paginated_list.dart`
- `lib/src/paginated_status.dart`
- `lib/src/paginated_builders.dart`
- `test/public_api_test.dart`
- 删除或替换 `test/paginated_list_test.dart` 中的 Calculator 模板测试

### 实施步骤

1. 定义 `RefreshStatus` 和 `LoadStatus`，值与设计规格完全一致。
2. 定义 `PaginatedItemsBuilder<T>`、`PaginatedHeaderBuilder` 和 `PaginatedFooterBuilder`。
3. 将根 library 改为只导出公开类型，不导出 internal 实现。
4. 为枚举和 typedef 添加公开 API 文档注释。

### 测试与验收

- 测试从 `package:paginated_list/paginated_list.dart` 导入全部公开类型。
- 编译时验证 `PaginatedItemsBuilder<T>` 接受 `ListView`、`GridView` 和 `CustomScrollView` 返回值。
- 工程中不再存在 `Calculator`。

### 建议提交

`feat: define pagination public API`

---

## Task 2：实现 PaginatedState 数据与状态机

### 目标

完成不依赖 UI 的 `PaginatedState<T>` 核心，包括不可变 items、刷新/加载状态转移和原子通知。

### 涉及文件

- `lib/src/paginated_state.dart`
- `test/paginated_state_test.dart`

### 实施步骤

1. 实现 `PaginatedState<T> extends ChangeNotifier`，构造器只接收可选 items。
2. 对初始 items 和每次 setter 输入使用 `List.unmodifiable(...)` 创建新副本。
3. 实现只读 `refreshStatus` 和 `loadStatus`。
4. 实现 `startRefresh()`、`startLoading()` 的幂等状态切换。
5. 实现 `refreshCompleted({resetLoadStatus = true})`、`refreshFailed()` 和 `refreshToIdle()`。
6. 实现 `loadComplete()`、`loadFailed()`、`loadNoData()` 和 `resetNoData()`。
7. 确保复合操作先完成全部字段变更，再只调用一次 `notifyListeners()`。

### 测试与验收

- 覆盖全部合法状态转移。
- 验证同状态 start 不通知。
- 验证 items 无法原地增删。
- 验证 setter 之后修改原输入 List 不影响 state。
- 验证 `refreshCompleted()` 的默认重置和 `false` 保留分支。
- 验证 `resetNoData()` 在非 noMore 状态下不通知。

### 建议提交

`feat: add pagination state machine`

---

## Task 3：建立 State 与 UI 的单客户绑定

### 目标

为 `requestRefresh()` / `requestLoading()` 建立不公开 Flutter State 细节的内部调用端口，并保证一个 state 只驱动一个 UI。

### 涉及文件

- `lib/src/paginated_state.dart`
- `lib/src/internal/paginated_binding.dart`
- `test/paginated_binding_test.dart`

### 实施步骤

1. 定义包内私有 binding/port，只暴露 request 所需的异步方法。
2. 在 state 中实现 bind、unbind 和身份校验。
3. 第二个客户绑定时抛出包含解决建议的 `FlutterError`。
4. 未绑定 UI 时，`request*()` 抛出 `StateError`并建议使用 `start*()`。
5. 将 request 的实际 UI 执行委托给 binding，state 不直接保存 `BuildContext`、`State` 或 `ScrollPosition`。
6. dispose state 时使 binding 失效；UI unbind 后 state 仍可使用 start 和结束方法。

### 测试与验收

- 单绑定、重复绑定、错误客户解绑和解绑后重新绑定均有测试。
- UI 未绑定时 request 错误类型和提示文案稳定。
- start 方法不依赖 binding。

### 建议提交

`feat: bind pagination state to one view`

---

## Task 4：验证 ScrollView 重组可行性

### 目标

用最小实验验证当前 Flutter SDK 下，可以从 `ListView`、`GridView` 和 `CustomScrollView` 构建同等内容 Sliver，并在前后插入动态 Header/Footer。

### 涉及文件

- `test/internal/scroll_view_composition_spike_test.dart`
- 必要时创建 `lib/src/internal/scroll_view_composer.dart`

### 实施步骤

1. 核对 Flutter SDK 中 `ScrollView.buildSlivers` 和 `BoxScrollView.buildChildLayout` 的当前签名与 protected 约束。
2. 为三类 ScrollView 构建最小组合实验。
3. 验证 padding 只包裹原内容，Header/Footer 位于 padding 外。
4. 验证原 controller、physics、axis 和常用 ScrollView 配置可被保留。
5. 将不可避免的 protected API 使用集中在一个 internal 文件，不散布 analyzer ignore。
6. 如当前 SDK 无法稳定重组，本 Task 停止并输出需回到设计规格调整的证据，不继续 Task 5。

### 测试与验收

- ListView、GridView 和 CustomScrollView 组合后内容数量和顺序正确。
- Header 在内容之前，Footer 在内容之后。
- 实验没有引入第三方依赖。
- 对当前 Flutter SDK 的脆弱点有注释和定向测试保护。

### 建议提交

`test: validate ScrollView composition`

---

## Task 5：实现 ScrollView Composer 与配置保留

### 目标

将 Task 4 的实验收敛为可维护的生产实现，为后续 Indicator 和手势处理提供单一 CustomScrollView。

### 涉及文件

- `lib/src/internal/scroll_view_composer.dart`
- `test/internal/scroll_view_composer_test.dart`

### 实施步骤

1. 实现 ScrollView 属性提取和内容 Sliver 组合。
2. 保留设计规格列出的 controller、primary、physics、padding 及其他通用属性。
3. 确保不将同一 ScrollController 同时 attach 到原 ScrollView 和新 ScrollView。
4. 检测 `reverse: true` 并抛出稳定的 `FlutterError`。
5. 根据返回 ScrollView 的 `scrollDirection` 设置合成视口。
6. 给内部组合器添加小范围 API 注释，禁止对外导出。

### 测试与验收

- 覆盖 ListView、GridView、CustomScrollView，并至少覆盖 padding 和外部 ScrollController。
- 验证竖向和横向属性。
- reverse 错误信息包含不支持原因。

### 建议提交

`feat: compose paginated ScrollViews`

---

## Task 6：实现边缘 Physics 与手势状态

### 目标

实现长内容和短内容的起始/末端拖动，将拖动距离转换为 `idle` / `canRefresh` / `canLoading`，并且只在松手或惯性确认时触发请求。

### 涉及文件

- `lib/src/internal/paginated_scroll_physics.dart`
- `lib/src/internal/paginated_gesture_coordinator.dart`
- `test/internal/paginated_gesture_test.dart`

### 实施步骤

1. 在用户 physics 之上组合 Paginated physics，允许边缘拖动和 request 驱动。
2. 显式尊重 `NeverScrollableScrollPhysics`，不偷偷恢复手势。
3. 统一使用 leading/trailing 边缘概念，避免竖向和横向各写一套状态机。
4. 当起始端距离达到 `refreshTriggerDistance` 时进入 canRefresh，回到阈值内恢复 idle。
5. 当末端距离达到 `loadingTriggerDistance` 时进入 canLoading，离开阈值恢复上一持久状态。
6. 松手或合法惯性滚动确认后才调用内部触发函数。
7. 实现 failed 手势重试和 noMore 手势禁止。
8. 确保短内容完成布局不会自动触发，仅主动拖动可触发。

### 测试与验收

- 未到阈值松手不触发。
- 到达阈值时先进入 can 状态，松手后只触发一次。
- 回拉到阈值内取消 can 状态。
- failed 可重试，noMore 不触发。
- 短内容静止不加载，主动末端拖动可加载。

### 建议提交

`feat: handle pagination edge gestures`

---

## Task 7：实现动态 Indicator Host 和默认 UI

### 目标

在同一滚动视口中渲染尺寸由 builder 决定的 Header/Footer，并实现可选 builder 的极简默认视觉。

### 涉及文件

- `lib/src/internal/paginated_indicator_host.dart`
- `lib/src/internal/default_indicators.dart`
- `test/internal/paginated_indicator_test.dart`

### 实施步骤

1. 实现可安置在 leading/trailing 的 Indicator host/sliver。
2. 让 child 的实际尺寸决定当前占用空间，不引入固定 headerExtent/footerExtent。
3. 状态改变时重新布局，但不自动添加 `AnimatedSize`。
4. 自定义 builder 原样嵌入 host，不额外包装文案、高度或显隐策略。
5. 实现默认进度、完成、失败和 can 状态图形；idle/noMore 返回 `SizedBox.shrink()`。
6. 默认指示器根据 axis 切换主轴尺寸和方向提示。

### 测试与验收

- builder 每次收到正确状态，不接收 context 或 pulledExtent。
- `SizedBox.shrink()` 的 idle 内容不占主轴空间。
- 不同状态返回不同尺寸时，视口可重新布局且无异常。
- builder 为 null 时默认 UI 可见。
- 横向与竖向布局都通过测试。

### 建议提交

`feat: render pagination indicators`

---

## Task 8：集成 PaginatedList 与完整请求流

### 目标

组合 State binding、ScrollView composer、手势协调和 Indicator host，完成公开 `PaginatedList<T>` 及 `request*()` 端到端行为。

### 涉及文件

- `lib/src/paginated_list.dart`
- `lib/src/paginated_state.dart`
- `lib/src/internal/paginated_binding.dart`
- `test/paginated_request_test.dart`

### 实施步骤

1. 实现设计规格中的 `PaginatedList<T>` 构造器与默认值。
2. 在 `initState`、`didUpdateWidget` 和 `dispose` 中正确绑定/解绑 state。
3. UI 挂载前将历史 completed/failed/canRefresh 归一为 idle，但保留 refreshing。
4. 实现 request 的 UI-ready 校验、回调存在性校验和同类请求去重。
5. request 先完成展示动画，再切换状态并调用/等待完整异步回调。
6. 手势触发使用同一内部请求路径，但不重复执行程序化滚动动画。
7. 程序 request 将异常传播给调用方；手势触发的未捕获异常使用 `FlutterError.reportError`。
8. 使用操作 token 防止 UI 在动画中解绑后仍触发回调。
9. 保留刷新和加载相互独立的去重 token，不强制互斥。

### 测试与验收

- `await requestRefresh()` 和 `await requestLoading()` 等待完整回调。
- 同类重复 request 不重复执行。
- 刷新与加载可同时执行。
- noMore 下的 `requestLoading()` 仍能强制请求。
- UI 不可用、回调为 null、动画中 dispose 均有确定结果。
- `start*()` 不会因 UI 状态监听而误触发回调。

### 建议提交

`feat: integrate paginated request flow`

---

## Task 9：完成刷新结果生命周期

### 目标

实现 UI 已挂载时 completed/failed 短暂展示后归一的逻辑，并防止旧计时器结束新请求。

### 涉及文件

- `lib/src/paginated_list.dart`
- `lib/src/internal/refresh_result_coordinator.dart`
- `test/refresh_result_lifecycle_test.dart`

### 实施步骤

1. 监听 RefreshStatus 进入 completed/failed，启动 `refreshResultDuration` 计时。
2. 计时结束时二次校验状态与操作 token，只结束原结果状态。
3. `startRefresh()`、`requestRefresh()` 和 `refreshToIdle()` 作废旧 token。
4. UI dispose 时取消计时器但不擅自改写 state；之后挂载时按历史结果归一规则处理。
5. 完成结果展示后进入 idle，触发 Header 收起/重新布局。

### 测试与验收

- completed 和 failed 按配置时长展示。
- `refreshToIdle()` 立即收起。
- 结果期间的新刷新不会被旧计时器改成 idle。
- 结果期间 dispose 后无定时器回调异常。
- 挂载前已完成/失败的状态不闪现结果 UI。

### 建议提交

`feat: settle refresh result states`

---

## Task 10：实现精确重建与 Widget 更新

### 目标

确保 ChangeNotifier 的统一通知不会导致 items ScrollView 在每次 Header/Footer 状态变化时重新构建。

### 涉及文件

- `lib/src/paginated_list.dart`
- `lib/src/internal/selected_listenable_builder.dart`
- `test/paginated_rebuild_test.dart`

### 实施步骤

1. 为 items、RefreshStatus 和 LoadStatus 各建立内部 selector/snapshot。
2. 只当选中值变化时重建对应区域。
3. items 引用变化时重新调用 `itemsBuilder`，状态变化时复用已构建 ScrollView。
4. `didUpdateWidget` 检测 state 和三个 builder 实例变化，正确换绑与失效缓存。
5. 确保更换 state 时旧 state 不再影响 UI。

### 测试与验收

- 使用计数 builder 验证三个区域的调用次数。
- Header 多次状态变化不重新调用 `itemsBuilder`。
- items 更新不重新调用未变的 Header/Footer builder。
- 父 Widget 替换 builder 闭包后使用新闭包。
- 换绑 state 无重复监听或泄漏。

### 建议提交

`perf: isolate pagination rebuilds`

---

## Task 11：完成端到端 Widget 测试矩阵

### 目标

将前面各 Task 的单点验证扩展为公开 API 端到端测试，覆盖竖向、横向、短内容、错误、并发和生命周期。

### 涉及文件

- `test/paginated_list_vertical_test.dart`
- `test/paginated_list_horizontal_test.dart`
- `test/paginated_list_lifecycle_test.dart`
- `test/paginated_list_error_test.dart`

### 实施步骤

1. 创建可重用测试 fixture，提供可控尺寸、可控 Future 和回调计数。
2. 完成竖向 leading/trailing 手势测试。
3. 完成横向左/右手势测试。
4. 完成 ListView、GridView、CustomScrollView 兼容性测试。
5. 完成 UI 挂载前 start、历史结果归一、dispose 中的 request 测试。
6. 完成回调异常传播/报告测试。
7. 完成同类去重和刷新/加载并行测试。
8. 完成默认 Indicator 和自定义动态尺寸 Indicator 测试。

### 测试与验收

- 设计规格第 12 节列出的每个场景至少对应一个测试。
- 测试不依赖真实时间或网络。
- 全部 Future、Timer 和 animation 在测试结束前被确定性地驱动完成或取消。

### 建议提交

`test: cover pagination interactions`

---

## Task 12：更新示例、README 并完成发布前验证

### 目标

用可运行示例和公开文档完成交付，并对整个包进行最终静态检查和测试。

### 涉及文件

- `example/lib/main.dart`
- `README.md`
- `CHANGELOG.md`
- `pubspec.yaml`
- 前面 Task 创建的所有 `lib/` 和 `test/` 文件

### 实施步骤

1. 在不覆盖用户无关改动的前提下，将 example 改为可操作的首页刷新+后续页加载示例。
2. 示例展示提前 `startRefresh()`、items 替换/追加、noMore 和错误分支。
3. README 说明安装、核心 API、生命周期、状态机和不支持范围。
4. CHANGELOG 记录首个可用版本的功能与限制。
5. 将 pubspec description 替换为准确包描述，检查 SDK 约束与实际使用 API 相容。
6. 运行格式化、analyzer、全部测试以及 example 的静态检查。
7. 运行 `flutter pub publish --dry-run`，修正包结构和元数据问题，但不实际发布。
8. 对照设计规格验收标准逐项勾选。

### 测试与验收

- `flutter analyze` 通过。
- `flutter test` 全部通过。
- example 通过 analyzer，手势示例能覆盖刷新、加载、失败和 noMore。
- `flutter pub publish --dry-run` 无阻断错误。
- README 中的 API 名称与实际导出一致。

### 建议提交

`docs: document PaginatedList usage`

---

## 4. 可并行性建议

在不产生重叠文件编辑的前提下：

- Task 2 和 Task 4 可在 Task 1 后并行；
- Task 7 的默认 UI 部分可在 Task 6 手势实现期间并行，但 Indicator host 需使用 Task 5 的组合结果；
- Task 9 和 Task 10 可在 Task 8 后并行；
- Task 11 必须在 Task 8–10 后统一收口；
- Task 12 最后执行，避免 README 和 example 频繁追随未稳定 API 变更。

## 5. 里程碑

### 里程碑 A：核心状态可用

完成 Task 1–3。此时公开命名、items 不可变规则、状态机和 UI binding 契约已稳定。

### 里程碑 B：滚动内核可用

完成 Task 4–7。此时竖向/横向 ScrollView 重组、边缘拖动和动态 Indicator 已可单独测试。

### 里程碑 C：公开组件可用

完成 Task 8–10。此时 `PaginatedList` 的 request、生命周期和精确重建行为完整。

### 里程 D：可交付

完成 Task 11–12。全部测试、示例、README 和发布前检查通过。

## 6. 最终完成定义

只有同时满足以下条件，整个实施计划才算完成：

1. 12 个 Task 的验收项全部通过。
2. 公开 API 与设计规格一致，无未记录的破坏性变更。
3. 竖向和横向的手势、request 和生命周期测试通过。
4. 无第三方运行时依赖。
5. analyzer、全部测试和 publish dry-run 通过。
6. 示例与 README 可独立指导用户完成提前刷新、下拉刷新和上拉加载。
