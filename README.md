# Plants vs Zombies (PVZ) Game Framework
**Engine**: Godot Engine 4.7.2  
**Target Platform**: 纯Web前端 (HTML5 / WebAssembly / WebGL 2.0)  
**Architecture Pattern**: Data-Driven (Resource-based), Decoupled EventBus, Component Visuals

---

## 🌟 核心特性与架构亮点

1. **纯Web前端深度优化 (Web-First Architecture)**
   - **渲染器适配**：配置 `gl_compatibility` 渲染方法（WebGL 2.0），完美适配 Chrome, Safari, Firefox, Edge 以及移动端手机浏览器。
   - **Web Audio 策略**：现代浏览器默认阻止无用户交互的音频播放。框架内置 `SoundManager`，在首次用户交互（点击/触控）时自动解锁 Web AudioContext。
   - **程序化音频合成 (Zero External Asset Dependency)**：内置音频波形与噪声合成器，发射豌豆、命中击碎、收集阳光、僵尸啃食、樱桃爆炸、割草机轰鸣等音效全部由代码动态生成，开箱即有真实音效。
   - **响应式视口**：1280x720 基准分辨率，采用 `canvas_items` 缩放与 `keep` 纵横比，自动适配桌面全屏与手机横屏。

2. **高度解耦与数据驱动 (Data-Driven Design)**
   - **植物与僵尸配置资源化**：所有属性（生命值、阳光花费、冷却时间、移速、护甲）均由 Godot 自定义 `Resource` (`PlantData`, `ZombieData`, `LevelData`) 驱动。
   - **全局信号总线 (`EventBus`)**：单例解耦植物种植、阳光变动、波次推进、僵尸受击与胜负判定。

3. **双重运行模式**
   - **Godot 4.7.2 原生项目**：直接在 Godot 4 引擎中打开即可游玩、编辑或一键导出为 Web 前端。
   - **即开即玩 Web Preview**：随项目提供免编译的 HTML5 Canvas 独立前端副本（位于 `web_preview/`），只需运行 `python3 serve.py` 即可立即在浏览器中试玩完整游戏循环！

---

## 📁 目录结构

```text
pvz_like_game/
├── project.godot                     # Godot 4.7.2 核心配置文件 (GL Compatibility, Autoload, 视口设置)
├── export_presets.cfg                # Web 导出预设模版配置
├── icon.svg                          # 游戏矢量图标
├── serve.py                          # 支持 COOP/COEP 隔离头的本地 Web 开发服务器
├── web/
│   └── index.html                    # 自定义 Godot Web 导出 HTML 模版 (带向日葵加载条与全屏按钮)
├── web_preview/
│   └── index.html                    # 纯前端即时预览版 (支持完整8种植物+4种僵尸+声效+波次系统)
├── data/                             # 数据驱动资源定义 (.tres)
│   ├── plants/                       # 8款植物的数据资源
│   │   ├── peashooter.tres           # 豌豆射手 (100阳光, 7.5s CD)
│   │   ├── sunflower.tres            # 向日葵 (50阳光, 生产阳光)
│   │   ├── wallnut.tres              # 坚果墙 (50阳光, 4000血量, 裂纹阶段)
│   │   ├── cherry_bomb.tres          # 樱桃炸弹 (150阳光, 3x3 范围1800伤害)
│   │   ├── snow_pea.tres             # 寒冰射手 (175阳光, 50%减速与冰冻效果)
│   │   ├── potato_mine.tres          # 土豆雷 (25阳光, 14s武装时间, 触碰秒杀)
│   │   ├── repeater.tres             # 双发射手 (200阳光, 连发2枚豌豆)
│   │   └── chomper.tres              # 大嘴花 (150阳光, 吞食僵尸后消化咀嚼)
│   ├── zombies/                      # 4款僵尸的数据资源
│   │   ├── normal_zombie.tres        # 普通僵尸 (200 HP)
│   │   ├── conehead_zombie.tres      # 路障僵尸 (200 HP + 370 护甲, 掉落路障)
│   │   ├── buckethead_zombie.tres    # 铁桶僵尸 (200 HP + 1100 护甲, 极高防御)
│   │   └── flag_zombie.tres          # 旗帜僵尸 (移速加快25%, 引领大波次)
│   └── levels/
│       └── level_1.tres              # 第1关：5波阶梯式进攻 + 旗帜突袭
├── scenes/
│   ├── main.tscn                     # 游戏主场景 (草坪、管理器、小推车、HUD)
│   ├── plants/                       # 植物场景实体
│   ├── zombies/                      # 僵尸场景实体
│   ├── projectiles/                  # 弹道实体 (豌豆、冰豌豆)
│   ├── items/                        # 阳光与小推车割草机
│   ├── effects/                      # 粒子命中碎裂与爆炸特效
│   └── ui/                           # HUD 卡槽、阳光计数器、铲子、波次进度条
└── scripts/
    ├── autoload/                     # 全局单例
    │   ├── event_bus.gd              # 全局信号总线
    │   ├── sound_manager.gd          # Web 音效合成与播放器
    │   └── game_manager.gd           # 游戏状态机与金钱交易事务
    ├── core/                         # 核心战斗与场地逻辑
    │   ├── grid_manager.gd           # 5x9 草坪坐标系转换、植物种植检测与高亮预览
    │   ├── sun_manager.gd            # 天空自然落阳与向日葵产阳调度
    │   └── wave_manager.gd           # 关卡波次推进与胜负判定
    ├── plants/                       # 植物控制脚本
    ├── zombies/                      # 僵尸状态机 (行走/啃食/减速/死亡)
    ├── projectiles/                  # 弹道碰撞与伤害处理
    ├── ui/                           # 卡牌 CD 扫描蒙版与铲子交互
    └── visuals/                      # 矢量程序化图形绘制组件
```

---

## 🕹️ 游戏核心系统实现

### 1. 草坪网格系统 (`GridManager`)
- 规格：5行（Lane 0 ~ 4）× 9列（Col 0 ~ 8）。
- 坐标换算：
  - `world_to_grid(Vector2) -> Vector2i`
  - `grid_to_world(Vector2i) -> Vector2`
- 特色：选中植物卡片时，鼠标在草坪悬停会显示对应单元格的**虚影预览**和**红/绿放置高亮**；点击右键随时取消选中。

### 2. 阳光经济系统 (`SunManager`)
- 自然落阳：每隔 8~10 秒从天空顶部随机掉落并在指定高度悬停漂浮。
- 向日葵产阳：周期性从花盘弹出抛物线阳光。
- 交互动效：点击阳光时，触发平滑缓动（Tween），阳光缩放并飞入左上角阳光计数框，数字弹出反馈动画。

### 3. 卡牌卡槽与冷却系统 (`SeedPacket`)
- 支持动态卡组加载（由关卡配置的 `available_plants` 自动生成）。
- 实时监测阳光充足度（阳光不足时卡片呈现变暗灰色）。
- 种植后触发顺滑的倒计时遮罩扫描（Vertical Fill Overlay），冷却完毕后恢复可用。

### 4. 僵尸攻击与护甲系统 (`BaseZombie`)
- 状态机：`WALKING`（行走） ↔ `EATING`（啃食） ↔ `DYING`（死亡）。
- 独立护甲层：路障僵尸与铁桶僵尸拥有独立的护甲血条，承受伤害时优先扣除护甲值，护甲归零时触发帽子脱落动画。
- 寒冰减速机制：受到冰豌豆攻击时，僵尸身体呈现冷蓝色，移动速度与啃食速度同时降低 50%，持续 5 秒。

### 5. 紧急防线：小推车割草机 (`LawnMower`)
- 5个通道各配备一辆小推车。
- 当僵尸突破防线接近草坪最左侧时，小推车自动点火轰鸣，以 650px/s 的速度冲刷整条通道，秒杀该行所有僵尸，作为玩家的最后防线。

---

## 🚀 启动与体验指南

### 方式一：直接在浏览器中体验即时预览 (无需安装 Godot)
本项目包含纯前端完整的可运行实现：
```bash
# 启动内置的 Web 开发服务器
python3 serve.py 8080
```
在浏览器中打开：
👉 **http://localhost:8080/web_preview/**

即可立即开始游戏，支持点击种植、收集阳光、使用铲子、查看波次警告与通关！

---

### 方式二：在 Godot 4.7.2 引擎中打开与编辑
1. 打开 **Godot 4.7.2** 编辑器。
2. 点击 **Import**（导入），选择本目录下的 `project.godot`。
3. 打开后按 **F5** 即可直接运行主场景 `res://scenes/main.tscn`。

---

### 方式三：导出为纯 Web 前端应用 (HTML5 / WebAssembly)
1. 在 Godot 4.7.2 菜单中选择 **Project** -> **Export...**（项目 -> 导出）。
2. 在预设列表中已内置好 **Web** 预设（基于 `export_presets.cfg`）。
3. 确保导出模版为 **Compatibility** 渲染模式（已预先配置）。
4. 点击 **Export Project**，导出到 `web_export/` 目录。
5. 运行 `python3 serve.py 8080` 并访问 `http://localhost:8080/web_export/`。

> 💡 **Web 开发关键注意事项**：  
> 现代浏览器对 WebAssembly 和 SharedArrayBuffer 有严格的安全上下文限制。运行 Godot 4 Web 项目时必须在 HTTP 响应头中提供：  
> - `Cross-Origin-Opener-Policy: same-origin`  
> - `Cross-Origin-Embedder-Policy: require-corp`  
> 项目随附的 `serve.py` 已经预置了这些标头，能够直接保证 Web 端平稳运行。

---

## 🧩 如何扩展框架

### 1. 新增一种植物（只需 2 步）
1. 在 `data/plants/` 新建一个 `PlantData` 资源（如 `cabbage_pult.tres`），设置名称、费用、冷却时间。
2. 继承 `BasePlant` 编写脚本或复用攻击逻辑。
3. 将新 `.tres` 添加进关卡资源 `LevelData.available_plants` 中，卡槽将自动出现并运作！

### 2. 新增一种僵尸
1. 在 `data/zombies/` 新建 `ZombieData` 资源（如 `newspaper_zombie.tres`），设置移速和生命值。
2. 在关卡 `LevelData.waves` 中指定其出现的波次与通道索引即可！

