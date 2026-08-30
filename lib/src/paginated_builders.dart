import 'package:flutter/widgets.dart';

import 'paginated_status.dart';

/// 根据不可修改的 [items] 构建包支持的滚动视图。
typedef PaginatedItemsBuilder<T> = ScrollView Function(List<T> items);

/// 根据刷新状态构建 Header。
typedef PaginatedHeaderBuilder = Widget Function(RefreshStatus status);

/// 根据加载状态构建 Footer。
typedef PaginatedFooterBuilder = Widget Function(LoadStatus status);

/// 构建首屏空状态或加载状态。
typedef FirstPageIndicatorBuilder = Widget Function();

/// 构建首屏错误状态，并接收可选的重试回调。
typedef FirstPageErrorIndicatorBuilder =
    Widget Function(VoidCallback? onTryAgain);
