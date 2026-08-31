## Unreleased

* 修复动画期间外部刷新已经结束后仍重复请求的问题。
* 首屏指示器复用原始视口配置，避免横向或带 Key 的列表在刷新展示时使请求失效。

* Breaking: PaginatedState 改为不可变快照，转换方法返回新值；可直接作为 Riverpod Notifier 状态。
* 新增 isNoMore；刷新成功原子更新数据并始终重置加载状态。
* 程序化请求迁移到可选 PaginatedController，状态无需绑定、监听或 dispose。
* 手势瞬态和结果收起由视图管理，提示收起不修改业务结果。
* 新快照保留滚动和请求会话；Widget Key 控制会话更换。
* 增加 Riverpod 示例、字段选择监听及生命周期回归测试。

## 0.0.1

* 提供下拉刷新、上拉加载与程序化请求。
* 支持 ListView、GridView、CustomScrollView、横向、reverse 和 RTL。
* 提供不可修改 items 快照、刷新/加载状态机及可定制指示器。
* Header/Footer builder 改为必填，不再提供默认指示器。
