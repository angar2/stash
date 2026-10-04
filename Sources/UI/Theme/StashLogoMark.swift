// TASK-105 — 땅콩 로고(MenuBarIcon) 공통 뷰. 정사각 이미지의 위아래 투명 여백을 배치에서 빼고, 보이는 땅콩 크기(가로 × 가로/2)로 자리를 잡는다.
// 메뉴바·토스트는 정사각 칸 그대로 쓰고, 칸 안 여백이 주변 배치를 밀어내면 안 되는 곳(팝오버 머리·온보딩 키캡)에서 쓴다. 색은 호출부 foregroundStyle을 따른다 (template).
import SwiftUI

struct StashLogoMark: View {
    /// 보이는 땅콩 가로. 세로는 `markHeight(forWidth:)` (가로의 절반).
    let width: CGFloat

    // MenuBarIcon@2x(44×44) 안 땅콩 위치 — 가로 꽉 참, 위 여백 10 · 높이 22. 이미지를 바꾸면 StashLogoMarkTests가 어긋남을 잡는다.
    static let imageSide: CGFloat = 44
    static let markTop: CGFloat = 10
    static let markHeight: CGFloat = 22

    static func markHeight(forWidth width: CGFloat) -> CGFloat {
        width * markHeight / imageSide
    }

    /// 정사각 이미지를 땅콩 틀 가운데 두면 땅콩이 위로 치우친 만큼(이미지 기준 1/44) 아래로 내려 틀에 꼭 맞춘다.
    static func verticalOffset(forWidth width: CGFloat) -> CGFloat {
        width / 2 - (markTop + markHeight / 2) / imageSide * width
    }

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .frame(width: width, height: width)
            .offset(y: Self.verticalOffset(forWidth: width))
            .frame(width: width, height: Self.markHeight(forWidth: width))
    }
}
