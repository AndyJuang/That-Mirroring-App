import SwiftUI

// 佔位：圖示在 2 秒內被點 5 次時，trigger 從 0 起每次加 1。
// 維持型別名 CatWinkEffect 與參數 trigger。之後只替換這個 modifier 的動畫：
// 眨一隻眼、周圍 6 到 8 顆小星星、約 0.8 到 1.2 秒、無音效。
// 系統開啟「減少動態效果」時只淡入淡出一次。
struct CatWinkEffect: ViewModifier {
    var trigger: Int

    @ViewState private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _, value in
                guard value > 0, !reduceMotion else { return }
                scale = 0.92
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { self.scale = 1 }
                }
            }
    }
}
