# Data Tracker 产品文档 v0.1

日期：2026-06-03

## 1. 产品概述

Data Tracker 是一个面向个人使用的健康数据追踪系统，由 iOS App、macOS App 和 OpenClaw Skills 三个一等产品组成。

它的核心目标不是做一个普通健康看板，而是让个人 Agent 可以持续、结构化地理解用户的健康与生活数据，并围绕当前目标「减重」提供记录、分析、提醒和建议。

产品闭环如下：

```text
OpenClaw 通过对话收集生活数据
macOS App 提供本地 Agent API 和同步队列
iOS App 负责 HealthKit 读写与用户确认
Apple Health 保存标准健康数据
Data Tracker 解释趋势并辅助决策
```

Data Tracker 不替代 Apple Health。Apple Health 是标准健康数据的最终归档；Data Tracker 是 Agent 工作流、数据包同步、记录修正和趋势解释层。

## 2. 当前产品判断

Apple Watch 和 Apple Health 已经能自动记录一部分关键数据：

- Workout
- Active Energy
- Steps
- Heart Rate
- 其他设备自动产生的健康样本

因此 Data Tracker v0.1 不应该重复创建运动记录。第一阶段真正缺失、也最影响减重目标的数据是：

- 饮食摄入
- 体重

产品应优先补齐这两类数据，再把它们和 Apple Health 中已有的运动消耗数据结合，用来估算热量缺口、体重趋势和减重进展。

## 3. 目标用户

当前目标用户是产品所有者本人。

用户画像：

- 使用 iPhone、Apple Watch、Mac、Tailscale、Codex 和 OpenClaw。
- 希望本地 Agent 可以访问自己的健康数据。
- 当前核心目标是减重。
- 偏好通过 Agent 对话完成复杂记录，而不是手动填写复杂表单。
- 接受 iOS App 作为看板、确认页和必要的快速录入口。

v0.1 是单用户产品。多人使用、App Store 分发、云服务和商业化不在当前范围内。

## 4. 核心交付物

Data Tracker 的核心产出是三件套。

### 4.1 iOS App

iOS App 是 HealthKit 的执行端和移动端确认界面。

主要职责：

- 请求 HealthKit 权限。
- 从 Apple Health 读取健康数据。
- 将 Data Tracker 生成的记录写入 Apple Health。
- 展示减重相关看板。
- 展示最近饮食、体重、运动记录。
- 展示 OpenClaw / Mac 生成的数据包同步状态。
- 允许用户检查、编辑、删除 Data Tracker 自己写入 Apple Health 的记录。
- 从 Mac 拉取待写入的数据包。
- 将 HealthKit 写入结果回传给 Mac。

iOS App 不只是一个开关。它是用户确认「到底写入了什么健康数据」的可信界面。

### 4.2 macOS App

macOS App 是本地 Agent Gateway 和同步协调器。

主要职责：

- 作为菜单栏应用运行。
- 提供本地 HTTP API 给 OpenClaw / Codex / 其他 Agent。
- 接收 iOS 上报的 HealthKit 数据。
- 接收 OpenClaw 创建的 Health Packet。
- 管理待同步到 iOS 的数据包队列。
- 保存 Agent 工作流审计信息。
- 保存 Health Packet 与 HealthKit object UUID 的映射。
- 提供 Agent 友好的健康上下文接口。
- 展示服务状态、API 地址、最近同步时间、待同步数量和错误状态。

macOS App 不作为标准健康数据的最终数据源。它保存的是 Agent 工作流、同步队列和审计数据。

### 4.3 OpenClaw Skills

OpenClaw Skills 负责指导 OpenClaw 按 Data Tracker 的模式跟踪用户生活。

主要职责：

- 通过对话收集饮食记录。
- 提醒用户称重。
- 估算热量和宏量营养素。
- 标记估算置信度。
- 创建 Health Packet。
- 调用 macOS App API 写入队列。
- 读取健康上下文。
- 生成每日和每周减重总结。
- 根据趋势给出行为建议。

OpenClaw Skill 不只是 API 使用说明。它应该让 OpenClaw 像一个轻量的个人健康运营助手。

## 5. 数据真相模型

Data Tracker 采用分层数据真相。

### 5.1 Apple Health

Apple Health 是标准健康事实的最终归档。

示例：

- 体重
- 摄入热量
- 蛋白质
- 碳水
- 脂肪
- Workout
- Active Energy
- Steps
- Heart Rate

只要某个数据可以用 HealthKit 标准类型表达，并且用户授权，Data Tracker 就应尽量写入 Apple Health。

### 5.2 macOS 本地存储

Mac 本地存储是 Agent 工作流的记录层。

示例：

- 用户原始描述
- Agent 解析结果
- 食物文本
- AI 估算过程
- 估算置信度
- 同步状态
- 写入失败原因
- HealthKit object UUID 映射
- 修订历史

这些信息 Apple Health 不能完整表达，但它们对 Agent 的解释、追踪和修正很重要。

### 5.3 iOS App

iOS App 是 HealthKit 写入执行端。

Mac 和 OpenClaw 不能直接写入 iPhone 上的 HealthKit。Agent 生成的健康记录必须先变成 Health Packet，由 iOS App 拉取并写入 Apple Health。

## 6. Health Packet

Health Packet 是 Data Tracker 中的一组结构化健康数据包。

它不是最终健康归档，而是一次写入 Apple Health 的指令、上下文和审计单元。

### 6.1 MVP Packet 类型

v0.1 只支持两类 Health Packet。

#### FoodIntakePacket

用途：

- 记录一餐、一次零食，或一段饮食摄入。
- 将摄入热量和营养数据写入 Apple Health。

建议字段：

- `packetId`
- `type = food_intake`
- `source`
- `occurredAt`
- `mealType`
- `rawText`
- `foodItems`
- `estimatedCaloriesKcal`
- `proteinGrams`
- `carbohydrateGrams`
- `fatGrams`
- `confidence`
- `estimationNotes`
- `status`
- `healthKitObjectIds`
- `revision`
- `createdAt`
- `updatedAt`

原则：

- 热量是必填。
- 蛋白质、碳水、脂肪是可选但推荐。
- AI 估算一定有误差，所以必须记录置信度和估算说明。

#### WeightPacket

用途：

- 记录一次体重。
- 将体重写入 Apple Health。

建议字段：

- `packetId`
- `type = body_weight`
- `source`
- `measuredAt`
- `weightKg`
- `rawText`
- `note`
- `status`
- `healthKitObjectIds`
- `revision`
- `createdAt`
- `updatedAt`

原则：

- 体重可以通过 OpenClaw 录入，也可以通过 iOS App 快速录入。
- 如果未来用户使用智能秤自动写入 Apple Health，Data Tracker 的体重写入链路可以不用。
- 看板始终从 Apple Health 读取所有体重记录，无论来源是不是 Data Tracker。

### 6.2 暂不支持的 Packet 类型

以下类型暂不进入 v0.1：

- WorkoutPacket
- SleepPacket
- MoodPacket
- HabitPacket
- GoalPacket

原因：Workout 已由 Apple Watch 写入 Apple Health。Data Tracker 应该先读取和分析运动数据，而不是主动创建运动数据。

## 7. 核心流程

### 7.1 通过 OpenClaw 记录饮食

1. 用户告诉 OpenClaw 今天吃了什么。
2. OpenClaw 估算热量和宏量营养素。
3. OpenClaw 在不确定时询问补充信息。
4. OpenClaw 创建 FoodIntakePacket。
5. macOS App 将 packet 标记为待 iOS 同步。
6. iOS App 拉取 pending packet。
7. iOS App 写入 Apple Health。
8. iOS App 将 HealthKit object UUID 回传给 Mac。
9. macOS App 将 packet 标记为已写入。
10. iOS App 看板展示新的饮食记录。

### 7.2 通过 OpenClaw 记录体重

1. OpenClaw 提醒用户称重。
2. 用户告诉 OpenClaw 体重。
3. OpenClaw 创建 WeightPacket。
4. iOS App 写入 Apple Health body mass sample。
5. iOS App 回传写入状态。
6. 看板从 Apple Health 更新体重趋势。

### 7.3 通过 iOS App 快速记录体重

1. 用户打开 iOS App。
2. 用户进入快速录入体重。
3. iOS App 写入 Apple Health。
4. iOS App 将这条记录同步给 Mac，供 Agent 后续理解上下文。

该流程很重要，因为一段时间内用户不会有自动写入体重的设备。

### 7.4 编辑 Data Tracker 记录

1. 用户在 iOS App 打开最近饮食或体重记录。
2. 用户修改数值或内容。
3. iOS App 判断该记录是否由 Data Tracker 创建。
4. 如果是 Data Tracker 创建，删除旧 HealthKit objects。
5. iOS App 写入新的 HealthKit objects。
6. packet revision +1。
7. iOS App 将新映射和状态回传给 Mac。

注意：

- HealthKit 的 quantity sample 不可变。
- 编辑的本质是删除旧样本并重新写入。
- Data Tracker 只能编辑或删除自己写入的记录。
- 其他 App 或 Apple Health 手动创建的记录，只读展示。

### 7.5 Agent 读取健康上下文

1. OpenClaw 调用 Mac API。
2. Mac 返回最近健康数据、同步状态和 packet 状态。
3. OpenClaw 使用这些上下文做提醒、总结和建议。

## 8. iOS App 需求

### 8.1 看板

iOS 看板应优先围绕减重展示：

- 当前体重
- 7 日平均体重
- 体重趋势
- 最近摄入热量
- 最近运动消耗
- 估算热量缺口
- 最近 workouts
- 最近饮食记录
- 最近体重记录

看板不追求展示所有健康数据，而是优先回答：

```text
我最近有没有稳定制造热量缺口？
体重趋势是否朝目标移动？
今天还有什么需要记录？
```

### 8.2 记录页

iOS App 应支持：

- 饮食记录列表
- 体重记录列表
- 运动记录列表
- 记录详情页
- Data Tracker 记录的编辑
- Data Tracker 记录的删除
- 非 Data Tracker 来源记录的只读展示

### 8.3 同步状态

iOS App 应展示：

- 健康上报是否开启
- 最近成功上报时间
- 待写入 packet 数量
- 最近 HealthKit 写入结果
- 当前 Mac endpoint
- 错误状态

## 9. macOS App 需求

### 9.1 菜单栏应用

菜单栏窗口应展示：

- 服务是否运行
- Agent API 地址
- iPhone 上报地址
- Tailscale 备用地址
- 最近接收时间
- 最近报告生成时间
- 待同步 packet 数量
- 最近 packet 写入状态
- 刷新按钮
- 退出按钮

### 9.2 本地 HTTP API

Mac App 应提供：

- Agent context API
- 最新 report API
- Daily summary API
- Recent samples API
- Recent workouts API
- 创建 Health Packet API
- Pending packet API
- Packet 状态 API
- Packet 修订历史 API

API 设计原则：

- JSON 稳定。
- 明确单位。
- 明确数据新鲜度。
- 明确当天数据可能不完整。
- 同时提供机器可读字段和 Agent 易理解的摘要。

## 10. OpenClaw Skill 需求

OpenClaw Skill 应定义 Agent 行为模式，而不只是提供脚本。

### 10.1 每日追踪行为

OpenClaw 应：

- 询问用户是否已称重。
- 在饮食缺失时自然提醒用户记录。
- 避免过度打扰。
- 明确说明食物热量是估算。
- 只有在不确定性过高时追问。
- 在信息足够时创建 packet。

### 10.2 分析行为

OpenClaw 应：

- 优先使用趋势体重，而不是单日体重。
- 使用 7 日和 14 日窗口。
- 结合摄入热量、运动消耗和体重趋势。
- 解释水分、盐分、碳水对体重波动的影响。
- 避免医疗诊断。
- 给出可执行的下一步建议。

### 10.3 Skill 工具能力

Skill 应支持：

- 读取健康上下文。
- 创建 FoodIntakePacket。
- 创建 WeightPacket。
- 查询待同步 packet。
- 查看最近饮食和体重记录。
- 生成每日总结。
- 生成每周复盘。

## 11. 减重分析模型

MVP 应支持：

- 最近 7 天摄入热量总计
- 最近 7 天摄入热量均值
- 最近 7 天运动消耗
- 最近 7 天 workout 次数
- 当前体重
- 7 日平均体重
- 14 日体重趋势
- 估算热量缺口或盈余

可以使用粗略估算：

```text
7700 kcal ~= 1 kg body fat
```

但产品不能假装这个模型很精确。体重会受到水分、盐分、糖原、排便、称重时间等因素影响。产品应强调趋势，而不是单日数值。

## 12. 隐私与安全原则

Data Tracker 是个人、本地优先产品。

原则：

- Agent API 只暴露在本机和 Tailscale 内网。
- 不提供公网健康数据 API。
- 不把 token、真实个人数据、私密配置提交到 git。
- 不默认把健康数据发给第三方服务。
- 不做医疗诊断。
- AI 热量估算必须被视为近似值。
- Agent 生成的写入记录必须保留审计链路。

## 13. MVP 范围

### 13.1 In Scope

- iOS 读取 Apple Health。
- iOS 写入饮食摄入。
- iOS 写入体重。
- iOS 展示饮食和体重记录。
- iOS 编辑 / 删除 Data Tracker 自己写入的记录。
- Mac 管理 Health Packet 队列。
- Mac 提供本地 Agent API。
- OpenClaw Skill 支持饮食和体重追踪。
- 减重看板展示摄入、运动、体重和热量缺口。

### 13.2 Out Of Scope

- 多用户。
- App Store 分发。
- 云后端。
- 社交功能。
- 完整食物数据库。
- 条形码扫描。
- 自动智能秤接入。
- 医疗诊断。
- 主动创建 workout。
- 编辑其他 App 创建的 Apple Health 记录。

## 14. 待确认问题

这些问题不阻塞 PRD v0.1，但会影响后续实现。

1. FoodIntakePacket 写入 Apple Health 时，是写 food correlation，还是只写独立 quantity samples？
2. iOS 手动录入时，是先由 iOS 创建 packet，再同步给 Mac，还是所有 packet 都必须由 Mac 分配 ID？
3. OpenClaw 创建饮食 packet 前，是否必须让用户确认估算结果？
4. 饮食记录列表是否按餐次分组：早餐、午餐、晚餐、零食？
5. Mac 本地保留 packet 审计历史多久？
6. iOS App 是否需要支持「今日还未记录饮食」这种提醒状态？

## 15. 建议实现顺序

1. 在 `Sources/Shared` 定义 Health Packet 数据模型。
2. 增加 Mac 本地 packet store。
3. 增加 Mac packet API。
4. 增加 iOS pending packet 拉取。
5. 增加 iOS 写入 body weight 到 HealthKit。
6. 增加 iOS 写入 dietary energy 到 HealthKit。
7. 增加 iOS 饮食 / 体重记录列表。
8. 增加 iOS 编辑 / 删除 Data Tracker 记录。
9. 更新 OpenClaw Skill，支持创建 FoodIntakePacket 和 WeightPacket。
10. 增加减重看板中的摄入、体重和热量缺口指标。

## 16. 产品原则

Data Tracker 不是一个传统 calorie app，也不是 workout app，更不是 Apple Health 的替代品。

它是一套个人健康数据闭环：

```text
OpenClaw 捕捉生活上下文
Mac 协调 packet 和 Agent API
iOS 写入并校验 HealthKit
Apple Health 保存标准健康事实
Data Tracker 解释长期趋势
```

