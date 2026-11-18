# ParcelHelper 修改记录 — 2026-11-18（基于 O96u/ParcelHelper v1.0.4）

## 改了什么

这次只改“已取了还显示运输中”这个你报的 bug，没有动 UI、没有加新功能。

1. `Shared/Models.swift` — `latestPickupConfirmed`
   - 补了漏掉的文案： bare “已取件”“已取出”“取件已完成”“已完成取件”“本人已签收”“签收人：本人”“已从快递柜取出”等。原来只认“您已取件”这种带前缀的， plain “快件已取件”认不出来。
   - 原来只看最新一条轨迹，改成扫全部轨迹 + 摘要：有的平台会在取件节点后面再贴一条通用文案，取件那条就被盖住了。
   - 补了直送规则：没有取件码、没有驿站名时，“已签收 / 已送达 / 已妥投”就等于本人已拿到（原来 Scripting 版平台同步里就是这条规则，Swift 版丢了）。有码、有驿站名的不算，驿站代签还是只显示“已签收”，不会误判成已取。

2. `App/NativePlatformSync.swift`
   - `arrivalKind` 里补了同一批文案（“已取件”“已取出”等），否则同步层和显示层各认一套。
   - `merge` 里补了直送规则：既有包裹最新文案是“已签收 / 已送达”，又无码无站时，同步后状态写成已取，不再一直挂在运输中。

3. `App/NativeTrackSearch.swift` — 手动查单入库
   - 原来只存轨迹文字、不写状态，手动查到的已取包裹入库后还是 status=1、显示运输中。现在入库时按上面的判定写 status=2 和取件时间；待取的补到站时间。

4. 测试
   - `Tests/ParcelStatusTests.swift`：16 个 Swift 断言，已接进 `Tests/DouyinParserTests.swift` 的 main。
   - `Tests/ParcelStatusCheck.py`：同一批用例的 Python 镜像版（这台机器没有 Swift 编译器，用它跑的验证，17/17 通过；旧逻辑在其中 7 个用例上是错的）。

## 没改的（先说清楚）

- 主屏幕小组件：原项目 README 自己写了“当前不提供可用的主屏幕小组件”，只有灵动岛 / 实时活动。这次没加，加小组件要新开一个 Widget Extension target、配 App Group，不是改几行代码的事，下一批再做。
- 后台刷新：iOS 不保证后台按时跑，原项目也写明了只在前台同步才可靠，这一点改代码解决不了。
- 平台同步（淘宝 / 京东 / 菜鸟 / 拼多多 / 丰巢 / 小米）走的都是各平台网页或私有接口，随时可能变，这次没动，只修了状态判定。

## 怎么变成 IPA（这台机器做不了）

这台机器是 Linux，没有 macOS / Xcode，所以我**没有编译、也没有出 IPA**，只能改源码 + 用 Python 镜像逻辑验证判定。

要出包，二选一：

1. 有 Mac + Xcode 16+：打开 `ParcelHelper.xcodeproj`，改签名和 Bundle ID，Archive 导出。
2. 没 Mac：把这份改好的源码推到你自己的 GitHub 仓库，仓库里自带的 `.github/workflows/build-ipa.yml` 会自动用 Xcode 构建并发布未签名 IPA，再自己签名安装（和原来 v1.0.4 的流程一样）。

注意：这个项目是 GPL-3.0 开源，如果你把改好的版本再分发，要按 GPL-3.0 的要求连同源码和许可证一起给。

## 还需要你确认的一件事

你那三个包裹的最新物流原文我还没看到。这次修的是最常见的几类文案，如果它们的原文是别的说法（比如“已妥投，签收人：XX”之外的写法），发我原文，我再补进词表里。

### 2026-11-18 17:25 补充：截图那单已确认

中通 79040463671372，最新轨迹“您已在新师范35号楼西头校园菜鸟驿站完成取件……”——关键是“完成取件”没有“已”字头，第一批补的“已完成取件 / 取件完成”都匹配不上。已把“完成取件 / 完成取货 / 取货成功”补进 `Models.swift`、`NativePlatformSync.swift` 和两份测试，Python 镜像验证 18/18 通过，zip 已重新打包。

### 2026-11-18 17:49 补充：小米绑定报 4001

截图是小米快递聚合页：账号显示“已授权”，但取件手机号“未绑定手机号”，点绑定时弹“账号操作 / 小米业务返回失败（4001）”，且“上次同步 无成功记录”。

- 4001 是什么：旧代码只把数字抛给用户，服务端的原文被丢了。按小米官方 SDK 错误码表，4001 = authToken 非法，请重新登录；4000 = authToken 过期，4002 = serviceToken 过期。这份接口本身是非官方逆向接口，码表只能作参考，但结合“已授权却调不通”来看，最可能就是存着的 serviceToken 已失效 / 不被接受，正确做法是解除授权后重新登录，而不是反复点绑定。
- 17:52 用户确认：失败发生在点“获取验证码”那一步，短信根本没发出来。
- **18:00 重要更正：作者本人当天也修了这个问题。** 用户 fork 的 main 分支（c6a5d4dc，2026-11-18 17:49 CST）已经包含上游的 4001 修复，真正的根因比“凭证过期”更具体：小米 assistant 接口要的是 `cUserId`，而旧代码在拿不到 `cUserId` 时会退回用账号域的 `userId` 存下来，看起来“已授权”，但每次调业务接口都会被服务端拒绝（4001）。上游同时修了 `isSuccess` 的掩盖 bug（顶层 code=4001 时 status.code=0 不能算成功）、STS 换 token 时缺少 `cUserId` 就报错、以及报错里带上具体步骤名（发送验证码 / 校验验证码 / 绑定手机号 / 包裹列表 / 物流详情）。本次推送已 rebase 到这个版本之上，没有覆盖上游的修复，只在报错里又补上了服务端的原文（desc/message），并把这部分抽成可测试的 `miEndpointErrorText`（`Tests/MiErrorTests.swift` / `Tests/MiErrorCheck.py`）。
- 还没法从截图确定的一点：这次失败是在“获取验证码”那一步，还是填了验证码点“绑定”那一步，弹窗标题都是通用的“账号操作”，看不出来。如果重新授权后还是 4001，把是在哪一步点的、以及那一步之前有没有收到短信验证码告诉我，我再往下查。
- 另外，“立即同步”是灰的不是 bug：没有绑定取件手机号时小米根本没法拉列表，按钮本来就是禁用的；先把手机号绑上、同步成功后才会有记录。

## 2026-11-18 18:06 第二批：Scripting v1.2.1 移植（未推送、未编译）

来源是用户新给的 `upload-2.scripting`（包裹助手 v1.2.1）。这批只改了本地工作副本 `~/workspace/ParcelHelper-main`，**没有推送到 GitHub，也没有编译**（本机是 Linux，没有 Xcode/Swift）。推上去之后 GitHub Actions 才会编 IPA。

### 移植了什么

**去重（`Shared/Storage.swift`）**
- `normalized()` 现在和 `NativePlatformSync.codeKey` 一致：全角转半角、去掉空白和 `-－—_`、转大写，全角数字或带横杠的运单号也能匹配上。
- 启动/保存时去重改成多键索引：每个包裹同时注册 `mail:{归一化运单号}` 和 `order:{订单号}` 两个键，合并后把新键全部指回幸存的那条，A==B、B==C 会传递合并，不再留一本重复账。
- 合并的基底不再是“轨迹节点多的那条”，而是 `trackUpdatedAt`（没有就用 `createdAt`）更新的那条；已取状态、手动标记、取件码都会合并， picked 的记录不会因为合并变回待取。
- 新增中央查找 `ParcelStore.findDuplicate(mailNo:orderId:)`：先按运单号（归一化）、再按订单号精确匹配。`upsert()` 建新记录前会先查它；`NativeParcelSync.merge` 里也在原有的“新已取/新已签收直接丢弃”守卫**之后**才查它，守卫的行为没变。
- 删除墓碑改成匹配包裹的**任意一个**身份键（原来只看第一个键），避免删掉的包裹换个运单号又被同步回来；手动重新添加时，`NativeTrackSearch.save`（手动查单保存）和 `importDouyin`（导入确认保存）会调用新增的 `removeDeletion(mail:order:)` 先清掉墓碑。

**快递鸟（`App/NativeTracking.swift`）**
- 新增纯函数 `needsClaim(reason:)`（另有 `kdniaoNeedsClaim` 供测试直接调用）：先排除“已领取 / 已领过 / 已使用 / 已过期 / 购买 / 充值 / 开通”，再匹配“请/需要/可/去……领取、未领取、领取……试用/免费、试用/免费……领取”。只有服务端明确让去领时，报错才会说“可领取免费试用名额”；其他失败仍原样转述服务端的话。
- **没有实现自动领取**：Swift 侧没有快递鸟的用户 token / 登录流程，领试用仍需去快递鸟官网手动操作。

**“刚查过”共享时间（`App/NativePlatformSync.swift` 的 `run()`）**
- 非强制同步时，某个平台在 10 分钟内已经同步成功过就直接跳过（返回“10 分钟内已同步过，已跳过”），不再重复请求；`force=true`（手动点同步、登录后首次同步）不受影响。
- 没有加 App Group 共享：这个 App 没有主屏幕小组件，Live Activity 是 App 自己推送的，不需要跨进程共享时间。

**唯品会（新增 `App/VipExpress.swift` + `App/LooseOrder.swift`）**
- GET `https://mapi.vip.com/vips-mobile/rest/order/mina_programs/get_union_order_list/v1`，query 参数按 `vip.ts` 原样写（api_key `8cec5243ade04ed3a02c5972bcda0d3f`、mobile_platform=2、app_name=shop_wap 等，page=1、page_size=50）；`mars_cid` 从 vip.com 的 Cookie 里取，同时放进 query 和 Cookie 头，**绝不自己编**（编一个就等于换设备，会话立刻失效）；code 为 1 或 200 算成功，“User id not found”按登录失效处理。
- 订单解析走新增的宽松取值器 `LooseOrder`（`orderLoose.ts` 的移植）：对象拍平成小写键（深度 ≤5），按字段名正则找 orderSn、运单号、商品名、状态、快递公司、时间；只取近 30 天的订单；没有运单号的订单只更新已有卡片，不新建。
- 有运单号的前 4 单会顺带用已有的 `cainiaoTrack` 查一次轨迹。
- 账号页新增唯品会入口（登录页 `https://m.vip.com/v3/index.html#/pages/userCenter/userCenter`，以 VIP_TANK / m_vipruid / WAP[login] 任一 Cookie 为登录标志），同步列表和“同步全部”里都已接好。

**得物（新增 `App/DewuOrders.swift`）**
- 打开 `https://m.dewu.com/router/order/buyer/orderList` 的 WKWebView，documentStart 时注入 `dewu.ts` 的 XHR 钩子，把页面自己发的 buyerOrderList 响应收进 `window.__dw`，等约 7 秒后读出来，取最后一条 200 响应里的 `data.orderList`，同样走 `LooseOrder` 解析；只取近 60 天；得物不做轨迹刷新。
- 401 会明确报错“得物接口要求原生签名，网页里签不出来（401）”，不做假数据。
- 得物只在前台手动/登录同步时跑，**没有**加进 `NativeHomeRefresh` 的自动轮询（那里没有 WebView）；账号页新增得物入口（登录页就是订单页本身，以 X-Auth-Token / xAuthToken / duToken 任一 Cookie 为登录标志）。

**空状态（`App/Views.swift`）**
- 取件页和包裹页原来就已经有“包裹都取完啦 / 还没有这类包裹”的空状态，这次没动；只给之前会一片空白的“驿站管理”页补了一句“还没有驿站记录，有包裹到站后会自动建档，也可以点右上角加号手动添加。”
- 唯品会 / 得物在账号页暂时没有品牌图标（Assets 里没有 `brand_vip` / `brand_dewu`），先用中性占位徽章代替；包裹卡片上的来源角标已补“唯”“得”。

### 刻意没移植 / 没做的事

- **小米平台保留**：Scripting v1.2.1 里小米聚合已经下线，但 Swift 版里小米是正常工作的、用户也在用，所以 `mi` 仍在同步列表里，这是有意的分歧，不是遗漏。
- **VIP_AUTO_STEP（`loginFix.ts` 的 `window.__vipA.step()`）没接**：它是往登录页里定时注入 JS、自动走完登录步骤的状态机；Swift 的 `PlatformWebLogin` 只有 Cookie 监听和拼多多的一次性 token 脚本，没有周期性执行 JS 的机制，不想为此新造一个登录视图，所以唯品会登录仍是普通网页登录，需要用户自己在页面上点完登录。
- **快递鸟自动领试用没做**：见上文，需要 token 登录流程，Swift 侧没有。
- **快捷指令改动没移植**：iCloud 链接、控制中心截屏识别是 Scripting 宿主侧的能力，不属于这个原生 App。
- **没有编译、没有出 IPA**：本机 Linux，没有 Xcode/Swift。Swift 写法已尽量保持简单，但仍需在 Mac 或 GitHub Actions 上编一次才能发现编译问题。
- **没有推送**：按任务要求，本批只改本地工作副本。

> 注意（rebase 记录）：写这批代码时发现，本地的 `App/PlatformAccounts.swift` 还是最初 zip 里的旧版，而 fork 远端（82518e44）已经包含上游后来加的拼多多 `NativeWebAutoSync` 集成。如果直接按本地旧版推，会把那部分改动覆盖掉。所以 `PlatformAccounts.swift` 是先取回远端版本、再把本批的三处改动（唯品会/得物入口、多 Cookie 登录标志、品牌图标占位）重新接上去的；其余文件与远端逐一 diff 过，只有本批的改动。

### 测试（Python 镜像，本机可跑的部分）

- `Tests/NeedsClaimCheck.py`：16/16 通过（7 条可领取、9 条不可领取）。
- `Tests/LooseOrderCheck.py`：通过（唯品会风格平铺订单、得物风格嵌套订单、运单号不能拿订单号顶替、13 位/10 位/日期字符串时间解析）。
- `Tests/ParcelStatusCheck.py`：18/18 通过（第一批的逻辑没动过）。
- `Tests/MiErrorCheck.py`：通过（小米报错文案没动过）。
- Swift 侧新增 `Tests/DedupeTests.swift`（6 项：全角数字、横杠空格、订单号、双键顺序、过短不算运单号、空）、`Tests/NeedsClaimTests.swift`（16 项）、`Tests/LooseOrderTests.swift`（16 项），都已接进 `Tests` 的 main；**Swift 测试本身在本机跑不了**，需随 Xcode 编译一起验证。

### 需要在真机上验证的事

- 唯品会：登录后 `mars_cid` 能不能从 Cookie 里拿到、订单列表第一页能不能返回、订单里真实的字段名（宽松解析器目前是按字段名猜的，两个手册账号都是 0 单，没有实证）。
- 得物：7 秒等待够不够抓到 buyerOrderList、页面在不挂到视图层级的 WKWebView 里会不会被节流、401 是不是真会出现。
- 去重：同一运单被淘宝/京东/拼多多各同步一条时，启动时能不能并成一条；手动删掉又手动加回来的包裹，下一次同步会不会再出现。
- 快递鸟：服务端回“请领取免费试用”时，报错是不是明确提示可领取。
