import 'package:flutter/widgets.dart';

import 'paginated_status.dart';

/// 根据不可修改的 [items] 构建包支持的滚动视图。
///
/// 首屏指示器展示期间也会调用本 builder 获取滚动配置，但不渲染列表内容。
typedef PaginatedItemsBuilder<T> = ScrollView Function(List<T> items);

/// 根据视图展示状态构建 Header，可能不同于业务快照（例如结果已收起）。
typedef PaginatedHeaderBuilder = Widget Function(RefreshStatus status);

/// 根据视图展示状态构建 Footer；canLoading 仅属于手势展示。
typedef PaginatedFooterBuilder = Widget Function(LoadStatus status);

/// 构建首屏空状态或加载状态。
typedef FirstPageIndicatorBuilder = Widget Function();

/// 构建首屏错误状态，并接收可选的重试回调。
typedef FirstPageErrorIndicatorBuilder =
    Widget Function(VoidCallback? onTryAgain);
