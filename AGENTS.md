# 再漫画X 维护指引

再漫画X（ZAI-X）是再漫画的 Flutter 第三方客户端，Dart 包名为 `zai_x`。主要验证 Android、Windows 和 iOS。接手任务时先查看 [维护指南](docs/MAINTAINERS.md) 中对应的模块入口和回归测试，再沿调用链定位问题。

## 开发与验证

- 在仓库根目录运行 `flutter pub get`、`flutter analyze --no-fatal-infos` 和 `flutter test`。局部改动可先运行 `flutter test test/<文件名>_test.dart`。Flutter 版本以 [发布工作流](.github/workflows/build_release.yml) 为准。
- 现有页面用 GetX 绑定控制器，业务逻辑放在控制器或服务，官方接口集中在 `lib/requests/`。新增页面先确认它属于主路由还是内容子路由，并沿用 [AppNavigator](lib/routes/app_navigator.dart) 的入口。
- Windows 下用纯 ASCII 路径运行 Flutter 命令。功能优先验证 Android，涉及宽屏、键盘、自更新或平台插件时补做相应平台验证。修改 `lib/` 下运行时代码且已有应用在运行时，普通 UI 或方法改动做 hot reload，初始化或全局状态改动做 hot restart。
- 界面文字使用简体字面量和 `.i18n`。新增或修改界面文案后运行 `python tools/i18n/gen_dict.py`，检查生成差异。

## 兼容性与数据边界

- 保留 Hive box 名、持久化键、adapter 的 `typeId` 和字段编号。修改持久化数据结构时覆盖旧数据读取。修改 Protobuf 时保留既有字段编号和 wire 类型。
- 阅读位置、进入过的章节、末页已读是不同的状态。书架缓存与追平状态按账号隔离。外部漫画源复用阅读器 UI，通过 `ComicReaderSource` 保存自己的进度和收藏。
- 修改官方接口时核对请求版本、登录态和权限响应。`needLogin: true` 会在已有会话时附带凭证。漫画详情与章节的 `_v`、评论请求的认证和空结果语义都有现有回归记录。
- 账号、token、AI 配置和签名材料留在本地配置或 CI secrets。分享日志前遮蔽请求头、请求体及账号字段。发布 tag 和更新数据分支会触发远端操作，按当前任务的授权范围执行。
- 完成后记录实际运行的检查及结果。涉及实机、账号权限、后台任务或安装包更新时，区分自动化测试和实机验证。
