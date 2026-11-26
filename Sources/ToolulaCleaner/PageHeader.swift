import SwiftUI

/// 工具页面顶部: 图标 + 标题 + 说明, 右边一个大数字
struct PageHeader<Trailing: View, Bar: View>: View {
    let icon: String
    let title: String
    let desc: String
    @ViewBuilder let trailing: () -> Trailing
    /// 下面一行: 提示 + 选项 + 按钮
    @ViewBuilder let bar: () -> Bar

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.toolula)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.toolula.opacity(0.13)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 26, weight: .bold))
                    Text(desc).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                trailing()
            }
            HStack(spacing: 10) { bar() }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }
}

/// 右上角的大数字 + 下面一行小字
struct BigNumber: View {
    let value: String
    let sub: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(sub).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 页面中间的大提示 (很干净 / 还没开始)
struct CenterNote: View {
    let icon: String
    let title: String
    let text: String
    var color: Color = .toolula
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(color)
            Text(title).font(.title2.weight(.semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
        }
    }
}

/// 小标签 (运行中 / 保留 / 程序已不存在)
struct Badge: View {
    let text: String
    var color: Color = .orange
    var body: some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1).fixedSize()
    }
}
