# 再漫画X 开发与维护指南

再漫画X（ZAI-X）是再漫画的 Flutter 第三方客户端，包含漫画、轻小说、资讯、账号任务和离线下载。应用连接再漫画服务，另有本地漫画索引、可选 AI 功能和独立的 Hitomi 漫画源。Android、Windows 和 iOS 有发布流程。macOS、Linux 保留工程目录。

改动前用本指南定位入口。应用版本以 [pubspec.yaml](../pubspec.yaml) 为准，Flutter 版本和打包参数以 [发布工作流](../.github/workflows/build_release.yml) 为准。对外功能、设计演进和历史验证分别见 [README](../README.md)、[路线图](ROADMAP.md) 和各版 `docs/QA-*.md`。

## 本地开发

从仓库根目录执行。发布 CI 使用 Flutter **3.47.2**，Android 构建使用 JDK 17。SDK 版本变更时核对 CI 与 `pubspec.lock`，其中的 SDK 下限可能高于 `pubspec.yaml` 的声明。

```powershell
flutter --version
flutter doctor -v
flutter pub get
flutter devices
flutter run -d <设备ID>
```

- Android 准备 Android SDK 和模拟器或真机。Windows 桌面构建需要 Visual Studio 的 C++ 桌面开发工具链。iOS 需在 macOS 配好 Xcode、CocoaPods，工程部署目标为 iOS 15。
- Windows 上 Flutter 命令应从纯 ASCII 路径执行。已有中文目录的工作副本可按 [README 的开发说明](../README.md#开发) 使用目录联接访问同一份文件。
- 默认入口是 [lib/main.dart](../lib/main.dart)。无账号或 AI 配置也可启动，登录后才可验证云书架、同步、任务和账号权限。AI 配置缺省时，相关功能入口会隐藏。
- Android 性能诊断使用 `flutter build apk --profile -t tools/profile_app.dart`，通过 `adb logcat -s flutter` 查看 `ZMH_PROFILE`。该入口输出帧耗时、缓存和内存数据。

## 架构与启动流程

| 路径 | 职责 |
| --- | --- |
| [lib/modules/](../lib/modules/) | 按业务划分的页面与 GetX 控制器，常见配对是 `*_page.dart` 或 `*_view.dart` 加 `*_controller.dart`。 |
| [lib/routes/](../lib/routes/) | 路由常量、页面绑定、导航帮助方法和资讯链接分流。 |
| [lib/services/](../lib/services/) | 应用设置、账户生命周期、Hive、本地索引、AI、下载和更新。 |
| [lib/requests/](../lib/requests/) | 各业务的官方 API 请求。共享 Dio 客户端、端点和鉴权逻辑在 `requests/common/`。 |
| [lib/models/](../lib/models/) | API 数据模型、Hive 持久化模型、Protobuf 生成代码。 |
| [lib/app/](../lib/app/) 与 [lib/widgets/](../lib/widgets/) | 主题、简繁转换、事件总线、基础控制器及可复用组件。 |
| [assets/](../assets/) 与 [tools/](../tools/) | 随包资源、协议源文件及生成、索引、签到、性能诊断工具。 |

1. [main.dart](../lib/main.dart) 初始化 Flutter binding，Windows 先做单实例检查，随后初始化 Hive。
2. `initServices()` 先打开本地设置，再让 `UserService` 恢复会话。注册 Hive adapter、打开业务 box 后合并云端阅读记录，接着准备字体、阅读统计、应用设置和下载服务。
3. Android 与 iOS 初始化 Workmanager 并安排订阅检查。后台 `callbackDispatcher` 位于独立 isolate，使用通知服务自己的持久化状态。登录与退出会刷新后台任务的凭证，应用恢复前台会补查可领取任务。
4. `DMZJApp` 通过 `GetMaterialApp` 进入 [IndexPage](../lib/modules/index/index_page.dart)。首页以 `IndexedStack` 保留已打开分区。分区 ID 由 [IndexController](../lib/modules/index/index_controller.dart) 维护，可选分区的显示顺序独立于 ID。

### 路由与状态

- [AppPages](../lib/routes/app_pages.dart) 用 `routes` 注册主路由，用 `generateSubRoute` 生成内容子路由。详情、列表等通过 [AppNavigator.toContentPage](../lib/routes/app_navigator.dart) 进入嵌套 Navigator（ID 1），漫画和小说阅读器在主路由全屏打开。
- 阅读器退出时会检查详情页是否仍在内容栈，并处理部分 Android 设备的重复返回事件。改导航时覆盖正常返回、系统返回和详情页随阅读器一起被弹出的场景。
- 列表、详情可复用 [BasePageController / BaseDataController](../lib/app/controller/base_controller.dart) 的加载和错误状态。跨页面更新先查看 [EventBus](../lib/app/event_bus.dart) 的已有事件，例如章节完成和书架刷新。

## 常见任务入口

| 任务 | 优先查看 | 相关测试 |
| --- | --- | --- |
| 漫画详情、神隐、权限 | [漫画详情控制器](../lib/modules/comic/detail/comic_detail_controller.dart)、[ComicRequest](../lib/requests/comic_request.dart)、[索引说明](comic-index.md) | [comic_hidden_detail](../test/comic_hidden_detail_test.dart) |
| 普通搜索、索引补齐 | [漫画搜索控制器](../lib/modules/comic/search/comic_search_controller.dart)、[小说搜索控制器](../lib/modules/novel/search/novel_search_controller.dart)、[ComicIndexService](../lib/services/comic_index/comic_index_service.dart)、[SearchHistoryService](../lib/services/search_history_service.dart) | [comic_index](../test/comic_index_test.dart)、[comic_index_update](../test/comic_index_update_test.dart)、[search_history](../test/search_history_test.dart) |
| 阅读器、换话、断点续读 | [漫画阅读控制器](../lib/modules/comic/reader/comic_reader_controller.dart)、[小说阅读控制器](../lib/modules/novel/reader/novel_reader_controller.dart)、[换话手势](../lib/widgets/chapter_swipe_boundary.dart)、[单作品阅读设置](../lib/services/comic_reader_preferences.dart) | [comic_reader_resume](../test/comic_reader_resume_test.dart)、[chapter_swipe_boundary](../test/chapter_swipe_boundary_test.dart)、[reader_back_restore](../test/reader_back_restore_test.dart)、[novel_history_sync](../test/novel_history_sync_test.dart) |
| 书架、订阅、追平状态 | [书架页](../lib/modules/bookshelf/bookshelf_page.dart)、[订阅控制器](../lib/modules/user/subscribe/comic/comic_subscribe_controller.dart)、[书架快照](../lib/services/comic_shelf_repository.dart)、[章节完成状态](../lib/services/comic_completion_service.dart) | [comic_shelf](../test/comic_shelf_test.dart)、[subscribe_update_sort](../test/subscribe_update_sort_test.dart) |
| 评论、账号和任务 | [CommentRequest](../lib/requests/comment_request.dart)、[UserRequest](../lib/requests/user_request.dart)、[UserService](../lib/services/user_service.dart)、[UserExamService](../lib/services/user_exam_service.dart) | [task_model](../test/task_model_test.dart)、[user_exam](../test/user_exam_test.dart)、[v2.4.1 评论修复记录](QA-v2.4.1.md) |
| 资讯正文与链接跳转 | [资讯详情页](../lib/modules/news/detail/news_detail_page.dart)、[NewsRequest](../lib/requests/news_request.dart)、[链接分流](../lib/routes/news_link_resolver.dart)、[图片跳转](../lib/routes/news_image_navigation_resolver.dart) | [news_link_resolver](../test/news_link_resolver_test.dart)、[news_image_navigation_resolver](../test/news_image_navigation_resolver_test.dart) |
| AI 搜索与答题 | [搜索会话](../lib/services/ai/ai_search_session.dart)、[搜索管线](../lib/services/ai/ai_search_pipeline.dart)、[答题器](../lib/services/ai/ai_exam_solver.dart)、[AI 请求客户端](../lib/services/ai/ai_chat_client.dart) | [ai_search_pipeline](../test/ai_search_pipeline_test.dart)、[ai_search_engine](../test/ai_search_engine_test.dart)、[ai_service_config](../test/ai_service_config_test.dart) |
| Hitomi 来源与阅读 | [来源入口](../lib/modules/hitomi/hitomi_page.dart)、[请求与图片规则](../lib/modules/hitomi/hitomi_source.dart)、[阅读器适配](../lib/modules/hitomi/hitomi_reader.dart)、[本地记录](../lib/modules/hitomi/hitomi_library.dart) | [hitomi_entry](../test/hitomi_entry_test.dart)、[hitomi_pagination](../test/hitomi_pagination_test.dart)、[external_comic_reader](../test/external_comic_reader_test.dart) |
| 离线内容下载与导出 | [漫画下载](../lib/services/comic_download_service.dart)、[小说下载](../lib/services/novel_download_service.dart)、[下载任务实现](../lib/services/download_task/)、[CBZ 导出](../lib/services/cbz_export_service.dart) | 用对应平台复核任务状态、重启恢复和已下载内容打开。 |
| 应用更新与 Windows 覆盖安装 | [更新元数据](../lib/requests/common_request.dart)、[更新服务](../lib/services/app_update_service.dart)、[断点续传](../lib/services/resumable_download.dart)、[Windows 安装与回滚](../lib/services/windows_self_update.dart) | [github_update_source](../test/github_update_source_test.dart)、[resumable_download](../test/resumable_download_test.dart)、[windows_self_update](../test/windows_self_update_test.dart) |

## 容易回归的边界

**官方请求与权限。** [HttpClient](../lib/requests/common/http_client.dart) 提供 JSON、文本、字节和 V4 解密请求。`checkCode` 在适用的响应上检查 `errno`，99 会触发会话失效处理。GET 默认参数随 `needLogin` 选择是否携带 uid，已登录时附加 Bearer token。神隐详情与章节依赖 [Api.APP_VERSION](../lib/requests/common/api.dart) 对应的 `_v` 参数，图像是否可读仍由服务端权限决定。评论列表在缺少登录凭证时可能成功返回空数据。排查时分别验证游客、已登录和权限不足的结果。

**本地存储与同步。** [LocalStorageService](../lib/services/local_storage_service.dart) 的 `LocalStorage` box 保存设置、会话和部分功能缓存。[DBService](../lib/services/db_service.dart) 管理阅读历史、进入过的章节和本机收藏等业务 box。Hive 数据及离线下载使用系统应用支持目录。云端历史的秒级时间先转换为 `DateTime`，再与本机时间比较。修改 box、键、adapter 或数据格式时，验证旧版本升级后能继续读取。

**阅读器与书架。** 普通阅读历史用于恢复章节和页码，章节完成状态用于判断追平。末页图片加载成功并实际显示后才自动完成，手动标记也会更新。加载中退出、过时的异步响应、预加载图片及评论尾页都需要保护已保存位置。订阅列表用 `last_updatetime` 排序，按账号读取缓存，切换账号后丢弃旧请求结果。外部漫画源经 [ComicReaderSource](../lib/modules/comic/reader/comic_reader_source.dart) 传入图片请求头、进度和收藏回调，使用独立的阅读偏好命名空间。

**本地索引与 AI。** 普通漫画搜索把本地索引作为官方结果的补充，按 ID 去重，并按官方接口分页是否结束决定补齐范围。索引更新会验证大小、版本和笔数后替换。AI 搜索按「规划条件 → 多来源收集候选 → 补简介 → 模型筛选」执行，继续搜索沿用当前运行状态。维护时保留取消、已评估作品去重及失败批次重试语义。AI 请求的数据边界见 [隐私政策](PRIVACY.md)。

**应用更新。** GitHub Release 代理与直连回退、续传、完整性校验和安装是独立步骤。Windows 需验证 ZIP 及其 SHA-256、暂存解压、安装目录写权限、旧进程退出、替换失败回滚及重新启动。[Windows 实机验证记录](QA-2026-09-29-windows-self-update.md) 提供复测场景。

## 生成文件与配置

| 改动 | 生成或配置方式 |
| --- | --- |
| 界面文案 | [i18n.dart](../lib/app/i18n.dart) 在运行时简转繁。使用 `opencc-python-reimplemented` 后运行 `python tools/i18n/gen_dict.py` 生成 `lib/app/i18n_dict.g.dart`。合并上游时见 [README 的开发说明](../README.md#开发)。 |
| 索引搜索字表、漫画分类标签 | `python tools/i18n/gen_t2s.py` 生成 `lib/app/t2s_chars.g.dart`，`python tools/tags/fetch_tags.py` 从官方接口生成 `lib/models/comic/comic_tag_table.g.dart`。标签脚本会访问上游，修改标签规则时再运行。 |
| Hive adapter | 源文件与生成文件同在 [lib/models/db/](../lib/models/db/)。变更带注解的模型后用 `dart run build_runner build` 生成，检查 `typeId`、字段编号及旧数据的缺省行为。 |
| Protobuf | 协议源在 [assets/proto/](../assets/proto/)，生成物在 [lib/models/proto/](../lib/models/proto/)。生成工具版本见 [路线图](ROADMAP.md)，协议改动需运行 [proto_wire_decode_test.dart](../test/proto_wire_decode_test.dart)。 |
| 本地漫画索引 | [comic_index 构建工具](../tools/comic_index/build_comic_index.dart) 生成 `assets/comic_index/` 的快照格式。增量、全量命令及文件格式见 [索引说明](comic-index.md)。全量重建会大量请求上游。 |
| AI 服务 | 仓库外的 JSON 使用 `baseUrl`、`apiKey`、`model`，端点须为 HTTPS，兼容 `/chat/completions`。通过 `dart run tools/ai/make_ai_defines.dart --in <配置.json> --out <ai_defines.json>` 生成构建配置，运行或构建时传 `--dart-define-from-file=<ai_defines.json>`。混淆值可从安装包还原，服务端负责实际用量限制。 |

生成物随仓库提交，常规启动和测试可以直接使用。AI 配置、登录数据、签名文件放在仓库外或 CI secrets。调试日志可能包含完整请求头和请求体，分享前做脱敏。

## 验证与发布

```powershell
flutter analyze --no-fatal-infos
flutter test test/comic_reader_resume_test.dart  # 示例，按改动选择目标测试
flutter test
```

- 发布 CI 允许 info 级别提示，error 和 warning 会使分析失败。优先复用 `test/` 中的 fixture 和 fake。真机或在线验证记录平台、登录条件、实际操作和结果。
- [build_release.yml](../.github/workflows/build_release.yml) 手动触发可生成测试产物，推送 `v*` tag 会执行 Release 上传。通过分析和测试后构建 `ZAI-X-android.apk`、`ZAI-X-windows-x64.zip`、`ZAI-X-ios-unsigned.ipa`。打包会尝试采用经笔数校验的 `comic-index` 分支快照，取不到有效快照时沿用仓库版本。
- Android 正式包使用既有签名以支持覆盖安装，应用 ID 为 `com.xycz.zmhx`。签名配置由 `android/zai_key.properties` 读取，缺省时 Gradle 使用 debug 签名。CI 从 `ZAI_AI_CONFIG` 注入可选 AI 配置。iOS CI 产物未签名，TestFlight 由 macOS 上的签名上传流程处理。发版核对 `pubspec.yaml` 版本、tag、产物名称、签名与 Release digest，记录方式见 [v2.4.1 发版记录](QA-v2.4.1.md)。
- [comic_index.yml](../.github/workflows/comic_index.yml) 定时增量更新 `comic-index` 数据分支。[daily_signin.yml](../.github/workflows/daily_signin.yml) 是独立的可选定时签到，需显式启用，和 App 启动签到分开。[Issue 自动化](../.github/codex/README.md) 有自己的分析、补丁验证和发布流程。
