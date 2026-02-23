# Cortex UI 重构计划：去紫色化 + 移除 SolidJS

> **日期**: 2026-02-21  
> **状态**: 规划中  
> **目标**: 1) 替换 indigo/purple 配色为更工具化的中性色调；2) 完全移除 SolidJS 依赖，切换为纯 LiveView 架构

---

## 一、现状分析

### 1.1 当前配色问题

当前项目大量使用 `indigo-*` 和 `purple-*` 色系（Tailwind 类名），给人典型的"AI 产品"观感。

**CSS 变量层** (`assets/css/app.css`):
| 变量 | 当前值 (HSL) | 视觉效果 |
|---|---|---|
| `--primary` | `221.2 83.2% 53.3%` | Indigo-600 |
| `--ring` | `224.3 76.3% 48%` | 深蓝紫 |
| `--background` | `222.2 84% 4.9%` | 深靛蓝黑 |

**Tailwind 类名硬编码** — 涉及文件汇总（共约 50+ 处引用）：

| 文件 | indigo 引用数 | purple 引用数 |
|---|---|---|
| `lib/.../components/jido_components.ex` | ~12 | 1 |
| `lib/.../components/file_browser_component.ex` | ~6 | 0 |
| `lib/.../settings_live/channels.ex` | ~5 | 0 |
| `lib/.../settings_live/channels_component.ex` | ~5 | 0 |
| `lib/.../model_live/form_component.ex` | ~10 | 0 |
| `lib/.../model_live/index.ex` | ~3 | 0 |
| `lib/.../components/layouts.ex` | ~3 | 0 |
| `lib/.../layouts/app.html.heex` | ~2 | 0 |
| `lib/.../components/thinking_component.ex` | ~3 | 0 |
| `lib/.../components/conversation_list_component.ex` | ~2 | 0 |
| `lib/.../live/jido_live.ex` | ~2 | 0 |
| `lib/.../controllers/page_html/home.html.heex` | 1 | 0 |
| `lib/.../components/model_selector.ex` | 1 | 0 |
| `assets/css/app.css` | 2 | 0 |

### 1.2 SolidJS 依赖现状

SolidJS 当前作为 LiveView 的前端渲染桥接层存在，但所有 SolidJS 组件已备份为 `.jsx.bak` 文件，**实际活跃使用的仅为 Vite 资产加载器 (`LiveSolidJS.Reload.vite_assets`)**。

**依赖链路（需清理的触点）：**

| 层级 | 文件 | 用途 |
|---|---|---|
| **Elixir Dep** | `mix.exs` L78 | `{:live_solidjs, git: "..."}` |
| **Elixir Import** | `lib/cortex_web.ex` L90 | `import LiveSolidJS` |
| **Elixir Protocol** | `lib/.../live_solidjs_protocol.ex` | `LiveSolidJS.Encoder` 实现 |
| **Layout Template** | `lib/.../layouts/root.html.heex` L10-14 | `<LiveSolidJS.Reload.vite_assets>` |
| **Home Page** | `lib/.../page_html/home.html.heex` L3 | `<.solid name="Hello" />` |
| **NPM Deps** | `assets/package.json` L10,14 | `live_solidjs`, `solid-js` |
| **NPM Dev Deps** | `assets/package.json` L25 | `vite-plugin-solid` |
| **Vite Config** | `assets/vite.config.js` L3,5,23,24,33,34 | solid plugin + alias |
| **TS Config** | `assets/tsconfig.json` L9,16 | `jsxImportSource: solid-js` |
| **Backup 组件** | `assets/js/solidjs/**/*.jsx.bak` | 18 个已备份文件 |

---

## 二、新配色方案建议

### 方案 A：Neutral Slate + Teal 强调色 (推荐)

工具感强，冷静专业，远离 AI 紫色刻板印象。

| 用途 | 旧色 | 新色 | Tailwind 类 |
|---|---|---|---|
| 主按钮/强调 | `indigo-600` | `teal-600` | `bg-teal-600` |
| 主按钮 hover | `indigo-500` | `teal-500` | `hover:bg-teal-500` |
| 选中态文字 | `text-indigo-400` | `text-teal-400` | `text-teal-400` |
| 选中态背景 | `bg-indigo-600/10` | `bg-teal-600/10` | `bg-teal-600/10` |
| 边框强调 | `border-indigo-500` | `border-teal-500` | `border-teal-500` |
| Shadow glow | `shadow-indigo-500/20` | `shadow-teal-500/20` | `shadow-teal-500/20` |
| Focus ring | `focus:ring-indigo-500` | `focus:ring-teal-500` | `focus:ring-teal-500` |
| Focus border | `focus:border-indigo-500` | `focus:border-teal-500` | `focus:border-teal-500` |
| 思考区域 bg | `bg-indigo-900/30` | `bg-slate-800/50` | `bg-slate-800/50` |
| 思考区域 text | `text-indigo-300` | `text-teal-300` | `text-teal-300` |
| 代码高亮 | `text-indigo-300` | `text-emerald-300` | `text-emerald-300` |
| 链接 | `text-indigo-400` | `text-teal-400` | `text-teal-400` |
| 渐变 | `from-indigo-600/20 to-purple-600/20` | `from-slate-700/40 to-teal-900/20` | — |
| Checkbox | `text-indigo-600` | `text-teal-600` | `text-teal-600` |

**CSS 变量更新：**
```css
:root {
  --primary: 172 66% 40%;          /* teal-600: hsl(172, 66%, 40%) */
  --primary-foreground: 210 40% 98%;
  --ring: 172 66% 40%;
  --background: 220 16% 6%;        /* 更中性的深灰黑 */
}
```

### 方案 B：Neutral Slate + Sky Blue 强调色

偏向经典开发工具风格（类 VS Code）。

| 用途 | 新色 |
|---|---|
| 主强调 | `sky-500` / `sky-600` |
| 文字强调 | `text-sky-400` |

### 方案 C：纯 Zinc/Neutral + Amber 点缀

极简工业风，强调内容而非 UI。

| 用途 | 新色 |
|---|---|
| 主强调 | `amber-500` |
| 背景 | `zinc-900` / `zinc-950` |

> **建议采用方案 A (Teal)**，兼顾专业感与辨识度，避免紫色 AI 刻板印象。

---

## 三、实施计划

### Phase 1：移除 SolidJS 依赖（低风险，优先执行）

**预计工作量：1-2 小时**

#### Step 1.1：替换 Vite 资产加载器

`LiveSolidJS.Reload.vite_assets` 当前仅用于开发环境 Vite HMR 资产注入。需要替换为 Phoenix 原生的 Vite 集成或直接标签引用。

**修改文件：**
- `lib/.../layouts/root.html.heex` — 将 `<LiveSolidJS.Reload.vite_assets>` 替换为标准 `<link>` + `<script>` 标签，配合环境判断实现 dev/prod 兼容：

```heex
<%= if Application.get_env(:cortex, :dev_routes) do %>
  <script type="module" src="http://localhost:5173/@vite/client"></script>
  <script type="module" src="http://localhost:5173/js/app.js"></script>
<% else %>
  <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
  <script type="module" phx-track-static src={~p"/assets/app.js"}></script>
<% end %>
```

#### Step 1.2：移除 Elixir 侧依赖

| 文件 | 操作 |
|---|---|
| `mix.exs` L78 | 删除 `{:live_solidjs, ...}` |
| `lib/cortex_web.ex` L90 | 删除 `import LiveSolidJS` |
| `lib/.../live_solidjs_protocol.ex` | 删除整个文件 |
| `lib/.../page_html/home.html.heex` L3 | 删除 `<.solid name="Hello" />` 或替换为 LiveView 组件 |

#### Step 1.3：清理 JS/前端侧

| 文件 | 操作 |
|---|---|
| `assets/package.json` | 移除 `solid-js`, `live_solidjs`, `vite-plugin-solid` |
| `assets/vite.config.js` | 移除 `solid()` plugin、`liveSolidjsPlugin()` 及相关 import/alias |
| `assets/tsconfig.json` | 移除 `jsxImportSource: solid-js` 和 `live_solidjs` path |
| `assets/js/solidjs/` | 删除整个目录（所有 `.jsx.bak` 文件） |

#### Step 1.4：清理依赖

```bash
cd assets && bun install   # 重新安装以清除 node_modules 中的 solid-js
mix deps.get               # 重新获取依赖
mix deps.clean live_solidjs --build  # 清理编译产物
```

#### Step 1.5：验证

```bash
mix compile --warnings-as-errors  # 确认无编译错误
cd assets && bun run build        # 确认前端构建正常
mix test                          # 确认测试通过
```

---

### Phase 2：配色替换（批量替换 + 逐文件验证）

**预计工作量：2-3 小时**

#### Step 2.1：更新 CSS 变量

修改 `assets/css/app.css` 中的 `:root` 变量为 Teal 色系。

#### Step 2.2：批量替换 Tailwind 类名

使用全局搜索替换，按优先级执行：

**替换映射表（精确匹配）：**

```
bg-indigo-600           → bg-teal-600
bg-indigo-500           → bg-teal-500
bg-indigo-600/10        → bg-teal-600/10
bg-indigo-500/5         → bg-teal-500/5
bg-indigo-900/30        → bg-slate-800/50
text-indigo-600         → text-teal-600
text-indigo-400         → text-teal-400
text-indigo-300         → text-teal-300
border-indigo-500       → border-teal-500
border-indigo-900/30    → border-slate-700/30
shadow-indigo-500/20    → shadow-teal-500/20
focus:border-indigo-500 → focus:border-teal-500
focus:ring-indigo-500   → focus:ring-teal-500
hover:bg-indigo-500     → hover:bg-teal-500
hover:bg-indigo-600     → hover:bg-teal-600
hover:text-indigo-300   → hover:text-teal-300
hover:text-indigo-400   → hover:text-teal-400
from-indigo-600/20      → from-slate-700/40
to-purple-600/20        → to-teal-900/20
group-hover:bg-indigo-600 → group-hover:bg-teal-600
```

#### Step 2.3：逐文件验证清单

- [ ] `assets/css/app.css` — CSS 变量 + markdown 样式
- [ ] `lib/.../components/jido_components.ex`
- [ ] `lib/.../components/file_browser_component.ex`
- [ ] `lib/.../components/thinking_component.ex`
- [ ] `lib/.../components/conversation_list_component.ex`
- [ ] `lib/.../components/layouts.ex`
- [ ] `lib/.../layouts/app.html.heex`
- [ ] `lib/.../settings_live/index.ex`
- [ ] `lib/.../settings_live/channels.ex`
- [ ] `lib/.../settings_live/channels_component.ex`
- [ ] `lib/.../settings_live/models_component.ex`
- [ ] `lib/.../model_live/index.ex`
- [ ] `lib/.../model_live/form_component.ex`
- [ ] `lib/.../components/model_selector.ex`
- [ ] `lib/.../live/jido_live.ex`
- [ ] `lib/.../controllers/page_html/home.html.heex`

#### Step 2.4：最终验证

```bash
# 确认无遗留 indigo/purple 引用
grep -rn "indigo\|purple\|violet" lib/ assets/css/
# 编译 + 构建
mix compile && cd assets && bun run build
# 视觉验证
mix phx.server  # 手动检查各页面
```

---

## 四、风险评估

| 风险 | 影响 | 缓解策略 |
|---|---|---|
| `LiveSolidJS.Reload.vite_assets` 移除后 HMR 失效 | 开发体验降级 | 使用 Phoenix 1.8 原生 Vite 集成或手动 Vite client 注入 |
| 批量颜色替换遗漏 | 视觉不一致 | Phase 2 完成后运行 `grep` 全局扫描 |
| `.solid` 组件调用未替换 | 编译错误 | Phase 1 完成后 `mix compile --warnings-as-errors` |
| Topbar 颜色硬编码 | `app.js` L49 仍为 `#29d` | 需同步替换为 teal 系 hex（`#0d9488`） |

---

## 五、BDD 驱动迭代流程说明

本计划遵循项目标准 BDD 驱动迭代流程：

1. **规划阶段** (本文档) — 完成架构分析和任务分解
2. **BDD 场景定义** — 在实施前为关键行为编写验收标准：
   - 场景：移除 SolidJS 后应用正常启动
   - 场景：所有页面无 indigo/purple 颜色残留
   - 场景：Vite HMR 在开发环境正常工作
3. **实施** — 按 Phase 顺序执行
4. **验证** — 运行 `mix test` + 视觉检查 + grep 扫描

详细 BDD 工具用法参考 `.agent/skills/bddc/SKILL.md` 和 `.github/KnowledgeBase`。

---

## 六、执行顺序建议

```
Phase 1 (SolidJS 移除) → git commit
    ↓
Phase 2 (配色替换) → git commit
    ↓
视觉回归测试 → 修复遗漏 → 完成
```

> 两个 Phase 相互独立，可分别提交。建议先执行 Phase 1 以简化前端构建链路。
