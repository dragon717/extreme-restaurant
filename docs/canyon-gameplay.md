# 峡谷餐厅 · 河港夜市

## 原版服务链

在 Fork 基线 cc4e4ef 上，用 gdtoolkit 的 GDScript 语法解析了 scripts 下 35 份脚本、617 个函数声明（同文件的不同内部类分别计数）。调用边来自语法树，订单所有权和时序根据函数内的条件与赋值核对。安装 gdtoolkit 后，可用 `python3 tools/gameplay_ast.py` 在当前版本重跑。

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

峡谷首页、顶栏和场景招牌采用原型画稿与生图素材。六位特色员工使用重新绘制的岗位动作，选将与技能栏的原图标接自 PC 版资源。建筑、桥梁及室内岗位共用固定机位的三维场景。[素材与版本依据](原型/设计依据.md)

两章各有 28 个营业日，第 1、8、15、22 天起分别播放春、夏、秋、冬的配乐。标题场景的 Soundtrack 会按所选章节的存档选曲，进入餐厅、开店和看日报时沿用同一播放位置。四首游戏版录音在 `assets/music/`，各为 144 拍，速度统一为每分钟 84 拍。每首在乐句内循环，换季从下一拍起用两拍交叉淡化。

场景和音乐读取同一份章节日历。春季庭院飘花，夏季草木转绿，秋季河岸转金，落叶沿石径和进店路散布。近处的客人和行人会把脚旁几片叶子拨开，叶子停在新的位置。冬天地面积雪，交替脚印留在行走路线上，落脚时扬起的雪粉和细冰粒各自落下。营业天气继续取当天预报。切换屋顶、进出菜单及开店均保留配乐进度，设置页可单独开关音乐。

配乐以《召唤师峡谷》的管弦地图音乐为参考，使用 Suno 生成。此次使用 Free 账户的试用下载额度，适用于个人非商业项目。[Riot 地图配乐说明](https://www.leagueoflegends.com/en-sg/news/game-updates/patch-14-1-notes/) · [Suno 下载授权说明](https://suno.com/blog/suno-updates-tos)

- 春 · 石桥初晴，长笛短句与双簧管应答。[Suno 原曲](https://suno.com/song/bd0ff4c4-687a-48f8-8ee0-e187e2e78d5c)
- 夏 · 河港晚市，拨弦和木管写夜市来客的脚步。[Suno 原曲](https://suno.com/song/3d8b728f-9909-4363-83df-f1226d4a3865)
- 秋 · 琥珀渡口，中提琴与大管铺开较长的乐句。[Suno 原曲](https://suno.com/song/56e24fa9-8595-4316-8bec-318b199350da)
- 冬 · 炉火守夜，低音木管和大提琴留出停顿。[Suno 原曲](https://suno.com/song/e9155e3b-e594-4cca-8c22-92d17bb921c6)

- [GitHub 英雄技能图标目录](https://github.com/TheePepS/League_Of_Legends_Assets/tree/master/Champions_Spells_Assets)
- [希维尔 R 图标](https://github.com/TheePepS/League_Of_Legends_Assets/blob/master/Champions_Spells_Assets/Sivir_On_The_Hunt.png)
- [布兰德被动图标](https://github.com/TheePepS/League_Of_Legends_Assets/blob/master/Champions_Spells_Assets/Brand_Blaze.png)
- [GitHub 英雄头像目录](https://github.com/TheePepS/League_Of_Legends_Assets/tree/master/Champions_assets)
- [CommunityDragon 的 scuttle.png 图标索引](https://raw.communitydragon.org/16.11/plugins/rcp-fe-lol-champ-select/global/default/images/subteams/)
- [GitHub 上按英雄整理的语音与音效](https://github.com/VaultSoft/sound-vault)
- [原版音乐调研，含 Awaken、RISE、Phoenix 和 Legends Never Die](https://github.com/Dev-Pedrosv/lol-media-player/tree/master/src/assets/audio/mp3)。
- [CommunityDragon 的客户端资源路径说明](https://github.com/CommunityDragon/Docs/blob/master/assets.md)
- [Riot 对游戏使用素材的规则，第 3 条](https://www.riotgames.com/en/legal)

## 首班员工进店

新局确认五位特色员工后，当班阵容与补位小兵在门外集合。员工单列走上门廊，穿过打开的门扇，按当晚可通行方格前往各自站位。最后一人越过门槛后镜头抬起。右下角可以切换三倍速或跳过本次入场；读档直接恢复原来岗位。脚步相位取自实际行程，侧行和背行使用独立画帧，支撑脚在换重心前固定在地面。炮车以车轮接地。

### 小兵岗位专长

补位兵种可在「选择本局英雄」的「补位小兵」或夜间的「今日排班」逐个调整，随本局存档保存。首次补位与缺少兵种字段的旧存档默认使用近战小兵。小兵占厨师或服务员的实际名额。

| 兵种 | 厨师 | 服务员 |
| --- | --- | --- |
| 近战小兵 | 前往灶位时移速提高 6% | 前往客桌接单时移速提高 6% |
| 法师小兵 | 烹饪用时减少 4% | 桌边点单用时减少 10% |
| 炮车兵 | 搬运成菜到出餐口时移速提高 8% | 持菜送往客桌时移速提高 8% |

三种小兵的外形参考 PC 客户端对应单位，侧面与背面动作按本项目角色图重绘。[近战小兵](https://raw.communitydragon.org/16.23/game/assets/characters/sru_orderminionmelee/hud/bluemelee_square.png) · [法师小兵](https://raw.communitydragon.org/16.23/game/assets/characters/sru_orderminionranged/hud/bluerange_square.png) · [炮车兵](https://raw.communitydragon.org/16.23/game/assets/characters/sru_orderminionsiege/hud/bluemechcannon_square.png)
