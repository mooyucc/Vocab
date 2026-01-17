---
name: uistandard
description: This is a new rule
---



# Overview

Insert overview text here. The agent will only see this should they choose to apply the rule.
---
alwaysApply: true
---

# Apple iOS Design Standards - UI/UX Guidelines

本文档定义了应用应遵循的Apple iOS设计标准和最佳实践，确保应用提供一致、直观且符合Apple设计语言的用户体验。

## 版本与兼容策略（2026）

- **目标平台**：iOS 26 / iPadOS 26，SwiftUI 8+，遵循2026版Human Interface Guidelines。
- **最低兼容**：iOS 18（SwiftUI 5）。所有新增特性必须提供`if #available(iOS 26, *)`分支。
- **降级方式**：
  - UI：优先调用新API（如`toolbarBackground(.visible, for:)`、`SensoryFeedback`修饰符），在旧版使用等价的`Material`、`UIImpactFeedbackGenerator`等。
  - 动画/手势：若`phaseAnimator`、`scrollTransition`不可用，则回退到`.animation(.spring())`和`.transition(.opacity)`。
  - 组件：缺失`ContentUnavailableView`等标准视图时，使用自定义容器保持语义一致。
- **测试矩阵**：至少覆盖iOS 26、iOS 22（中间版本）、iOS 18（最低版本），确认视觉及交互一致。

## 一、核心设计原则

### 1.1 三大主旨（Three Themes）

#### 清晰性（Clarity）
- **内容优先**：界面元素不应与内容竞争，使用留白和视觉层次突出重要信息
- **可读性**：确保文字在所有尺寸下都清晰可读，支持动态字体
- **语义明确**：每个界面元素都有明确的目的和含义

#### 遵从性（Deference）
- **系统优先**：尊重iOS系统设计，使用系统组件和标准交互模式
- **内容为主**：界面设计服务于内容，而非装饰
- **原生体验**：使用SwiftUI原生组件，避免自定义过度

#### 深度性（Depth）
- **视觉层次**：通过阴影、模糊、动画创造层次感
- **导航清晰**：使用NavigationStack、TabView等标准导航模式
- **过渡自然**：动画和过渡应该自然流畅，符合物理直觉

### 1.2 六大设计原则（Six Principles）

#### 1. 美学完整性（Aesthetic Integrity）
- 设计风格与应用功能保持一致
- 避免过度装饰，保持简洁优雅
- 使用系统提供的SF Symbols图标系统

#### 2. 一致性（Consistency）
- 使用标准界面元素和交互模式
- 保持术语、图标、行为的一致性
- 遵循iOS平台约定，而非其他平台

#### 3. 直接操作（Direct Manipulation）
- 用户可以直接与内容交互
- 提供即时视觉反馈
- 支持手势操作（滑动、长按、捏合等）

#### 4. 反馈（Feedback）
- 所有操作都应有明确的反馈
- 使用动画、声音、触觉反馈
- 状态变化要清晰可见

#### 5. 隐喻（Metaphors）
- 使用用户熟悉的概念和图标
- 地图、列表、卡片等应符合用户预期
- 避免使用抽象或难以理解的隐喻

#### 6. 用户控制（User Control）
- 用户应该能够撤销操作
- 提供明确的取消和确认选项
- 不要替用户做决定，提供选择

## 二、SwiftUI最佳实践

### 2.1 组件使用规范

#### NavigationStack（推荐）
```swift
NavigationStack {
    // 内容
}
.navigationTitle("标题")
.navigationBarTitleDisplayMode(.inline) // 或 .large
```
> **iOS 26+**：多列信息架构使用`NavigationSplitView`或`NavigationStack`+`toolbarBackground(.visible, for: .navigationBar)`以获得透明导航栏和大标题推挤效果。配合`searchable(text:placement:)`的`.navigationBarDrawer`样式。
>
> **iOS 18-25**：保留`NavigationStack`基础实现，如需分割导航可用`NavigationSplitView`但禁用透明背景，改用`List`和`NavigationLink`保持兼容。

#### TabView
```swift
TabView(selection: $selectedTab) {
    // 使用Label和systemImage
    .tabItem {
        Label("标签", systemImage: "icon.name")
    }
}
```
> **iOS 26+**：可使用`.tabViewStyle(.expanded)`与`.tabBarToolbar(.visible)`（SwiftUI 8）以获得沉浸式浮动标签栏，必要时叠加`safeAreaInset`提供底部操作区。
>
> **iOS 18-25**：维持`.tabViewStyle(.automatic)`；如需浮动效果，改用自定义`Toolbar`或`safeAreaInset`包裹，但保持44pt最小高度。

#### 表单和输入
- 使用`Form`而非`List`来组织表单内容
- 使用`TextField`、`Picker`、`Toggle`等标准控件
- 为输入字段提供清晰的标签和占位符

#### 按钮
- 主要操作使用`.buttonStyle(.borderedProminent)`
- 次要操作使用`.buttonStyle(.bordered)`
- 文本按钮使用`.buttonStyle(.plain)`
- 确保按钮有足够的触控目标（最小44x44点）
> **iOS 26+**：主按钮默认启用`.controlSize(.large)`与`.sensoryFeedback(.impact(flexibility: .medium))`提供系统级触觉。对于多操作区域使用`ControlGroup`或`MenuButton`。
>
> **iOS 18-25**：若无`sensoryFeedback`修饰符，在`Button` action内调用`UIImpactFeedbackGenerator`。`ControlGroup`不可用时使用`HStack`显示次操作按钮。

### 2.2 布局规范

#### 间距系统
- 使用标准间距：4、8、12、16、20、24、32点
- VStack/HStack默认间距为8点，可根据需要调整
- 卡片内边距通常为16-20点
- 屏幕边缘安全区域使用`.padding()`
> **iOS 26+**：优先采用`Spacing.standard(.l)`等系统间距常量（SwiftUI 8），并利用`.containerRelativeFrame(.horizontal)`在分屏或浮窗中自动适配。
>
> **iOS 18-25**：继续使用显式值，通过`GeometryReader`或自定义`Spacing`枚举保持一致。

#### 安全区域
```swift
.padding() // 自动适配安全区域
// 或
.safeAreaInset(edge: .bottom) { /* 内容 */ }
```

#### 响应式布局
- 使用`GeometryReader`处理不同屏幕尺寸
- 使用`.frame(maxWidth: .infinity)`实现自适应宽度
- 使用`LazyVGrid`和`LazyHGrid`实现网格布局
> **iOS 26+**：更多使用`ViewThatFits`、`LayoutThatFits`与`AnyLayout`组合实现自适配，网格优先`Grid`/`GridRow`（SwiftUI 8）。
>
> **iOS 18-25**：继续依赖`GeometryReader`和`LazyVGrid`；`Grid`不可用时保持`LazyVGrid`实现。

### 2.3 颜色系统

#### 语义颜色（推荐）
```swift
.foregroundColor(.primary)      // 主要文本
.foregroundColor(.secondary)     // 次要文本
.foregroundColor(.tertiary)      // 三级文本
.background(Color(.systemBackground))        // 背景
.background(Color(.secondarySystemBackground)) // 卡片背景
```
> **iOS 26+**：优先使用`Color.tint`、`Color.accent`以及`HierarchicalShapeStyle.primary`等层级色；对沉浸式卡片启用`.glassBackgroundEffect(in:)`。
>
> **iOS 18-25**：无`glassBackgroundEffect`时使用`.background(.regularMaterial)`；tint不可用时改用`AccentColor`。

#### 系统颜色
- 使用`.blue`、`.green`、`.red`等系统颜色
- 支持自动深色模式适配
- 避免硬编码颜色值

#### 渐变和效果
```swift
.foregroundStyle(.blue.gradient)  // iOS 15+
.background(.ultraThinMaterial)   // 毛玻璃效果
```
> **iOS 26+**：结合`meshGradient`、`containerBackground(.ultraThinMaterial, for:)`实现沉浸式背景，并通过`prefersMaterialControls`遵循系统亮暗映射。
>
> **iOS 18-25**：`meshGradient`不可用时改用`LinearGradient`或`RadialGradient`；`containerBackground`缺失时维持`.background`.

### 2.4 字体和排版

#### 动态字体
```swift
.font(.title)           // 标题
.font(.headline)        // 标题行
.font(.body)            // 正文
.font(.subheadline)     // 副标题
.font(.caption)         // 说明文字
.font(.caption2)        // 小号说明
```
> **iOS 26+**：启用`.dynamicTypeSize(...).fontDesign(.rounded)`以匹配全新Rounded系统字体，并结合`FontWidth`实现可变字宽。
>
> **iOS 18-25**：`fontDesign(.rounded)`不可用时保持默认系统字体，借助`UIFontMetrics`在UIKit桥接中维持动态字体。

#### 字体权重
- `.regular`：默认
- `.medium`：中等
- `.semibold`：半粗
- `.bold`：粗体

#### 文本对齐
- 标题通常左对齐
- 正文根据内容选择对齐方式
- 数字和统计数据可以右对齐

## 三、视觉设计规范

### 3.1 图标和符号

#### SF Symbols（必须使用）
- 优先使用系统提供的SF Symbols
- 使用语义化的图标名称
- 支持多色和渐变样式

```swift
Image(systemName: "icon.name")
    .foregroundStyle(.blue.gradient)
    .font(.title2)
```
> **iOS 26+**：充分利用多层级彩色Symbols与`animation`变体（如`"location.slash.fill"`的`variableValue`）实现状态反馈。
>
> **iOS 18-25**：若`variableValue`不可用，改用不同填充图标区分状态；多色符号不可用则使用单色+渐变。

#### 自定义图标
- 仅在必要时使用自定义图标
- 保持与SF Symbols风格一致
- 提供@2x和@3x版本

### 3.2 卡片和容器

#### 卡片设计
```swift
.padding()
.background(Color(.secondarySystemBackground))
.cornerRadius(15)  // 或 12、20
.shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
```
> **iOS 26+**：可替换为`.background(.quaternarySystemFill)`+`.glassBackgroundEffect()`并开启`.clipShape(.rect(cornerRadius: 18, style: .continuous))`营造连续圆角。
>
> **iOS 18-25**：保持`Color(.secondarySystemBackground)`；如需连续圆角使用`RoundedRectangle(cornerRadius:style:)`。

#### 圆角半径
- 小卡片：12点
- 中等卡片：15点
- 大卡片：20点
- 按钮：20点（胶囊形）或8-12点（圆角矩形）

#### 响应式布局
- **宽度适配**
  - iPhone：卡片宽度应适配屏幕宽度，使用`.frame(maxWidth: .infinity)`实现全宽，或使用`.frame(maxWidth: 600)`限制最大宽度以提升可读性
  - iPad：使用`.frame(maxWidth: 600)`或`.containerRelativeFrame(.horizontal, count: 1, spacing: 16)`限制卡片宽度，避免在大屏上过度拉伸
  - 多列布局：iPad横屏时考虑使用`LazyVGrid`或`Grid`实现2-3列卡片布局
> **iOS 26+**：优先使用`.containerRelativeFrame(.horizontal, count:columns, spacing:spacing)`实现容器相对尺寸，自动适配分屏、浮窗和不同设备尺寸。使用`ViewThatFits`让卡片在空间不足时自动调整布局。
>
> **iOS 18-25**：使用`GeometryReader`读取容器宽度，通过计算实现响应式布局。iPad横屏时使用`@Environment(\.horizontalSizeClass)`判断并调整列数。

- **间距适配**
  - iPhone竖屏：卡片之间间距16-20点，屏幕边缘间距16点
  - iPhone横屏：适当增加卡片间距至20-24点
  - iPad：卡片间距20-24点，屏幕边缘间距20-32点
  - 使用`.padding(.horizontal, 16)`和`.padding(.vertical, 12)`作为基础内边距
> **iOS 26+**：使用`Spacing.standard(.l)`等系统间距常量，配合`.containerRelativeFrame`实现自适应间距。
>
> **iOS 18-25**：使用显式数值，通过`@Environment(\.horizontalSizeClass)`和`@Environment(\.verticalSizeClass)`判断设备类型并调整间距。

- **内容适配**
  - 文本内容：使用`.lineLimit(nil)`允许文本换行，避免在小屏上被截断
  - 图片内容：使用`.aspectRatio(contentMode: .fit)`保持比例，配合`.frame(maxHeight: 200)`限制高度
  - 按钮和操作：在小屏上考虑将水平布局改为垂直布局，使用`ViewThatFits`自动选择最佳布局
> **iOS 26+**：使用`ViewThatFits`让卡片内容根据可用空间自动选择最佳布局（如水平/垂直按钮排列）。使用`LayoutThatFits`实现更复杂的自适应布局。
>
> **iOS 18-25**：通过`GeometryReader`读取可用宽度，使用条件判断（如`if width > 400`）切换布局方式。

- **最小尺寸限制**
  - 卡片最小宽度：iPhone上不小于屏幕宽度减去32点（左右各16点边距）
  - 卡片最小高度：根据内容动态调整，但不应小于60点（确保可读性）
  - 避免在小屏设备上使用过小的卡片，考虑使用全宽布局替代

- **横竖屏适配**
  - 竖屏：卡片通常使用全宽或接近全宽布局
  - 横屏：考虑使用多列布局或限制卡片最大宽度，避免内容过度拉伸
  - 使用`.environment(\.horizontalSizeClass)`和`.environment(\.verticalSizeClass)`判断方向并调整布局

### 3.3 阴影和深度

#### 阴影使用
```swift
.shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
.shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4) // 更明显
```

#### 毛玻璃效果
```swift
.background(.ultraThinMaterial)   // 最透明
.background(.thinMaterial)          // 较透明
.background(.regularMaterial)      // 标准
.background(.thickMaterial)        // 较不透明
.background(.ultraThickMaterial)   // 最不透明
```

## 四、交互设计规范

### 4.1 触控目标

#### 最小尺寸
- 所有可交互元素最小44x44点
- 重要操作按钮建议48x48点或更大
- 列表项高度至少44点

#### 间距
- 相邻触控元素之间至少8点间距
- 避免元素过于紧密导致误触

### 4.2 手势操作

#### 标准手势
- **轻点（Tap）**：选择、激活
- **长按（Long Press）**：上下文菜单、预览
- **滑动（Swipe）**：删除、导航
- **拖拽（Drag）**：重新排序、移动
- **捏合（Pinch）**：缩放（地图）

#### 手势反馈
- 提供即时视觉反馈
- 使用触觉反馈（Haptic Feedback）增强体验
```swift
let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
impactFeedback.impactOccurred()
```
> **iOS 26+**：优先使用`.sensoryFeedback(.impact(flexibility: .soft), trigger: state)`绑定业务状态，减少手动生成器调用。
>
> **iOS 18-25**：继续通过`UIImpactFeedbackGenerator`或`UINotificationFeedbackGenerator`提供触觉反馈。

### 4.3 动画和过渡

#### 动画原则
- 持续时间：0.2-0.3秒（快速），0.4-0.5秒（标准）
- 使用缓动曲线：`.easeInOut`、`.spring()`
- 保持动画一致性

#### 标准过渡
```swift
.transition(.opacity)
.transition(.move(edge: .bottom))
.transition(.scale.combined(with: .opacity))
```

#### 自定义动画
```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
```
> **iOS 26+**：可采用`phaseAnimator`、`keyframeAnimator`控制复杂场景；`scrollTransition`让列表滚动动画符合深度感。
>
> **iOS 18-25**：使用`.animation`或`withAnimation`配合`.transition(.opacity)`，必要时分解为多个`withAnimation`块。

## 五、无障碍设计（Accessibility）

### 5.1 动态字体支持

```swift
.font(.body)  // 自动支持动态字体
// 或
.font(.system(size: 16, weight: .regular))
.dynamicTypeSize(...)  // 限制字体大小范围（如需要）
```

### 5.2 颜色对比度

- 文本与背景对比度至少4.5:1（正常文本）
- 大文本（18pt+）至少3:1
- 使用语义颜色而非仅依赖颜色传达信息

### 5.3 无障碍标签

```swift
.accessibilityLabel("描述性标签")
.accessibilityHint("操作提示")
.accessibilityValue("当前值")
.accessibilityAddTraits(.isButton)
```

### 5.4 语音控制支持

- 为所有交互元素提供有意义的标签
- 确保可以通过语音命令访问所有功能

## 六、深色模式支持

### 6.1 自动适配

- 使用语义颜色，系统自动适配深色模式
- 避免硬编码颜色值
- 测试深色模式下的所有界面

### 6.2 自定义适配

```swift
@Environment(\.colorScheme) var colorScheme

var backgroundColor: Color {
    colorScheme == .dark ? .black : .white
}
```

### 6.3 图片适配

- 为深色模式提供适配的图片资源
- 使用Asset Catalog的Appearance设置

## 七、状态和反馈

### 7.1 加载状态

```swift
.progressViewStyle(.circular)
// 或
ProgressView()
    .progressViewStyle(.linear)
```

### 7.2 错误处理

- 显示清晰的错误信息
- 提供解决方案或重试选项
- 使用系统警告样式

### 7.3 空状态

- 提供有意义的空状态提示
- 包含图标、文字和可能的操作建议
- 避免空白页面
> **iOS 26+**：使用`ContentUnavailableView`（带`.buttonActions`)展示图文组合，并结合`.symbolEffect(.pulse)`突出主操作。
>
> **iOS 18-25**：如`ContentUnavailableView`不可用，构建自定义`VStack`，保持相同语义结构（图标、标题、描述、操作）。

### 7.4 成功反馈

- 使用动画、颜色变化或提示信息
- 短暂显示后自动消失或提供关闭选项

## 八、导航模式

### 8.1 导航层次

- **浅层次**：使用TabView + NavigationStack
- **深层次**：使用NavigationStack的push导航
- **模态**：使用`.sheet()`、`.fullScreenCover()`、`.popover()`

### 8.2 导航栏

```swift
.navigationTitle("标题")
.navigationBarTitleDisplayMode(.inline)  // 或 .large
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("操作") { }
    }
}
```

### 8.3 返回和取消

- 提供明确的返回按钮（系统自动）
- 模态视图必须提供取消/关闭按钮
- 重要操作提供确认对话框

## 九、表单设计

### 9.1 表单布局

```swift
Form {
    Section("分组标题") {
        TextField("标签", text: $text)
        Picker("选择", selection: $selection) { }
        Toggle("开关", isOn: $isOn)
    }
}
```

### 9.2 输入验证

- 实时验证（如可能）
- 清晰的错误提示
- 使用`.textInputAutocapitalization()`、`.keyboardType()`等修饰符

### 9.3 提交按钮

- 主要操作按钮放在表单底部
- 使用`.disabled()`控制按钮状态
- 提供加载状态反馈

## 十、地图和位置

### 10.1 地图样式

- 使用系统提供的MapKit样式
- 支持标准、混合、卫星等模式
- 考虑使用静音模式突出用户内容
> **iOS 26+**：使用`Map`的新`MapStyle.immersive`与`LookAroundPreview`组件，允许在导航栏内联展示预览；结合`mapScope`与`ContentBehavior`实现沉浸式切换。
>
> **iOS 18-25**：`MapStyle.immersive`不可用时回退到`MapStyle.standard`，Look Around以`MKLookAroundViewController`模态展示。

### 10.2 标注和标记

- 使用清晰的标记样式
- 支持聚类显示大量标记
- 提供标注详情视图
> **iOS 26+**：优先使用`Annotation`+`.mapOverlay`创建语义标注，并结合`SpatialTapGesture`实现局部交互。
>
> **iOS 18-25**：继续使用`MapAnnotation`、`MapPin`及`MKClusterAnnotation`；无`SpatialTapGesture`时使用标准`TapGesture`。

### 10.3 用户位置

- 请求位置权限时说明用途
- 提供位置精度指示
- 允许用户控制位置共享
> **iOS 26+**：接入`PreciseLocationControl`面板，使用`locationButton(for:)`系统按钮。
>
> **iOS 18-25**：`locationButton`不可用时，使用自定义按钮+`CLLocationManager`权限引导，仍需提供精度标签。

## 十一、性能优化

### 11.1 列表性能

- 使用`LazyVStack`、`LazyHStack`、`LazyVGrid`
- 实现`.onAppear`和`.onDisappear`进行资源管理
- 避免在列表渲染中执行重计算

### 11.2 图片加载

- 使用异步图片加载
- 提供占位符
- 缓存图片资源

### 11.3 动画性能

- 避免在主线程执行重计算
- 使用`.animation()`修饰符而非`.withAnimation()`
- 测试低性能设备

## 十二、国际化

### 12.1 文本本地化

- 所有用户可见文本使用`.localized`
- 使用`LocalizedStringKey`
- 提供完整的本地化资源

### 12.2 布局适配

- 支持从右到左（RTL）语言
- 测试不同语言下的布局
- 考虑文本长度差异

### 12.3 日期和数字

- 使用`DateFormatter`和`NumberFormatter`
- 遵循用户区域设置
- 使用相对日期（如"2天前"）

## 十三、代码规范

### 13.1 SwiftUI视图组织

```swift
struct MyView: View {
    // MARK: - Properties
    @State private var state: String = ""
    
    // MARK: - Body
    var body: some View {
        // 视图内容
    }
    
    // MARK: - Helper Methods
    private func helperMethod() { }
}
```

### 13.2 视图提取

- 复杂视图拆分为子视图
- 可复用组件提取为独立视图
- 使用`@ViewBuilder`构建复杂布局

### 13.3 状态管理

- 使用`@State`管理本地状态
- 使用`@Binding`传递状态
- 使用`@EnvironmentObject`共享全局状态
- 使用`@Query`访问SwiftData数据

## 十四、测试检查清单

### 14.1 视觉测试
- [ ] 所有屏幕尺寸（iPhone SE到iPhone Pro Max）
- [ ] 深色模式和浅色模式
- [ ] 横屏和竖屏方向
- [ ] 动态字体大小（最小到最大）
- [ ] 不同语言和本地化

### 14.2 交互测试
- [ ] 所有按钮和链接可点击
- [ ] 手势操作正常工作
- [ ] 动画流畅无卡顿
- [ ] 触觉反馈正常
- [ ] 无障碍功能可用

### 14.3 功能测试
- [ ] 数据加载和显示
- [ ] 错误处理
- [ ] 网络状态变化
- [ ] 权限请求流程
- [ ] 数据同步（如iCloud）

## 十五、参考资源

### 官方文档
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)

### 设计资源
- SF Symbols应用（macOS）
- Apple Design Resources（Sketch、Figma模板）
- iOS设计模板和组件库

### 最佳实践
- 遵循WWDC设计相关session
- 参考Apple官方应用的设计模式
- 关注Apple Design Awards获奖应用

## 十六、Liquid Glass 设计与实现规范（iOS 26+）

> **说明**：Liquid Glass 是 iOS 26 / iPadOS 26 / macOS Tahoe 中推出的全新玻璃视觉与交互体系，用于替代传统 `Material` 毛玻璃。它强调**折射感（Refraction）**、**流体感（Fluidity）**和**动态融合（Morphing）**。本节定义 Footprint 在使用 Liquid Glass 时的范围、实现方式和 HIG 要求。

### 16.1 概念与使用范围

- **核心特性**
  - **光学折射感**：通过对背景内容的弯折与模糊体现「真实玻璃」，而非简单半透明叠加。
  - **流体弹性**：在交互过程中呈现轻微弹性和形变，配合系统动画（如 spring）营造流体感。
  - **动态融合**：多块玻璃与背景、前景之间的过渡自然，不是孤立的硬边卡片。
- **适用场景（推荐）**
  - 底部主导航栏、地图上的悬浮控制条、关键操作条（如行程播放控制、过滤控制）。
  - 底部弹出面板顶部的抓手区域、小型浮动菜单、少量核心按钮的背景。
- **不适用场景（禁止）**
  - 主要内容区域的大面积背景（阅读区、长列表背景等）。
  - 长列表中每一行都使用 Liquid Glass。
  - Liquid Glass 之上再叠加另一层 Liquid Glass（多层玻璃堆叠）。

### 16.2 SwiftUI 实现方式

- **优先使用系统自动 Liquid Glass**
  - 在 iOS 26+ 上，`TabView`、`NavigationSplitView`、`sheet` / `popover`、部分控制组件会自动采用 Liquid Glass 外观。
  - 设计上优先通过系统组件表达玻璃效果，减少完全自绘的玻璃容器。

- **自定义玻璃区域：`.glassEffect` 与降级策略**

#### 胶囊形按钮示例

```swift
import SwiftUI

struct FootprintGlassButton: View {
    var body: some View {
        Button {
            // 业务操作
        } label: {
            Label("打卡", systemImage: "star.fill")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .modifier(GlassButtonStyle())
    }
}

struct GlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())  // 确保整个区域可点击
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
    }
}
```

#### 圆形浮动按钮实现（推荐模式）

圆形浮动按钮是地图悬浮控件、浮动菜单等场景的常见模式。以下是经过验证的实现方式：

```swift
import SwiftUI

// 主按钮实现
struct MainFloatingButton: View {
    @State private var isExpanded = false
    let collapsedDiameter: CGFloat = 60
    let isDarkStyle: Bool = false
    
    var body: some View {
        Button {
            toggleMenu()
        } label: {
            mainButtonContent
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var mainButtonContent: some View {
        if #available(iOS 26, *) {
            Image(systemName: isExpanded ? "xmark" : "circle.hexagongrid.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isDarkStyle ? Color.white : Color.primary)
                .frame(width: collapsedDiameter, height: collapsedDiameter)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())  // 关键：确保整个圆形区域可点击
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        } else {
            Image(systemName: isExpanded ? "xmark" : "circle.hexagongrid.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isDarkStyle ? Color.white : Color.primary)
                .frame(width: collapsedDiameter, height: collapsedDiameter)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(isDarkStyle ? Color.white.opacity(0.12) : Color.white.opacity(0.85))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isDarkStyle ? 0.25 : 0.35), lineWidth: 1)
                        )
                )
                .contentShape(Circle())  // 向后兼容版本也需要
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }
    
    private func toggleMenu() {
        // 切换菜单状态
    }
}

// 径向按钮（子按钮）实现
struct RadialFloatingButton: View {
    let icon: String
    let isActive: Bool
    let isDarkStyle: Bool = false
    
    var body: some View {
        Button {
            // 按钮操作
        } label: {
            radialButtonContent
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var radialButtonContent: some View {
        if #available(iOS 26, *) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isDarkStyle ? Color.white : Color.primary)
                .frame(width: 24, height: 24)
                .padding(14)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())  // 关键：确保整个圆形区域可点击
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        } else {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isDarkStyle ? Color.white : Color.primary)
                .frame(width: 24, height: 24)
                .padding(14)
                .background(
                    Circle()
                        .fill(isDarkStyle ? Color.black.opacity(0.55) : Color.white.opacity(0.95))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isDarkStyle ? 0.25 : 0.2), lineWidth: isActive ? 1.6 : 1)
                        )
                )
                .contentShape(Circle())  // 向后兼容版本也需要
        }
    }
}
```

**关键实现要点：**

1. **使用 `.glassEffect(.regular.interactive(), in: Circle())`**
   - `.regular` 提供标准的玻璃效果强度
   - `.interactive()` 启用交互式反馈（触控时的弹性效果）
   - `in: Circle()` 指定圆形形状

2. **必须添加 `.contentShape(Circle())`**
   - `.glassEffect()` 修饰符可能会改变视图的点击区域
   - `.contentShape(Circle())` 确保整个圆形区域（包括 padding）都可以响应点击
   - 这符合 iOS 设计规范中 44x44 点的最小触控目标要求

3. **保持一致的阴影效果**
   - 使用 `.shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)` 提供深度感
   - 主按钮和径向按钮使用相同的阴影参数，保持视觉一致性

4. **向后兼容实现**
   - iOS 18-25 使用 `.ultraThinMaterial` 或自定义颜色背景
   - 同样需要 `.contentShape(Circle())` 确保点击区域正确
   - 保持相同的视觉尺寸和布局

- **高阶：`GlassEffectContainer` + `glassEffectID`（仅用于少量核心场景）**
  - 适合底部模式切换、少量图标菜单等**需要共享同一玻璃底板并随选择状态形变**的区域。

```swift
import SwiftUI

@available(iOS 26, *)
struct MorphingGlassMenu: View {
    @Namespace private var animation
    @State private var selectedTab = 0

    var body: some View {
        GlassEffectContainer {
            HStack {
                ForEach(0..<3) { index in
                    Button {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            selectedTab = index
                        }
                    } label: {
                        Image(systemName: index == selectedTab ? "circle.fill" : "circle")
                            .padding(12)
                    }
                    .glassEffectID(index, in: animation)
                }
            }
        }
        .glassStyle(.regular)
    }
}
```

> **向后兼容要求**：所有使用 `glassEffect` / `GlassEffectContainer` 的代码必须通过 `if #available(iOS 26, *)` 提供 `Material`（如 `.background(.ultraThinMaterial)`）等价降级方案，确保在 iOS 18–25 上依然有清晰的半透明背景与轮廓。

### 16.3 设计与 HIG 细则

- **1）放在「框架层」，不要占据「内容层」**
  - **应该用**：底部导航 / 顶部工具条 / 地图悬浮控件 / 可拖动面板顶部等接近窗口边缘或内容边界的区域。
  - **不应该用**：整屏大背景、主内容阅读区、长列表每行的背景。
- **2）不要堆叠多层 Liquid Glass（Don’t Stack）**
  - 同一个界面中同时出现的 Liquid Glass 层尽量控制在 **1–2 层**。
  - 不要在已经是 Liquid Glass 的导航栏上再放一块单独的玻璃卡片。
- **3）保持足够留白与对比（Spacing）**
  - Liquid Glass 依赖背景内容（图片 / 地图 / 渐变）来体现折射和深度，应保持**8–12pt 以上**的外边距与周围元素区分。
  - 避免在纯白或纯黑大片区域上放置玻璃容器，以免失去「折射」和「深度」感。
- **4）避免过度动态与眩晕感**
  - 使用 `.interactive(.automatic)` 时，需在真机上验证弹性与亮度变化是否自然、不过度「跳动」。
  - 与应用整体动画节奏保持一致（参考本规范中动画持续时间与曲线设置）。
- **5）确保正确的点击区域（重要）**
  - **必须使用 `.contentShape()` 修饰符**：`.glassEffect()` 可能会改变视图的点击区域，导致只有图标部分可点击，而圆形/胶囊形的 padding 区域无法响应。
  - **实现方式**：在 `.glassEffect()` 之后立即添加 `.contentShape(Circle())` 或 `.contentShape(Capsule())`，确保整个视觉区域都可以点击。
  - **向后兼容**：iOS 18-25 的降级实现也需要 `.contentShape()`，保持一致的交互体验。
  - **测试验证**：在真机上测试按钮边缘区域的点击响应，确保整个圆形区域都能触发操作。

### 16.4 引入步骤建议（团队实践）

- **步骤 1：环境准备**
  - 确认 Xcode 使用支持 iOS 26 SDK 的版本，构建目标包含 iOS 26。
- **步骤 2：从关键导航和地图浮层开始试点**
  - 先在底部主导航栏、地图悬浮控制条、少量核心操作按钮上引入 `glassEffect`。
  - 旧版本保持 `Material` 实现，避免一次性替换所有毛玻璃区域。
- **步骤 3：联动测试（视觉 + 性能 + 无障碍）**
  - 多设备测试（含老机型），观察帧率与电量，必要时减少同时存在的玻璃元素数量。
  - 确保文字对比度与可读性满足无障碍要求，VoiceOver 下可以正确聚焦和朗读。

---

**最后更新**：2025年（基于iOS 26设计标准）
**适用版本**：iOS 18.0+（SwiftUI 5.0+，iOS 26特性按可用性启用）
**向后兼容要求**：所有新特性需提供清晰的`if #available`降级路径，并在设计评审中标注。
**维护者**：开发团队
