import SwiftUI
import UIKit

/// 이 파일 안에서만 보이는 원색. 밖에서는 ``WoorisaiColor``의 역할 이름으로만 닿을 수 있다.
///
/// 색 이름은 역할을 말하지 않는다. `coral`이 텍스트에 안전한지, 배경으로 써도 되는지, 그것이
/// "내 것"을 뜻하는지 이름만 봐서는 알 수 없고 — 실제로 그 셋이 한 이름 아래 뒤섞여 있었다.
/// 그래서 원색은 값의 보관소로만 남기고, 의미는 전부 ``WoorisaiColor`` 쪽에 적는다.
private enum WoorisaiPalette {
  /// SwiftUI 밖 chrome(프라이버시 커버)용. 아래 `cream`·`coral`과 같은 값을 유지할 것.
  static let creamUIColor = adaptiveUIColor(light: (255, 248, 241), dark: (23, 19, 18))
  static let coralUIColor = adaptiveUIColor(light: (217, 92, 78), dark: (255, 143, 125))

  static let cream = Color(uiColor: creamUIColor)
  static let creamDeep = adaptive(light: (249, 238, 228), dark: (46, 37, 33))
  static let surface = adaptive(light: (255, 252, 250), dark: (37, 31, 29))
  static let field = adaptive(light: (255, 251, 248), dark: (48, 40, 37))
  static let selectedSurface = adaptive(light: (255, 240, 236), dark: (58, 40, 37))
  static let ink = adaptive(light: (57, 45, 42), dark: (247, 238, 234))
  static let muted = adaptive(light: (112, 94, 88), dark: (200, 181, 172))
  static let line = adaptive(light: (160, 139, 130), dark: (142, 114, 104))
  static let coral = Color(uiColor: coralUIColor)
  static let coralDark = adaptive(light: (168, 63, 53), dark: (255, 170, 153))
  static let coralSoft = adaptive(light: (255, 224, 216), dark: (84, 48, 43))
  static let rose = adaptive(light: (246, 181, 173), dark: (192, 120, 112))
  static let sage = adaptive(light: (75, 113, 86), dark: (155, 201, 168))
  static let sageSoft = adaptive(light: (228, 240, 231), dark: (43, 69, 51))
  static let success = adaptive(light: (61, 110, 75), dark: (155, 213, 169))
  static let error = adaptive(light: (180, 35, 24), dark: (255, 180, 171))
  static let primaryButtonStart = adaptive(light: (193, 64, 52), dark: (183, 62, 52))
  static let primaryButtonEnd = adaptive(light: (150, 47, 40), dark: (132, 42, 36))
  static let primaryButtonDisabled = adaptive(light: (132, 102, 97), dark: (140, 108, 102))
  // 다크 모드에서 순검정 그림자는 따뜻한 어두운 배경에 묻혀 카드를 납작하게 만든다. 대신 옅은
  // 웜 글로우가 높이로 읽힌다. 투명도는 `WoorisaiElevation`이 단계별로 정한다.
  static let shadow = adaptive(light: (57, 45, 42), dark: (255, 190, 175))

  private static func adaptive(
    light: (red: Int, green: Int, blue: Int),
    dark: (red: Int, green: Int, blue: Int)
  ) -> Color {
    Color(uiColor: adaptiveUIColor(light: light, dark: dark))
  }

  private static func adaptiveUIColor(
    light: (red: Int, green: Int, blue: Int),
    dark: (red: Int, green: Int, blue: Int)
  ) -> UIColor {
    UIColor { traits in
      let components = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(
        red: CGFloat(components.red) / 255,
        green: CGFloat(components.green) / 255,
        blue: CGFloat(components.blue) / 255,
        alpha: 1
      )
    }
  }
}

/// 역할 기반 색상 토큰. 뷰는 이 타입만 참조하고, 원색(`WoorisaiPalette`)은 직접 쓰지 않는다.
///
/// 이름은 daangn/seed-design의 어법(`bg` / `fg` / `stroke` × 의미 × 강도)을 따른다. 색 이름
/// (`coral`, `sage`)이 아니라 역할로 부르면, 브랜드 톤을 조정할 때 바꿀 지점이 코드에서 바로
/// 드러난다. 예전 `coralDark`는 50곳에 쓰였지만 그중 무엇이 "브랜드 강조"이고 무엇이 "그냥 진한
/// 코랄"인지 구분할 방법이 없었다.
///
/// Seed에 없는 축이 하나 있다: ``Authorship``. 이 앱은 거의 모든 화면에서 "내 것 / 상대 것"을
/// 색으로 구분하는데, Seed의 brand·neutral·critical 축으로는 그 의미가 표현되지 않는다.
///
/// 원색으로 새는 것을 막기 위해 축을 넉넉히 둔다. 표현할 이름이 없으면 `.white`나 `Color.black`
/// 같은 시스템 색으로 우회하게 되고(실제로 그렇게 20곳이 샜다), 그건 grep으로도 잡히지 않는다.
/// 필요한 역할이 없다면 원색을 직접 쓰지 말고 여기에 축을 추가할 것.
enum WoorisaiColor {

  // MARK: - 배경

  enum Bg {
    /// 화면 바탕. `WarmBackground`가 깔아주는 가장 아래 레이어.
    static let layerBasement = WoorisaiPalette.cream
    /// 바탕 위에 뜬 카드·시트의 면.
    static let layerDefault = WoorisaiPalette.surface
    /// 바탕보다 한 단계 눌러 앉은 영역(미디어 갤러리처럼 콘텐츠가 잠기는 곳).
    static let layerSunken = WoorisaiPalette.creamDeep
    /// 아래 내용을 살짝 비추는 눌러앉은 면(업로드 항목 행, 이미지 뷰어 바탕).
    /// 호출부가 0.72와 0.58을 따로 쓰고 있었는데 진한 쪽으로 맞췄다.
    static let layerSunkenAlpha = WoorisaiPalette.creamDeep.opacity(0.72)
    /// 입력 필드처럼 "채워 넣는" 면.
    static let layerFill = WoorisaiPalette.field
    /// 선택된 항목의 면.
    static let selected = WoorisaiPalette.selectedSurface

    /// 브랜드 강조 배경(아이콘 버튼 원형 배경, 내 말풍선 등).
    static let brandWeak = WoorisaiPalette.coralSoft
    /// 안내 메시지 면. ``brandWeak``보다 물러나되 읽는 사람 눈에는 걸린다.
    static let brandWeakAlpha = WoorisaiPalette.coralSoft.opacity(0.5)
    /// 넓은 영역을 브랜드 톤으로 옅게 덮을 때(PIN 입력부 같은 섹션 바탕).
    static let brandSubtle = WoorisaiPalette.coralSoft.opacity(0.34)
    /// 브랜드 솔리드 배경. 위에 올릴 것은 ``Fg/brandContrast``.
    ///
    /// **흰 글자를 얹는 브랜드 면은 반드시 이 토큰이다.** `Fg` 축의 브랜드 색들은 글자·아이콘용
    /// 이라 배경으로 돌리면 흰 글자와의 대비가 무너진다 — ``Fg/brandVivid``는 다크모드에서
    /// 2.2:1, ``Fg/brand``는 1.8:1까지 떨어진다. 이 색은 라이트 5.18:1, 다크 5.60:1을 지킨다.
    ///
    /// `.buttonStyle(.borderedProminent)`의 `.tint(_:)`도 배경을 칠하므로 여기에 해당한다.
    static let brandSolid = WoorisaiPalette.primaryButtonStart
    /// 비활성 컨트롤의 배경.
    static let disabled = WoorisaiPalette.primaryButtonDisabled
    /// 선명한 브랜드 면. **위에 글자를 올리지 않는** 표시자·점에만 쓴다(타임라인 노드 등).
    /// 글자를 올려야 하면 ``brandSolid``.
    static let brandVivid = WoorisaiPalette.coral

    /// 사진 뷰어처럼 콘텐츠에 몰입시키는 전체화면 배경.
    ///
    /// 테마를 따르지 않고 항상 검정이다. 라이트 모드에서 크림색 위에 사진을 띄우면 밝은 사진의
    /// 경계가 흐려지고 색 인지가 왜곡된다 — 사진 앱들이 공통으로 검정을 쓰는 이유다.
    static let immersive = Color.black

    /// 사진 위에 얹는 컨트롤의 어두운 받침. 사진이 무슨 색이든 위의 흰 아이콘이 읽히게 한다.
    ///
    /// 호출부에 0.36부터 0.68까지 일곱 가지 투명도가 흩어져 있던 것을 세 단으로 접었다.
    /// 받침이 필요한 이유는 하나(가독성)인데 값이 일곱 개일 이유는 없다.
    static let scrimWeak = Color.black.opacity(0.44)
    static let scrim = Color.black.opacity(0.58)
    /// 여러 컨트롤을 한 판에 묶는 패널.
    static let scrimStrong = Color.black.opacity(0.68)
  }

  // MARK: - 전경 (텍스트 · 아이콘)

  enum Fg {
    /// 본문 텍스트.
    static let neutral = WoorisaiPalette.ink
    /// 보조 설명, 캡션, 메타 정보.
    static let neutralMuted = WoorisaiPalette.muted
    /// 입력 전 자리표시 문구.
    static let placeholder = WoorisaiPalette.muted

    /// 브랜드 색 텍스트·아이콘. 대비를 확보한 진한 톤이라 글자에 써도 된다.
    ///
    /// **배경으로는 쓰지 않는다.** 다크모드에서 이 색은 밝은 살구빛(255,170,153)으로 뒤집히므로
    /// 위에 흰 글자를 올리면 1.8:1까지 떨어진다. 브랜드 면은 ``Bg/brandSolid``.
    static let brand = WoorisaiPalette.coralDark
    /// 아이콘·틴트 전용의 선명한 브랜드 톤.
    ///
    /// **본문 텍스트에도, 배경에도 쓰지 않는다.** 크림 배경 위 3.57:1(아이콘은 되지만 본문
    /// 기준 4.5:1 미달)이고, 이 색을 배경 삼아 흰 글자를 올리면 다크모드에서 2.2:1까지 떨어진다.
    /// 글자에는 ``brand``, 배경에는 ``Bg/brandSolid``를 쓸 것.
    static let brandVivid = WoorisaiPalette.coral
    /// 2톤 심볼(`foregroundStyle(_:_:)`)의 보조 톤. 주 톤은 ``brandVivid``.
    static let brandWeak = WoorisaiPalette.coralSoft
    /// 브랜드 솔리드 배경(``Bg/brandSolid``, 그라디언트 버튼) 위에 올리는 라벨·아이콘.
    static let brandContrast = Color.white
    /// 테마와 무관하게 항상 흰색이어야 하는 전경. ``Bg/immersive`` 위의 텍스트·아이콘,
    /// 그리고 솔리드 상태색을 배경 삼는 2톤 심볼의 안쪽 톤.
    static let staticWhite = Color.white
    /// ``staticWhite``의 보조 톤. 몰입 배경 위의 캡션·부가 정보.
    static let staticWhiteMuted = Color.white.opacity(0.88)

    /// 오류·한도 초과.
    static let critical = WoorisaiPalette.error
    /// 완료·성공.
    static let positive = WoorisaiPalette.success

    /// 브랜드 톤과 짝을 이루는 차분한 강조. 빈 상태 아이콘처럼 재촉하지 않아야 하는 자리에 쓴다.
    static let calm = WoorisaiPalette.sage
  }

  // MARK: - 테두리

  enum Stroke {
    /// 카드·필드의 기본 경계선.
    static let neutralWeak = WoorisaiPalette.line
    /// 오류 상태의 필드 경계선.
    static let critical = WoorisaiPalette.error
    /// 선택된 항목의 테두리. 셋 중 가장 또렷하다.
    static let brandSolid = WoorisaiPalette.coral
    /// 브랜드 톤 경계선(토스트 등). 호출부에서 별도 투명도를 얹지 말 것.
    static let brandWeak = WoorisaiPalette.coral.opacity(0.28)
    /// 브랜드임을 귀띔만 하는 경계선(로고 카드 등).
    static let brandSubtle = WoorisaiPalette.coral.opacity(0.16)
  }

  // MARK: - 작성자 (이 앱 고유 축)

  /// 게시물·댓글·점수 변경을 남긴 사람. 색으로 화자를 구분하는 것이 이 앱의 핵심 표현이라
  /// 별도 축으로 둔다.
  enum Authorship {
    case mine
    case partner

    init(isMine: Bool) {
      self = isMine ? .mine : .partner
    }
  }

  /// 작성자별 전경색(이름, 아이콘, 틴트).
  static func fg(_ authorship: Authorship) -> Color {
    switch authorship {
    case .mine: WoorisaiPalette.coral
    case .partner: WoorisaiPalette.sage
    }
  }

  /// 작성자별 말풍선·카드 배경.
  static func bg(_ authorship: Authorship) -> Color {
    switch authorship {
    case .mine: WoorisaiPalette.coralSoft
    case .partner: WoorisaiPalette.field
    }
  }

  /// 작성자별 카드·말풍선 테두리.
  ///
  /// 내가 쓴 것에는 브랜드 톤 윤곽을, 상대 것에는 중립 윤곽을 두른다. 호출부 세 곳이 내 쪽
  /// 투명도를 0.24와 0.2로 다르게 쓰고 있었는데 진한 쪽으로 맞췄다.
  static func stroke(_ authorship: Authorship) -> Color {
    switch authorship {
    case .mine: WoorisaiPalette.coral.opacity(0.24)
    case .partner: Stroke.neutralWeak
    }
  }

  // MARK: - 미디어 종류

  /// 첨부물이 사진인지 동영상인지. 미리보기를 만들지 못했을 때 대신 세우는 자리표시 타일이
  /// 종류에 따라 색을 달리한다.
  enum MediaKind {
    case image
    case video

    init(isImage: Bool) {
      self = isImage ? .image : .video
    }
  }

  /// 자리표시 타일의 아이콘 색.
  static func fg(_ kind: MediaKind) -> Color {
    switch kind {
    case .image: WoorisaiPalette.coral
    case .video: WoorisaiPalette.sage
    }
  }

  /// 자리표시 타일의 배경.
  ///
  /// 업로드 타일과 첨부 타일이 같은 자리표시인데 한쪽만 종류별로 칠하고 다른 쪽은 종류와
  /// 무관하게 세이지를 깔고 있었다. 종류별로 맞췄다.
  static func bg(_ kind: MediaKind) -> Color {
    switch kind {
    case .image: WoorisaiPalette.coralSoft.opacity(0.5)
    case .video: WoorisaiPalette.sageSoft
    }
  }

  // MARK: - 점수 증감

  /// 관계 점수의 변화 방향.
  ///
  /// 방향을 색상(hue)으로 가르지 않는다. 세 가지 이유가 겹친다.
  ///
  /// - 부호가 이미 라벨에 있다(`"+3점"` / `"-2점"` / `"변화 없음"`). 색은 중복 신호이므로
  ///   빠져도 판독에 손실이 없고, 색만으로 정보를 전달하지 말라는 HIG 권고에도 맞다.
  /// - 예전에 쓰던 코랄(적)과 세이지(녹)는 적록색약에게 같은 색으로 보인다. 하필 두 배지를
  ///   구분하는 유일한 단서가 그 색상 차이였다.
  /// - 그 두 색은 ``Authorship``의 나/상대 색이기도 하다. 상대가 점수를 올린 이력에서는
  ///   화자 색과 방향 색이 한 행에 동시에 나와 무엇이 무엇을 뜻하는지 뒤섞였다.
  ///
  /// 대신 강조의 세기로 구분한다. 올랐을 때만 브랜드 톤으로 눈에 띄고, 내려갔을 때는 조용히
  /// 또렷하게 읽히며(중립 톤·대비 11:1), 변화가 없으면 가장 약하게 물러난다. 관계 점수가
  /// 내려간 것은 오류가 아니라 기록된 사실이므로 경고색을 쓰지 않는다.
  enum Delta {
    case increase
    case decrease
    case unchanged

    init(_ value: Int) {
      if value > 0 {
        self = .increase
      } else if value < 0 {
        self = .decrease
      } else {
        self = .unchanged
      }
    }
  }

  /// 점수 변화량 라벨 색.
  static func fg(_ delta: Delta) -> Color {
    switch delta {
    case .increase: Fg.brand
    // 비활성이 아니라 "조용한 사실"이므로 muted가 아닌 본문 색을 쓴다.
    case .decrease: Fg.neutral
    case .unchanged: Fg.neutralMuted
    }
  }

  /// 점수 변화량 배지 배경.
  static func bg(_ delta: Delta) -> Color {
    switch delta {
    case .increase: Bg.brandWeak
    case .decrease: Bg.layerSunken
    case .unchanged: Bg.layerFill
    }
  }

  /// 점수 변화량 배지 테두리.
  ///
  /// 브랜드 배지는 채도만으로 카드면에서 떠 보이지만, 중립 배지의 면은 카드면과 명도차가
  /// 1.1:1 남짓이라 형태가 사라진다. 테두리로 윤곽을 세운다.
  static func stroke(_ delta: Delta) -> Color? {
    switch delta {
    case .increase: nil
    case .decrease, .unchanged: Stroke.neutralWeak
    }
  }

  // MARK: - 컴포넌트 전용

  /// 특정 컴포넌트 하나에서만 의미를 갖는 색. 다른 화면에서 갖다 쓰지 말 것 — 그렇게 쓸 일이
  /// 생겼다면 위쪽 역할 축에 이름이 없다는 뜻이다.
  enum Component {
    enum PrimaryButton {
      /// 배경 그라디언트의 아래쪽 끝. 위쪽 끝은 ``Bg/brandSolid``.
      static let solidEnd = WoorisaiPalette.primaryButtonEnd
      /// 눌린 동안의 배경. 그라디언트의 진한 쪽으로 전체가 가라앉는다.
      static let solidPressed = WoorisaiPalette.primaryButtonEnd
    }

    enum IconButton {
      /// 원형 배경. 브랜드 강조면을 한 겹 더 눕혀 툴바에서 튀지 않게 한다.
      static let background = WoorisaiPalette.coralSoft.opacity(0.72)
      /// 눌린 동안. 평소보다 또렷해진다.
      static let backgroundPressed = WoorisaiPalette.coralSoft
    }

    /// SwiftUI 밖에서 쓰는 UIKit 색. 프라이버시 커버처럼 앱 스위처에 잡히는 chrome은
    /// `UIViewController` 수준에서 칠해야 해서 `UIColor`가 필요하다. 시스템 시맨틱 색
    /// (`.systemBackground` 등)으로 대체하면 따뜻한 브랜드 배경 위에 흑백이 번쩍인다.
    enum UIKit {
      static let background = WoorisaiPalette.creamUIColor
      static let brandMark = WoorisaiPalette.coralUIColor
      /// 코드로 그리는 도형의 흰 부분(알림 썸네일 등).
      static let staticWhite = UIColor.white
    }

    enum SelectableCard {
      /// 선택된 카드가 살짝 떠 보이게 하는 브랜드 톤 광. 중립 그림자(``WoorisaiElevation``)와
      /// 달리 색으로 선택 상태를 거든다.
      static let glow = WoorisaiPalette.coral.opacity(0.09)
    }
  }

  // MARK: - 장식

  /// `WarmBackground`의 분위기 레이어. 의미를 전달하지 않으며 `accessibilityHidden`이다.
  enum Decor {
    static let ambientBrand = WoorisaiPalette.coralSoft
    static let ambientCalm = WoorisaiPalette.sageSoft
    static let dotWarm = WoorisaiPalette.rose
    static let dotCalm = WoorisaiPalette.sage
    static let dotBrand = WoorisaiPalette.coral

    /// 일기 카드 위에 붙은 마스킹 테이프(`DiaryPaperTape`).
    static let tapeFill = WoorisaiPalette.sageSoft.opacity(0.92)
    static let tapeEdge = WoorisaiPalette.sage.opacity(0.2)
  }
}

/// 그림자 3단. 값이 흩어지지 않도록 색·반경·오프셋을 한 묶음으로 둔다.
///
/// 호출부에 흩어져 있던 네 조합(`0.08/10/4`, `0.12/12/6`, `0.16/12/4`, `0.2/12/6`)을 세 단으로
/// 접었다. 위로 갈수록 짙고 넓고 멀어지도록 단조롭게 맞춘 것이라 `0.16/12/4`만 s2로 흡수됐다.
///
/// 다크 모드에서 순검정 그림자는 따뜻한 어두운 배경에 묻혀 모든 카드가 납작해지므로,
/// 색이 은은한 웜 글로우로 뒤집힌다.
enum WoorisaiElevation {
  /// 카드·표면.
  case s1
  /// 떠 있는 요소 — 토스트, 로고 카드.
  case s2
  /// 주요 액션 버튼.
  case s3

  var color: Color {
    switch self {
    case .s1: WoorisaiPalette.shadow.opacity(0.08)
    case .s2: WoorisaiPalette.shadow.opacity(0.12)
    case .s3: WoorisaiPalette.shadow.opacity(0.2)
    }
  }

  var radius: CGFloat {
    switch self {
    case .s1: 10
    case .s2, .s3: 12
    }
  }

  var offsetY: CGFloat {
    switch self {
    case .s1: 4
    case .s2, .s3: 6
    }
  }
}

extension View {
  func woorisaiShadow(_ elevation: WoorisaiElevation) -> some View {
    shadow(color: elevation.color, radius: elevation.radius, y: elevation.offsetY)
  }
}
