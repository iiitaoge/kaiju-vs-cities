# Analytics 接入

本项目同时使用 Roblox 原生漏斗与第三方 GameAnalytics（GA）：原生漏斗回答关键路径在哪一步流失，GA 回答技术状态、玩法行为、资源流和实际数值。分析失败不会阻断玩法。

## GameAnalytics 配置

在 Studio 中选中 `ServerStorage/GameAnalytics` 文件夹，设置 Attributes：

| Attribute | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `GameAnalyticsGameKey` | String | 是 | 32 位 GA Game Key |
| `GameAnalyticsSecretKey` | String | 是 | 40 位 GA Secret Key |
| `GameAnalyticsBuild` | String | 否 | 数据 Build，缺省 `0.1.0` |
| `GameAnalyticsDebug` | Boolean | 否 | SDK 调试日志，缺省 `false` |

凭据不进入源码，而是由 Argon 同步 `ServerStorage/GameAnalytics` 文件夹的 Attributes。凭据无效或文件夹缺失时 GA 保持关闭，玩法继续运行。Place 必须开启 HTTP Requests。正式发布前应修改 `GameAnalyticsBuild`，以便按版本隔离调试期和正式数据。

## Roblox 原生漏斗

所有原生漏斗只从服务器发送。重复流程每次使用新的 GUID `FunnelSessionId`；只有相邻步骤成功才前进，防止客户端跳步污染转化率。

### `SessionLoad`

1. `Player Joined`
2. `Save Ready`
3. `Playable`

`Playable` 表示存档、Plot、City、Monster 和 Character placement 均完成。

### Onboarding（一次性新手漏斗）

1. `Playable`
2. `First City Built`
3. `First Cash Collected`
4. `First City Level 2`
5. `First Monster Built`
6. `Attack Targets Loaded`
7. `Attack Target Selected`
8. `First Attack Accepted`

最后一步是服务器接受攻击，而不是客户端点击；已完成当前教程版本的玩家不会重复进入。

### `AttackLaunch`

1. `Management Opened`
2. `Start Clicked`
3. `Targets Loaded`
4. `Target Selected`
5. `Attack Requested`
6. `Attack Accepted`

### `MonsterUpgrade`

1. `Management Opened`
2. `Upgrade Clicked`
3. `Upgrade Completed`

进攻与防守怪兽都进入该漏斗，并以 SpawnPointId 绑定同一次管理会话。

### `Rebirth`

1. `Panel Opened`
2. `Eligible`
3. `Execute Clicked`
4. `Save Committed`
5. `Runtime Reloaded`

资格、存档提交和运行时重载均使用服务器权威结果。

Studio 只用于验证调用链和错误；Roblox Creator Dashboard 的线上漏斗必须在已发布体验中验证。

## GameAnalytics 事件字典

### 技术与安全

- `Technical:Load:*`：加入、各运行时加载阶段、Playable、失败原因和耗时。
- `Technical:Persistence:<Phase>:Fail`：Load、Save、Snapshot、Replacement 失败。
- `Technical:Rebirth:SaveCommitted`：重生存档已提交。
- `Security:*`：服务器网络边界拒绝，按玩家、入口和原因聚合 60 秒。

### UI 意图

- `UI:Monster:*`：管理界面打开/关闭、升级点击。
- `UI:Attack:*`：开始、选择目标、取消、不可用和本地校验失败。
- `UI:Rebirth:*`：面板打开、执行点击。

UI 意图来自低信任客户端，只允许固定白名单和稳定 SubjectId；服务器要求数据 Ready、校验怪兽已建造或玩家靠近重生按钮，并以每人 10 秒最多 30 条限流。客户端不能上报金额、等级或成功结果。

### 玩法与成长

- `Gameplay:Region:*`：产钱区解锁、建造、升级。
- `Gameplay:Boost:*`：收入倍率、生命倍率、自动领取购买。
- `Gameplay:Income:*`：手动领取。
- `Gameplay:Monster:*`：进攻/防守怪兽建造、升级、升级拒绝。
- `Gameplay:Attack:*`：目标列表、请求接受/拒绝、战斗完成与结束原因。
- `Gameplay:Defense:*`：守方承受一次攻击的结果。
- `Gameplay:Rebirth:*`：资格、完成、失败。
- GA Progression：教程步骤、区域等级、Boost、攻防怪兽等级、重生次数及失败。

### 资源流与数值

所有金额和等级都读取服务器已提交的实际结果，分析层不复制平衡配置，因此以后替换正式数值不需要重写埋点。

| 范围 | 记录内容 | 时机 |
| --- | --- | --- |
| Money Source | 手动收入、自动收入、Boost 开启自动领取时的存量收入、战斗奖励 | 实际入账；自动收入按区域聚合 60 秒 |
| Money Sink | 区域解锁/建造/升级、Boost、进攻/防守怪兽建造/升级 | 实际扣款成功 |
| 余额 | `Metric:Economy:Balance:*` | Playable、重生完成、每 60 秒、关键收入/支出后 |
| 本轮收入/重生 | `Metric:Progression:RunEarnings`、`RebirthCount` | Playable、重生完成；本轮收入另每 60 秒 |
| 产钱区 | 是否解锁、等级、收入倍率、生命倍率、自动收入、已解锁总数 | Playable、重生完成；变更时另记 Progression/Metric |
| 怪兽 | 每个进攻/防守 SpawnPoint 的等级（未建造为 0）、已建造总数 | Playable、重生完成；建造/升级时另记 Progression |
| 攻击 | 时长、摧毁房屋、奖励、击败守怪、塔命中、承受塔伤 | 每次攻击完成 |

Studio 金钱作弊和测试脚本不会生成 Resource Source/Sink 行为事件；Studio 快照仍可能反映测试时的当前余额。项目目前没有真实 Robux/Marketplace 成交链路，因此暂不伪造付费事件，接入购买系统时应在服务器收据确认后增加 Business Event。

## SDK 来源

仓库内置官方 GameAnalytics Roblox SDK `2.2.6`：

- 仓库：`https://github.com/GameAnalytics/GA-SDK-ROBLOX`
- 固定提交：`f391708741f4620f26d5dcbc7fd445b7637893b2`
- 本地目录：`src/Shared/Vendor/GameAnalytics`
- 许可证：`src/Shared/Vendor/GameAnalytics/LICENSE.txt`
