# 峡谷餐厅 · 河港夜市

## 原版服务链

在 Fork 基线 cc4e4ef 上，用 gdtoolkit 的 GDScript 语法解析了 scripts 下 35 份脚本、615 个函数。调用边来自语法树，订单所有权和时序根据函数内的条件与赋值核对。安装 gdtoolkit 后，可用 `python3 tools/gameplay_ast.py` 在当前版本重跑。

| 玩家观察到的现象 | 源码入口与规则 | 可观测指标 |
| --- | --- | --- |
| 空桌仍有客人离开 | `simulation.step → _assign_seats` 按客组人数匹配桌型，`_apply_patience` 处理等待期限 | 拒客数、排队耗时 |
| 客人已经点好，厨房尚无单 | `_dispatch_waiter → _set_task` 分派接单，`_complete_action` 在 ORDER 时创建订单，在 SUBMIT 时写入 submitted_tick | 点单等待、出餐前等待 |
| 多份订单在灶台处积压 | `_dispatch_chef` 预订灶台和订单，`_arrive_task` 决定烹饪截止 tick，`_complete_action` 按 batch_yield 生成食物并绑定订单 | 灶台利用率、出餐前等待 |
| 餐品已到窗口，客人仍在等 | `_dispatch_waiter` 从可取的出餐口订单里优先选创建最早的一份。唯有 DELIVER 确认食物在服务员身上，客人才转入 EATING | 出餐后等待、等餐扣分 |
| 客人付款，日报生成 | `_checkout` 检查 payment_committed 防止重复结账，`_record_food_wait` 按 pass_tick 切分等待，`_close_day` 汇总 | 实收、完餐率、两段平均等待 |

出餐前等待包含传单、排炉、烹饪和搬运。仅凭这个数字不能断定灶台不足，需同时看灶台利用率。相同种子、桌位和采购配置下，可用两段等待比较技能施放时机。此处没有把设计参数当作实测收益。

## 从联盟机制到经营决策

| 参考机制 | 本版触发条件 | 在经营模拟里的结果 |
| --- | --- | --- |
| 迅捷蟹的河道加速区域、希维尔的团队提速 | 营业时点击「河道急送」。出餐口周围 2 格内的移动信使触发加速，区域持续 8 秒，冷却 28 秒 | 信使移速 ×1.5，离开区域后延续 3 秒。水流跟随出餐口，走位、占用、取餐和结账继续走原状态机。适合出餐后积单 |
| 布兰德的三层触发 | 每名厨师独立累计已完成锅数，第三锅开火时触发「三锅旺火」 | 该锅烹饪用时减半。以整锅计数，多份拼盘算一锅。特效跟随该厨师，产量、食物 ID 和品质规则沿用原实现 |

时间统一取模拟 tick。暂停时冷却、加速和灶火停在当前帧，快进时同步推进。开店重置技能，夜晚和日报继续使用原有检查点。

## 素材对照

封面、九宫格底板、图标、信使与厨师行走帧、水流和灶火均使用本次生成的图像。封面、技能栏见 scenes/title.tscn 与 scenes/service_skills.tscn。原作顾客与街景沿用原绘制系统。音乐入口是标题场景的 Soundtrack 节点，绑定有游戏使用授权的 AudioStream 可贯穿营业过程。

- [GitHub 英雄技能图标目录](https://github.com/TheePepS/League_Of_Legends_Assets/tree/master/Champions_Spells_Assets)
- [希维尔 R 图标](https://github.com/TheePepS/League_Of_Legends_Assets/blob/master/Champions_Spells_Assets/Sivir_On_The_Hunt.png)
- [布兰德被动图标](https://github.com/TheePepS/League_Of_Legends_Assets/blob/master/Champions_Spells_Assets/Brand_Blaze.png)
- [GitHub 英雄头像目录](https://github.com/TheePepS/League_Of_Legends_Assets/tree/master/Champions_assets)
- [CommunityDragon 的客户端资源路径说明](https://github.com/CommunityDragon/Docs/blob/master/assets.md)
- [Riot 对游戏使用素材的规则，第 3 条](https://www.riotgames.com/en/legal)
