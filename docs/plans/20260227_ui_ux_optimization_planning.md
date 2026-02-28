# Cortex UI/UX 优化计划书

**日期**: 2026-02-27  
**版本**: v1.0  
**状态**: 规划阶段

---

## 📋 执行摘要

本计划书基于 `design-taste-frontend` 高级 UI/UX 工程规范，对 Cortex 当前界面进行全面审计，识别出与业界最佳实践的差距，并提出系统化的优化方案。目标是将 Cortex 从功能性界面提升为具有高端视觉品质、流畅交互体验和专业设计工程的产品级界面。

---

## 🎯 核心设计目标

### 当前基线配置
- **DESIGN_VARIANCE**: 8 (偏向非对称、创意布局)
- **MOTION_INTENSITY**: 6 (流畅 CSS 动画 + 适度物理效果)
- **VISUAL_DENSITY**: 4 (平衡的信息密度,适合日常应用)

### 优化原则
1. **信号驱动优先**: 所有 UI 交互必须通过 SignalHub 发射标准化信号
2. **性能至上**: 动画使用 `transform` 和 `opacity`,避免触发 reflow
3. **移动优先**: 确保响应式设计在所有设备上稳定
4. **无障碍合规**: 遵循 WCAG 基础标准(但不声称完全合规)

---

## 🔍 当前状态审计

### ✅ 已做得好的方面

1. **技术栈现代化**
   - ✅ Tailwind CSS v4.1.4 (最新版本)
   - ✅ Phoenix LiveView (实时响应)
   - ✅ Vite 构建工具
   - ✅ CodeMirror 6 编辑器集成

2. **基础架构**
   - ✅ 信号驱动架构 (SignalHub)
   - ✅ 组件化设计 (JidoComponents)
   - ✅ 暗色主题基础

3. **功能完整性**
   - ✅ 实时消息流
   - ✅ 模型/Agent 选择器
   - ✅ 文件浏览器
   - ✅ 权限管理

### ❌ 需要改进的关键问题

#### 1. **设计系统缺陷 (CRITICAL)**

**问题**: 使用 daisyUI 导致的"AI 设计痕迹"
- ❌ daisyUI 组件库产生通用化、缺乏个性的视觉风格
- ❌ 按钮、卡片、表单等组件过于"开箱即用",缺少品牌特色
- ❌ 违反 design-taste-frontend 的"反 AI 陈词滥调"原则

**影响**: 界面看起来像"又一个 AI 聊天工具",缺乏记忆点

**解决方案**:
```elixir
# 当前 (core_components.ex)
class={["btn", Map.fetch!(variants, assigns[:variant])]}  # daisyUI 类

# 优化后
class={[
  "px-4 py-2 rounded-lg font-medium transition-all duration-200",
  "bg-teal-600 hover:bg-teal-500 active:scale-[0.98]",
  "shadow-sm hover:shadow-md",
  "focus:outline-none focus:ring-2 focus:ring-teal-400/50"
]}
```

#### 2. **排版系统问题 (HIGH)**

**问题**: 缺乏层次化的字体系统
- ❌ 未定义明确的字体家族(仍使用系统默认)
- ❌ 标题缺少 `tracking-tighter` 和 `leading-none` 优化
- ❌ 正文未设置最佳阅读宽度 (`max-w-[65ch]`)

**当前状态**:
```css
/* app.css - 仅有基础 markdown 样式 */
.markdown-content h1 { @apply text-xl font-bold mt-4 mb-2; }
```

**优化方案**:
```css
/* 引入高端字体 */
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap');

:root {
  --font-sans: 'Geist', -apple-system, sans-serif;
  --font-mono: 'Geist Mono', 'JetBrains Mono', monospace;
}

/* 标题系统 */
.heading-display { 
  @apply text-4xl md:text-6xl font-bold tracking-tighter leading-none; 
}
.heading-section { 
  @apply text-2xl md:text-3xl font-semibold tracking-tight; 
}
.body-text { 
  @apply text-base text-slate-300 leading-relaxed max-w-[65ch]; 
}
```

#### 3. **色彩系统违规 (HIGH)**

**问题**: 存在"AI 紫色/蓝色"美学倾向
- ⚠️ 当前使用 `teal` (青色) 作为主色 - 较好,但需要去饱和化
- ❌ 缺少系统化的色彩变量定义
- ❌ 阴影未使用色调匹配 (tinted shadows)

**当前配置**:
```css
:root {
  --primary: 172 66% 40%;  /* teal - 饱和度 66% 过高 */
}
```

**优化方案**:
```css
:root {
  /* 主色调 - 降低饱和度到 50% */
  --primary: 172 50% 40%;
  --primary-hover: 172 55% 45%;
  
  /* 中性色 - 使用 Zinc 而非 Slate */
  --bg-base: 240 10% 3.9%;      /* zinc-950 */
  --bg-elevated: 240 6% 10%;     /* zinc-900 */
  --border: 240 4% 16%;          /* zinc-800 */
  
  /* 色调阴影 */
  --shadow-teal: 172 50% 40% / 0.15;
}

.card-elevated {
  box-shadow: 0 4px 6px -1px rgb(var(--shadow-teal)),
              0 2px 4px -2px rgb(var(--shadow-teal));
}
```

#### 4. **布局单调性 (MEDIUM)**

**问题**: 过度依赖居中和对称布局
- ❌ 聊天界面完全垂直居中
- ❌ 缺少非对称的视觉张力
- ❌ 未利用 CSS Grid 的高级特性

**当前布局**:
```heex
<!-- chat_panel.ex - 标准垂直堆叠 -->
<div class="flex-1 flex flex-col h-full">
  <div class="flex-1 overflow-y-auto p-6 space-y-6">
    <!-- 消息列表 -->
  </div>
</div>
```

**优化建议**:
- 使用 `grid-template-columns: 2fr 1fr 1fr` 创建非对称网格
- 消息气泡采用左对齐 + 右侧大量留白 (用户消息)
- 添加 `-mt-8` 等负边距创建重叠效果

#### 5. **动画缺失 (HIGH)**

**问题**: 几乎没有微交互动画
- ❌ 按钮点击无触觉反馈 (`:active` 状态)
- ❌ 列表项加载无交错动画 (stagger)
- ❌ 模态框出现无过渡效果
- ❌ 消息流入无渐显动画

**当前状态**:
```javascript
// app.js - 仅有基础 ScrollToBottom hook
ScrollToBottom: {
  mounted() { this.scrollToBottom(); }
}
```

**优化方案**:
```javascript
// 添加消息渐显 Hook
MessageFadeIn: {
  mounted() {
    this.el.style.opacity = '0';
    this.el.style.transform = 'translateY(10px)';
    
    requestAnimationFrame(() => {
      this.el.style.transition = 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)';
      this.el.style.opacity = '1';
      this.el.style.transform = 'translateY(0)';
    });
  }
}
```

```css
/* 按钮触觉反馈 */
.btn-primary {
  @apply transition-all duration-200;
  @apply active:scale-[0.98] active:-translate-y-[1px];
}

/* 列表交错动画 */
.message-item {
  animation: fadeInUp 0.4s cubic-bezier(0.16, 1, 0.3, 1) backwards;
  animation-delay: calc(var(--index) * 50ms);
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

#### 6. **响应式设计漏洞 (CRITICAL)**

**问题**: 存在移动端布局崩溃风险
- ❌ 未使用 `min-h-[100dvh]` (仍可能使用 `h-screen`)
- ❌ 复杂布局未在 `< 768px` 强制单列
- ❌ 固定宽度组件可能导致横向滚动

**检查清单**:
```heex
<!-- ❌ 危险写法 -->
<div class="h-screen">  <!-- iOS Safari 会跳动 -->
<div class="w-96">      <!-- 小屏幕会溢出 -->

<!-- ✅ 安全写法 -->
<div class="min-h-[100dvh]">
<div class="w-full max-w-96">
```

#### 7. **"100 AI Tells" 违规项**

**已发现的 AI 设计痕迹**:

| 违规项 | 当前状态 | 优化方案 |
|--------|----------|----------|
| **通用卡片布局** | 使用 daisyUI `.card` 类 | 移除卡片,使用 `border-t` 分隔 |
| **居中偏好** | 消息完全居中 | 左对齐 + 非对称留白 |
| **纯黑背景** | `bg-slate-950` (接近黑) | 使用 `zinc-950` (更温暖) |
| **通用图标** | Heroicons (可接受) | 考虑 Phosphor Icons (更精致) |
| **缺少空状态设计** | 简单文本提示 | 添加插图 + 引导性文案 |

---

## 🎨 优化实施路线图

### Phase 1: 设计系统重构 (Week 1-2)

#### 1.1 移除 daisyUI 依赖
```bash
# 1. 检查 daisyUI 使用情况
rg "btn-|card-|alert-|input-|select-|checkbox-" lib/

# 2. 创建自定义组件库
mkdir -p lib/cortex_web/components/ui/
touch lib/cortex_web/components/ui/{button,input,card,badge}.ex

# 3. 逐步替换
# - core_components.ex 中的 button/1
# - core_components.ex 中的 input/1
# - jido_components 中的卡片样式
```

#### 1.2 建立字体系统
```css
/* assets/css/app.css */
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&display=swap');

@layer base {
  :root {
    --font-sans: 'Geist', system-ui, sans-serif;
    --font-mono: 'Geist Mono', 'SF Mono', monospace;
  }
  
  body {
    font-family: var(--font-sans);
  }
  
  code, pre {
    font-family: var(--font-mono);
  }
}
```

#### 1.3 色彩系统标准化
```css
/* 创建 assets/css/design-tokens.css */
@layer base {
  :root {
    /* Zinc 中性色系 */
    --zinc-950: 240 10% 3.9%;
    --zinc-900: 240 6% 10%;
    --zinc-800: 240 4% 16%;
    --zinc-700: 240 5% 26%;
    
    /* 主色调 - 去饱和 Teal */
    --primary: 172 50% 40%;
    --primary-hover: 172 55% 45%;
    --primary-active: 172 45% 35%;
    
    /* 语义色 */
    --success: 142 76% 36%;
    --warning: 38 92% 50%;
    --error: 0 72% 51%;
    
    /* 阴影 */
    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
    --shadow-md: 0 4px 6px -1px rgb(var(--primary) / 0.1);
  }
}
```

### Phase 2: 组件微交互 (Week 2-3)

#### 2.1 按钮触觉反馈
```elixir
# lib/cortex_web/components/ui/button.ex
def button(assigns) do
  ~H"""
  <button
    class={[
      "group relative px-4 py-2 rounded-lg font-medium",
      "transition-all duration-200 ease-out",
      "active:scale-[0.98] active:-translate-y-[1px]",
      "focus:outline-none focus:ring-2 focus:ring-offset-2",
      variant_classes(@variant)
    ]}
    {@rest}
  >
    <span class="relative z-10">{render_slot(@inner_block)}</span>
    <!-- 悬停光晕效果 -->
    <span class="absolute inset-0 rounded-lg bg-white/0 group-hover:bg-white/5 transition-colors"></span>
  </button>
  """
end
```

#### 2.2 消息流入动画
```javascript
// assets/js/hooks/message_animation.js
export const MessageAnimation = {
  mounted() {
    const messages = this.el.querySelectorAll('[data-message]');
    messages.forEach((msg, index) => {
      msg.style.setProperty('--index', index);
      msg.classList.add('animate-fade-in-up');
    });
  }
}
```

```css
/* assets/css/animations.css */
@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-in-up {
  animation: fadeInUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) backwards;
  animation-delay: calc(var(--index) * 80ms);
}
```

#### 2.3 模态框过渡
```heex
<!-- 添加 Alpine.js 或纯 CSS 过渡 -->
<div
  x-show="show"
  x-transition:enter="transition ease-out duration-300"
  x-transition:enter-start="opacity-0 scale-95"
  x-transition:enter-end="opacity-100 scale-100"
  class="fixed inset-0 z-50 flex items-center justify-center"
>
  <!-- 模态框内容 -->
</div>
```

### Phase 3: 布局优化 (Week 3-4)

#### 3.1 非对称消息布局
```heex
<!-- chat_panel.ex 优化 -->
<div class="grid grid-cols-[1fr_2fr] gap-8">
  <!-- 左侧: 紧凑的系统消息 -->
  <div class="space-y-2">
    <%= for msg <- @system_messages do %>
      <.system_message_compact message={msg} />
    <% end %>
  </div>
  
  <!-- 右侧: 主对话区 -->
  <div class="space-y-6">
    <%= for msg <- @chat_messages do %>
      <.chat_message message={msg} />
    <% end %>
  </div>
</div>
```

#### 3.2 响应式安全检查
```bash
# 创建检查脚本
cat > scripts/check_responsive.sh << 'EOF'
#!/bin/bash
echo "检查 h-screen 使用..."
rg "h-screen" lib/ --type elixir

echo "检查固定宽度..."
rg "w-\[?\d+(?:px|rem)" lib/ --type elixir

echo "检查缺少移动断点..."
rg "class=\"[^\"]*md:|lg:" lib/ --type elixir | rg -v "sm:"
EOF
chmod +x scripts/check_responsive.sh
```

### Phase 4: 高级特性 (Week 4-5)

#### 4.1 Liquid Glass 效果
```css
/* 玻璃态卡片 */
.glass-card {
  background: rgba(255, 255, 255, 0.05);
  backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    0 20px 40px -15px rgba(0, 0, 0, 0.3);
}
```

#### 4.2 Skeleton Shimmer 加载
```css
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.skeleton {
  background: linear-gradient(
    90deg,
    rgba(255,255,255,0.05) 25%,
    rgba(255,255,255,0.1) 50%,
    rgba(255,255,255,0.05) 75%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}
```

#### 4.3 交错列表动画
```heex
<div
  id="conversations"
  phx-update="stream"
  class="space-y-2"
>
  <%= for {{dom_id, conv}, index} <- Enum.with_index(@streams.conversations) do %>
    <div
      id={dom_id}
      style={"--index: #{index}"}
      class="animate-fade-in-up"
    >
      <.conversation_item conversation={conv} />
    </div>
  <% end %>
</div>
```

---

## 📊 性能优化清单

### GPU 加速规则
```css
/* ✅ 仅动画这些属性 */
.optimized-animation {
  transition: transform 0.3s, opacity 0.3s;
  will-change: transform, opacity;
}

/* ❌ 避免动画这些属性 */
.bad-animation {
  transition: width 0.3s, height 0.3s, top 0.3s;  /* 触发 reflow */
}
```

### 动画性能监控
```javascript
// 添加性能监控 Hook
export const PerformanceMonitor = {
  mounted() {
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.duration > 16.67) {  // > 60fps
          console.warn('Slow animation:', entry.name, entry.duration);
        }
      }
    });
    observer.observe({ entryTypes: ['measure'] });
  }
}
```

---

## 🧪 测试与验证

### 视觉回归测试
```bash
# 使用 Percy 或 Chromatic
npm install --save-dev @percy/cli

# 截图关键页面
percy snapshot test/screenshots/
```

### 响应式测试矩阵
| 设备 | 分辨率 | 测试重点 |
|------|--------|----------|
| iPhone SE | 375x667 | 单列布局,无横向滚动 |
| iPad | 768x1024 | 双列网格,触摸目标 |
| Desktop | 1920x1080 | 非对称布局,悬停效果 |

### 性能基准
```bash
# Lighthouse CI
npm install -g @lhci/cli

lhci autorun --config=lighthouserc.json
```

**目标指标**:
- First Contentful Paint: < 1.5s
- Time to Interactive: < 3.0s
- Cumulative Layout Shift: < 0.1

---

## 📦 依赖变更

### 需要添加
```json
{
  "dependencies": {
    "@phosphor-icons/web": "^2.0.0"  // 替代 Heroicons
  },
  "devDependencies": {
    "@percy/cli": "^1.27.0",
    "lighthouse": "^11.0.0"
  }
}
```

### 需要移除
```elixir
# mix.exs - 检查是否有 daisyUI 相关依赖
# assets/vendor/daisyui.js - 删除
# assets/vendor/daisyui-theme.js - 删除
```

---

## 🚀 实施优先级

### P0 (立即执行)
1. ✅ 修复响应式漏洞 (`h-screen` → `min-h-[100dvh]`)
2. ✅ 添加按钮触觉反馈 (`:active` 状态)
3. ✅ 建立色彩变量系统

### P1 (本周完成)
4. 🔄 移除 daisyUI,创建自定义组件
5. 🔄 引入 Geist 字体系统
6. 🔄 实现消息流入动画

### P2 (下周完成)
7. ⏳ 非对称布局重构
8. ⏳ Liquid Glass 效果
9. ⏳ 空状态设计

### P3 (持续优化)
10. ⏳ 性能监控仪表板
11. ⏳ 视觉回归测试
12. ⏳ 无障碍审计

---

## 📝 设计决策记录

### ADR-001: 为什么移除 daisyUI?
**背景**: daisyUI 提供快速原型能力,但产生通用化视觉风格  
**决策**: 移除 daisyUI,构建自定义组件库  
**理由**:
- 符合 design-taste-frontend 的"反 AI 陈词滥调"原则
- 完全控制视觉风格和品牌一致性
- 减少 CSS 包体积 (~50KB)

**权衡**: 需要额外开发时间 (~2 周)

### ADR-002: 选择 Geist 而非 Inter
**背景**: Inter 是 AI 工具的默认字体  
**决策**: 使用 Geist 字体家族  
**理由**:
- Vercel 设计系统的核心字体,现代感强
- 避免"AI 紫色/Inter 字体"的刻板印象
- 优秀的 Mono 变体,适合代码显示

### ADR-003: 动画强度设定为 6/10
**背景**: 需要平衡流畅性和性能  
**决策**: MOTION_INTENSITY = 6 (流畅 CSS + 适度物理)  
**理由**:
- 避免过度动画导致的"炫技感"
- 保证 60fps 性能
- 符合开发工具的专业定位

---

## 🔗 参考资源

### 设计灵感
- [Vercel Dashboard](https://vercel.com/dashboard) - 非对称布局
- [Linear](https://linear.app) - 微交互动画
- [Raycast](https://raycast.com) - 玻璃态设计
- [Arc Browser](https://arc.net) - 色彩系统

### 技术文档
- [Tailwind CSS v4 Docs](https://tailwindcss.com/docs)
- [Phoenix LiveView Hooks](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- [Web Animations API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Animations_API)

### 工具
- [Coolors](https://coolors.co) - 色彩方案生成
- [Type Scale](https://typescale.com) - 字体比例计算
- [Cubic Bezier](https://cubic-bezier.com) - 缓动函数调试

---

## 📞 后续行动

### 下一步
1. **团队评审**: 与产品/设计团队同步此计划
2. **技术预研**: 验证 Geist 字体在 Elixir 项目中的集成方式
3. **创建 Epic**: 在任务管理系统中创建对应的 Epic 和 Story

### 需要决策的问题
- [ ] 是否引入 Framer Motion (需要 React) 或使用纯 CSS?
- [ ] 是否需要设计师参与视觉规范制定?
- [ ] 性能基准是否需要调整 (当前目标较高)?

---

**文档维护者**: Cortex AI Agent  
**最后更新**: 2026-02-27  
**下次评审**: 2026-03-06 (实施 Phase 1 后)
