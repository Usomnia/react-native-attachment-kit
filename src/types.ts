/** 화면 모드: 기기 설정 따름 / 라이트 강제 / 다크 강제 */
export type Appearance = "system" | "light" | "dark"

/** 모듈이 번역을 내장한 언어 코드 (ISO 639-1, 59개) */
export type SupportedLanguageCode = "af" | "ar" | "be" | "bg" | "bn" | "ca" | "cs" | "cy" | "da" | "de" | "el" | "en" | "eo" | "es" | "et" | "fa" | "fi" | "fr" | "ga" | "gl" | "gu" | "he" | "hi" | "hr" | "ht" | "hu" | "id" | "is" | "it" | "ja" | "ka" | "kn" | "ko" | "lt" | "lv" | "mk" | "mr" | "ms" | "mt" | "nl" | "no" | "pl" | "pt" | "ro" | "ru" | "sk" | "sl" | "sq" | "sv" | "sw" | "ta" | "te" | "th" | "tl" | "tr" | "uk" | "ur" | "vi" | "zh"

/** languageCode 옵션 타입 — 지원 코드 자동완성 + 지역 코드가 붙은 값("pt-BR", "zh_Hans")도 허용 */
export type LanguageCode = SupportedLanguageCode | (string & {})

export interface ImageResult {
  originalUri: string // 원본 URI (ph:// 또는 file://)
  originalFileUri?: string // 원본 해상도의 파일 URI (file://) - 선택적
  originalWidth: number // 원본 width
  originalHeight: number // 원본 height
  uri?: string // resize된 이미지 URI (file://) - 선택적
  width?: number // resize된 width
  height?: number // resize된 height
  type: string // mime type
  caption?: string // 편집기에서 입력한 캡션
  fileName?: string // 파일명
  fileExtension?: string // 확장자
  fileSize?: number // 파일 크기 (bytes)
  /** "image"(기본) | "video" — mediaType: "all"/"video" 로 열었을 때 동영상이면 "video" */
  mediaType?: "image" | "video"
  /** 동영상: 길이(초, 소수) */
  duration?: number
  /**
   * 사진: thumbnail 옵션을 줬을 때 썸네일 file:// (uri 와 같은 결과 사진에서 만듦 — 방향·크롭·그리기 반영, EXIF 없음).
   * 동영상: 포스터 썸네일 (video.posterFormat 형식 — 기본 webp, 긴 변 512. thumbnail 옵션과 무관)
   */
  thumbnailUri?: string
  thumbnailWidth?: number
  thumbnailHeight?: number
  /** 사진 썸네일 파일 크기 (bytes) — thumbnail 옵션을 줬을 때만 */
  thumbnailFileSize?: number
  /** 동영상: 전송본 코덱·평균 비트레이트(bps) */
  videoCodec?: "h264" | "hevc" | string
  videoBitrate?: number
  /** 편집(trim/crop/overlay/음소거/품질 변경)했는지. false 면 원본을 그대로(리먹스) 보낸 것 */
  edited?: boolean
  /** 동영상 변환에 실패했을 때 (uri 없음). 사진·정상 동영상엔 없음. 앱이 취소했으면 "CANCELLED" */
  error?: string
  /** 앱이 cancelVideoProcessing 으로 취소한 동영상 (uri 없음) */
  cancelled?: boolean
}

/**
 * onProcessingStart — 갤러리에서 보낸 직후, 처리(사진 리사이즈·동영상 변환)를 시작하기 전에 한 번.
 * 앱은 이걸로 말풍선 자리를 먼저 만들고(비율·포스터·길이), 동영상은 onVideoProgress 로 진행률을 그린 뒤
 * onImageProcessed(index 같음)가 오면 실제 파일로 바꿉니다.
 */
export interface ProcessingStartEvent {
  /**
   * 이번 보내기의 ID. onVideoProgress / onImageProcessed 에도 같은 값이 붙음.
   * 동영상을 변환하는 동안에도 갤러리를 다시 열어 또 보낼 수 있으므로, 이벤트를 전역 리스너로 받는 앱은 이 값으로 구분
   */
  processingId: string
  total: number
  items: ProcessingStartItem[]
}

export interface ProcessingStartItem {
  index: number
  mediaType: "image" | "video"
  /** ph://… (iOS) / content://… (Android) */
  originalUri?: string
  /** 예상 결과 크기 (사진: 리사이즈 후, 동영상: 품질·크롭 반영). 비율용 */
  width: number
  height: number
  /** 동영상: 보낼 길이(초, 구간 반영) */
  duration?: number
  /** 동영상: 포스터 file:// (video.posterFormat 형식 — 기본 webp, 크롭·그리기 반영) — 변환이 끝나기 전 말풍선에 */
  thumbnailUri?: string
  thumbnailWidth?: number
  thumbnailHeight?: number
}

/**
 * 사진 썸네일 옵션 (GalleryOptions.thumbnail / EditorOptions.thumbnail).
 * 결과 사진(uri)을 만든 같은 이미지에서 만들어 ImageResult.thumbnailUri/Width/Height/FileSize 로 돌려줍니다 (onImageProcessed 에도).
 */
export interface ThumbnailOptions {
  /** 썸네일 최대 가로(px). mode "cover" 면 결과 가로가 정확히 이 값 (원본이 더 작으면 확대하지 않음) */
  maxWidth: number
  /** 썸네일 최대 세로(px). 생략하면 maxWidth 와 같음 */
  maxHeight?: number
  /**
   * "fit"(기본): 원본 비율 유지, maxWidth×maxHeight 상자 안에 맞춤 (예: 모먼트 목록)
   * "cover": 상자를 꽉 채우고 넘치는 부분은 가운데 기준으로 잘라냄 → 결과가 정확히 maxWidth×maxHeight (예: 프로필 아바타).
   *          원본이 상자보다 작으면 확대하지 않고 상자 비율로 가운데만 자름 (100×80 사진 + 200×200 → 80×80)
   */
  mode?: "fit" | "cover"
  /** 0~1, 기본 0.8 */
  quality?: number
  /** 기본 "webp". webp 인코딩이 안 되는 드문 경우 jpg 로 대신 (확장자는 thumbnailUri 로 확인) */
  format?: "webp" | "jpg"
}

/** 동영상 옵션 (GalleryOptions.video). mediaType 이 "video"/"all" 일 때만 의미 */
export interface VideoOptions {
  /** 고를 수 있는 최대 길이(초). 기본 600 (10분). 넘는 동영상은 누르면 안내만. 0 = 제한 없음 */
  maxDurationSec?: number
  /** 전송 결과 최대 용량(MB). 기본 100. 추정치가 넘으면 더 낮은 품질로 자동 조정. 0 = 제한 없음 */
  maxFileSizeMB?: number
  /** 해상도 단계 (세로 px). 기본 [360, 480, 720, 1080]. 원본보다 큰 단계는 쓰지 않음(원본 유지) */
  qualities?: number[]
  /** 기본 품질 (세로 px). 기본 720. 원본이 더 작으면 원본 그대로 */
  defaultQuality?: number
  /** 구간 자르기 허용. 기본 true (편집 화면이 생기는 P2 부터) */
  allowTrim?: boolean
  /** 음소거 버튼 표시. 기본 true (P2 부터) */
  allowMute?: boolean
  /** 코덱. 기본 "h264". "hevc" 는 용량이 작지만 수신 기기 호환을 확인한 경우만 */
  codec?: "h264" | "hevc"
  /**
   * 동영상 포스터(썸네일) 파일 형식. 기본 "webp" (jpg 보다 작음). "jpg" 로 하면 예전처럼 jpg.
   * onProcessingStart / onImageProcessed 의 thumbnailUri 확장자가 이 값을 따름 (webp 인코딩이 안 되는 드문 경우엔 jpg 로 대신하니, 확장자는 uri 로 확인)
   */
  posterFormat?: "webp" | "jpg"
  /** 전송 전 변환 진행률 (동영상마다 0~1, 1% 이상 바뀔 때·최소 0.1초 간격) */
  onProgress?: (e: VideoProgressEvent) => void
  /**
   * 변환하는 동안 화면 가운데 진행 HUD(취소 버튼 포함)를 띄울지.
   * 기본: asyncProcessing 이 아니면 true, asyncProcessing: true 면 false —
   * 이벤트(onProcessingStart / onVideoProgress / onImageProcessed)로 말풍선에 진행 상황을 그리는 앱은 HUD 없이 씁니다.
   * HUD 가 없을 때 취소는 AttachmentKit.cancelVideoProcessing(index)
   */
  showProgressHUD?: boolean
}

export interface VideoProgressEvent {
  index: number
  total: number
  progress: number
  /** 어느 보내기의 진행률인지 (onProcessingStart 의 processingId) */
  processingId?: string
}

export interface SourceRect {
  x: number
  y: number
  width: number
  height: number
}

export interface GalleryOptions {
  maxSelection?: number
  maxWidth?: number // 최대 width
  maxHeight?: number // 최대 height
  /** 기본 "photo" = 사진만(동영상 권한도 요청 안 함). "all" = 사진+동영상 날짜순 혼합, "video" = 동영상만 */
  mediaType?: "photo" | "video" | "all"
  /** 동영상 옵션 (mediaType 이 video/all 일 때) */
  video?: VideoOptions
  /**
   * 사진 썸네일도 함께 만들기. 생략하면 지금처럼 사진 썸네일 없음.
   * 동영상 포스터는 이 옵션과 무관하게 기존 규칙 그대로 (video.posterFormat, 긴 변 512)
   */
  thumbnail?: ThumbnailOptions
  quality?: number
  allItemsText?: string
  selectedItemsText?: string
  doneButtonText?: string
  recentsAlbumText?: string
  /** 지원 언어 코드(59개). "pt-BR", "zh-Hant", "iw" 같은 값도 받아서 지원 코드로 정규화하고, 지원하지 않으면 영어(en)로 표시합니다. */
  languageCode?: LanguageCode
  autoCloseOnSelect?: boolean
  /**
   * 선택 방식.
   * - 'single': 한 장 즉시 선택형 (기존 maxSelection 0/1 동작 — 탭하면 바로 반환, 편집 ON 이면 탭 → 편집 → 전송)
   * - 'multi' : 체크(번호 배지) → (필요하면 편집) → 완료. maxSelection 이 1 이어도 멀티와 똑같이 동작하고,
   *             1장일 때 다른 사진을 고르면 기존 선택과 교체됩니다. autoCloseOnSelect 는 무시되며 maxSelection 생략/1 미만이면 1장.
   * 생략 시 기존 규칙으로 판단: autoCloseOnSelect 또는 maxSelection <= 1 → 단일, 그 외 멀티 (하위 호환)
   */
  selectionMode?: "single" | "multi"
  enableEditor?: boolean // 단일 이미지 선택 시 편집기 활성화 여부
  profileMode?: boolean // 1:1 프로필 크롭 모드 활성화 여부
  themeColor?: string // 테마 컬러 지정 (ex: "#FFEB3B")
  /**
   * 화면 모드. "system"(기본)은 기기 설정을 따르고, "light"/"dark" 는 강제합니다.
   * 생략하면 init / setDefaults 의 appearance 기본값을 씁니다.
   */
  appearance?: Appearance
  asyncProcessing?: boolean // 완전 비동기 이벤트 리턴 여부
  onSelectionChange?: (event: SelectionChangeEvent) => void
  onImageProcessed?: (event: any) => void
  /** 처리 시작 (보낸 직후 한 번) — 모든 자리의 미디어 종류·예상 크기·동영상 포스터. ProcessingStartEvent 참고 */
  onProcessingStart?: (event: ProcessingStartEvent) => void
  /**
   * 갤러리 아래에 첨부 메뉴(갤러리 / 위치 / 파일)를 보여줍니다. 기본 false.
   * 위치 탭: iOS 는 Apple 지도(키 필요 없음), Android 는 Google 지도 — 앱의 AndroidManifest 에
   * `com.google.android.geo.API_KEY` meta-data 가 있어야 지도가 그려집니다 (주소 변환은 기기 내장 Geocoder).
   */
  showAttachMenu?: boolean
  /**
   * 위치 보내기 때 지도 캡처 이미지를 만들지 (기본 true = 예전과 같음).
   * false 면 캡처 없이 위치 정보만 바로 보냅니다 — AttachLocationResult 에 imageUri/imagePath/imageWidth/imageHeight 가 없고,
   * imageSpanMeters 는 캡처했을 때와 같은 값이 옵니다. 받는 쪽은 renderLocationThumbnail 로 썸네일을 그립니다.
   */
  captureLocationImage?: boolean
  /**
   * (Android) 첨부 메뉴 바의 아래 여백 조정 (dp).
   * attachMenuSinkIntoNav: 바가 내비게이션 바 영역으로 내려앉는 정도. 기본 12 (지금 모양). 0 이면 내비게이션 바 바로 위.
   * attachMenuMinBottomMargin: 화면 아래와의 최소 간격. 기본 8.
   * iOS 는 무시.
   */
  attachMenuSinkIntoNav?: number
  attachMenuMinBottomMargin?: number
  /**
   * 위치 탭에서 위치를 보냈을 때 호출됩니다. 이때 openGallery 는 빈 배열로 끝납니다.
   */
  onLocationSelected?: (location: AttachLocationResult) => void
  /**
   * 파일 탭에서 파일을 보냈을 때 호출됩니다 (앱 캐시/임시 폴더로 복사된 파일). 이때 openGallery 는 빈 배열로 끝납니다.
   * Android 는 시스템 파일 선택기(내부 저장 공간 탐색), iOS 는 파일 앱 선택기를 씁니다.
   * 복사에 실패한 파일이 있으면 두 번째 인자 failed 로 { name, error } 목록이 옵니다 (없으면 undefined).
   * 복사본은 iOS tmp/AttachmentKitFiles, Android cache/AttachmentKitFiles 에 있고 24시간이 지난 것은 다음 갤러리 열기 때 지워지므로 바로 옮기거나 업로드하세요.
   */
  onFilesSelected?: (files: AttachFileResult[], failed?: AttachFileFailure[]) => void
  openDuration?: number
  closeDuration?: number
}

/** 첨부 메뉴 > 파일 에서 복사에 실패한 파일 */
export interface AttachFileFailure {
  /** 원래 파일 이름 */
  name: string
  /** 실패 사유 (네이티브 오류 메시지) */
  error: string
}

/** 첨부 메뉴 > 파일 에서 보낸 파일 (앱 캐시/임시 폴더로 복사본) */
export interface AttachFileResult {
  /** file:// URI */
  uri: string
  /** 파일 경로 */
  path: string
  /** 원래 파일 이름 */
  name: string
  /** 바이트 */
  size: number
  mimeType: string
}

/** 첨부 메뉴 > 위치 에서 보낸 위치 */
export interface AttachLocationResult {
  latitude: number
  longitude: number
  /** 정확도(m). 내 현재 위치를 보낼 때만 */
  accuracy?: number
  /** 장소 이름 (장소를 골랐을 때) */
  title?: string
  /** 주소 */
  address?: string
  /** 내 현재 위치를 보냈는지 (false = 지도에서 옮긴 위치 또는 장소) */
  isCurrentLocation: boolean
  /** 보낸 지점의 지도 캡처 (세로형 480×1040 webp (9:19.5), 내 위치 점 없이 핀만). 캡처 실패 시 없음 */
  imageUri?: string
  imagePath?: string
  imageWidth?: number
  imageHeight?: number
  /** 보낸 위치와 별개로, 보낸 순간의 내 현재 위치 (권한이 있고 위치를 알 때만) */
  currentLatitude?: number
  currentLongitude?: number
  /** 내 현재 위치 정확도(m) */
  currentAccuracy?: number
  /** 지도 이미지에 내 위치 점을 그렸는지 ("내 위치 공유" 토글 — 기본 끔, 선택은 기기에 기억) */
  includesMyLocation?: boolean
  /** 마커 종류 (지도 뷰어가 같은 아이콘을 그리도록): "current" 내 위치 / "pin" 지도에서 옮긴 지점 / "place" 장소 */
  markerType?: 'current' | 'pin' | 'place'
  /** (iOS) 장소 종류 — MKPointOfInterestCategory rawValue. 장소일 때만 */
  placeCategory?: string
  /** 보낸 이미지 가로가 덮는 실제 거리(m) — 지도 뷰어를 같은 축척으로 열 때 (captureLocationImage: false 여도 옴) */
  imageSpanMeters?: number
}

/**
 * 위치 메시지 말풍선 지도 썸네일 — 이 기기에서 위치 정보만으로 그려 캐시합니다.
 * AttachLocationResult 값을 그대로 넘기면 보낸 화면과 같은 마커·축척으로 그립니다.
 */
export interface LocationThumbnailOptions {
  latitude: number
  longitude: number
  /** 썸네일 가로 (dp/pt). 결과 이미지는 기기 배율을 곱한 px */
  width: number
  /** 썸네일 세로 (dp/pt). aspect 를 주면 생략 (aspect 가 우선) */
  height?: number
  /**
   * 세로를 가로에서 계산: "square" 1:1 / "portrait" 9:19.5 (보내는 지도 이미지와 같은 비율) /
   * "device" 이 기기 화면 세로 비율 (지도 뷰어를 열 때 말풍선 이미지가 화면을 꼭 맞게 채움).
   * 생략하면 height 를 그대로 씁니다.
   */
  aspect?: 'square' | 'portrait' | 'device'
  /**
   * 결과 이미지 최대 크기 (px). 비율을 유지한 채 이 안에 들어가게 줄입니다.
   * 둘 다 생략하면 512 × 512, 하나만 주면 다른 쪽은 제한하지 않습니다.
   * 예: width 170 + aspect "device" + maxWidth 512 + maxHeight 1152 → 3배 기기에서 약 510×1105 px (세로가 512 로 잘리지 않음)
   */
  maxWidth?: number
  /** 결과 이미지 최대 세로 (px). maxWidth 참고 */
  maxHeight?: number
  /** AttachLocationResult.markerType — 마커 아이콘 */
  markerType?: 'current' | 'pin' | 'place'
  /** (iOS 아이콘) AttachLocationResult.placeCategory */
  placeCategory?: string
  /** 썸네일 가로가 덮는 실제 거리(m). AttachLocationResult.imageSpanMeters. 없으면 400 */
  spanMeters?: number
  /**
   * 보낸 쪽이 "내 위치 공유"를 켰을 때(includesMyLocation)의 내 위치 — 있으면 파란 점을 그리고
   * 두 점이 다 들어오게 범위를 넓힙니다. 공유를 안 켰으면 넘기지 마세요.
   */
  myLatitude?: number
  myLongitude?: number
  /** 마커 색 (기본: setDefaults 의 themeColor) */
  themeColor?: string
  /** 지도 모드. "system" 은 지금 기기/앱 화면 모드. 생략하면 setDefaults 의 appearance */
  appearance?: Appearance
}

export interface LocationThumbnailResult {
  /** file:// (캐시 파일, webp) */
  uri: string
  path: string
  /** 픽셀 크기 */
  width: number
  height: number
  /** 캐시에서 바로 꺼냈는지 */
  cached: boolean
}

/**
 * 지도 뷰어 (위치 메시지를 눌렀을 때). AttachLocationResult 의 값을 그대로 넘기면 보낸 화면과 같은 마커·축척으로 열립니다.
 * sourceRect + sourceImageUri 를 주면 말풍선 이미지가 화면을 채우며 지도로 바뀌고(스티키), 닫을 땐 반대로 돌아갑니다.
 */
/** 좌표 → 주소 (기기 지오코더, 무료). 결과는 디스크에 캐시됩니다 */
export interface ReverseGeocodeOptions {
  latitude: number
  longitude: number
  /**
   * 주소 언어. 앱 언어 코드 그대로 ('ko', 'en', 'ja', 'zh-Hans', 'zh-TW', 'pt-BR' …) — 모듈 UI 언어 목록으로 줄이지 않습니다.
   * 생략하면 setDefaults / init 의 languageCode (넘긴 그대로)
   */
  languageCode?: string
}

export interface ReverseGeocodeResult {
  /** 전체 주소. 위치 탭 address 와 같은 형식 (시·도 시·군·구 동 도로 번지, 국가명 없음). 결과가 없으면 null */
  address: string | null
  /** 목록용 짧은 주소 (동/도로 + 번지). 없으면 null */
  shortAddress: string | null
  /** 디스크(또는 메모리) 캐시에서 바로 꺼냈는지 */
  cached: boolean
}

/**
 * reverseGeocode reject 코드
 *  - E_INVALID_COORDINATE: 범위를 벗어난 좌표 / NaN
 *  - E_GEOCODE_UNAVAILABLE: (Android) 기기에 Geocoder 가 없음
 *  - E_GEOCODE_THROTTLED: 요청 제한(iOS 앱당 분당 약 50건 등) — 잠시 뒤 다시 시도
 *  - E_GEOCODE_TIMEOUT: 지오코더가 8초 안에 답하지 않음
 *  - E_GEOCODE_NETWORK: 오프라인
 *  - E_GEOCODE_FAILED: 그 밖의 오류
 * 오류는 캐시하지 않습니다
 */
export type ReverseGeocodeErrorCode =
  | 'E_INVALID_COORDINATE' | 'E_GEOCODE_UNAVAILABLE' | 'E_GEOCODE_THROTTLED'
  | 'E_GEOCODE_TIMEOUT' | 'E_GEOCODE_NETWORK' | 'E_GEOCODE_FAILED'

export interface MapViewerOptions {
  latitude: number
  longitude: number
  /** 장소 이름 */
  title?: string
  /** 주소. 생략하면 기기 지오코더로 채움 (reverseGeocode 와 같은 캐시, 언어는 languageCode ?? setDefaults 의 languageCode) */
  address?: string
  /** AttachLocationResult.markerType — 보낸 화면과 같은 마커 */
  markerType?: 'current' | 'pin' | 'place'
  /** (iOS) AttachLocationResult.placeCategory */
  placeCategory?: string
  /** AttachLocationResult.imageSpanMeters — 처음 축척을 말풍선 이미지와 맞춤 */
  spanMeters?: number
  /** "길찾기" 버튼 표시 (기본 true) */
  showDirections?: boolean
  /** 말풍선 이미지 위치 (measureInWindow 값 그대로, dp/pt). 있으면 스티키 애니메이션 */
  sourceRect?: SourceRect
  /**
   * 말풍선 이미지 (https:// 또는 file://). 못 불러오면 이미지 없이 지도만 엶.
   * sourceRect 와 비율이 달라도 됩니다 (예: 4:3 칸 + 화면 비율 이미지) — 칸 안에 가운데 크롭(cover)으로 그려
   * 첫 프레임이 말풍선(resizeMode="cover")과 같고, 열리며 잘린 위아래가 펼쳐집니다 (닫을 땐 반대)
   */
  sourceImageUri?: string
  /** 말풍선 이미지 라운드 (dp/pt, 기본 12) */
  sourceCornerRadius?: number
  /**
   * 닫기 애니메이션이 "시작"될 때 (durationMs = 닫기 애니메이션 길이). 프로미스는 다 닫힌 뒤에 끝나므로,
   * 키보드 복귀처럼 닫힘과 동시에 하고 싶은 일은 여기서. Android 는 이 시점에 뷰어 창이 입력 포커스를 내려놓음
   */
  onViewerWillClose?: (e: { durationMs: number }) => void
  /** 마커·버튼 색 (기본: setDefaults 의 themeColor) */
  themeColor?: string
  languageCode?: LanguageCode
  appearance?: Appearance
}

/** 뷰어의 동영상 페이지 정보 (ViewerOptions.videos) */
export interface ViewerVideo {
  /** http(s) 또는 file:// */
  uri: string
  /** 초. 모르면 생략 (불러온 뒤 채움) */
  duration?: number
  /** 절대 경로(file:// 없음). 파일이 있으면 그걸로 재생, 없으면 스트리밍하고 다 받으면 이 경로에 저장 */
  cacheFile?: string
  width?: number
  height?: number
}

export interface ViewerOptions {
  images: string[]
  placeholderImages?: string[]
  /**
   * images 와 같은 순서의 로컬 캐시 파일 경로(절대 경로, file:// 없음). 원격 URL 사진에 대해:
   * 파일이 있으면 네트워크 없이 그 파일을 그리고, 없으면 내려받은 원본 바이트를 그 경로에 저장합니다.
   * (앱이 캐시를 한 곳에서 관리하기 위한 옵션 — 항목이 null/빈 문자열이면 해당 사진은 기존 방식)
   */
  cacheFiles?: (string | null)[]
  /**
   * images 와 같은 순서. 항목이 있으면 그 페이지는 동영상 (null/생략 = 사진) — cacheFiles 와 같은 "평행 배열".
   * 동영상 페이지에서 images[i] 는 포스터(썸네일) 이미지로 쓰입니다 (열기·닫기 애니메이션, 로딩 중 표시).
   * 지원: iOS 뷰어, Android 는 useOverlayViewer: true 일 때 (그 외 Android 뷰어는 포스터만 보임)
   */
  videos?: (ViewerVideo | null)[]
  initialIndex?: number
  themeColor?: string // Added themeColor for Android
  /**
   * 화면 모드. "system"(기본)은 기기 설정을 따르고, "light"/"dark" 는 강제합니다.
   * 생략하면 init / setDefaults 의 appearance 기본값을 씁니다.
   */
  appearance?: Appearance
  title?: string
  animationType?: 'slide' | 'fade' | 'zoom'
  closeAnimationType?: 'slide' | 'fade' | 'zoom'
  sourceRect?: SourceRect
  sourceBorderRadius?: number
  sourceBackgroundColor?: string
  sourceBorderCorners?: ('topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight')[]
  hideSourceImage?: boolean
  onPageSelected?: (index: number) => void
  onViewerWillClose?: () => void
  /**
   * 상단바에 저장/공유/삭제 아이콘 3개를 표시할지 여부. 기본값 true.
   */
  showActionButtons?: boolean
  /** 여러 장(묶음사진)일 때 저장 액션시트에 쓰는 문구들 - 기본값은 한국어. */
  saveAllText?: string
  saveOneText?: string
  shareAllText?: string
  shareOneText?: string
  actionCancelText?: string
  /**
   * 삭제 확인 알럿 문구 - 넘기지 않으면 languageCode(59개 언어 지원, 그 외 언어는 en 폴백)에
   * 맞춰 네이티브 쪽 기본 다국어 문구가 자동으로 적용됩니다.
   */
  deleteConfirmTitle?: string
  deleteConfirmMessage?: string
  /**
   * 여러 장(묶음사진)을 삭제할 때만 쓰이는 경고 문구 - "삭제하면 전체가 함께 삭제된다"는
   * 걸 미리 알려줍니다. deleteConfirmMessage를 넘기면 그게 항상 우선이고, 이건 아무 것도
   * 안 넘겼을 때 사진이 2장 이상일 경우에만 자동으로 붙습니다.
   */
  deleteConfirmGroupMessage?: string
  deleteButtonText?: string
  /**
   * patch405: 삭제 방식 선택지. 넘기면 삭제 확인 팝업에 "삭제" 버튼 하나 대신 이 항목들이
   * (위에서부터 순서대로) 표시되고, 고른 항목의 key 가 onImageDeleted 의 option 으로 전달됩니다.
   * 예) [{ key: 'everyone', label: '나와 상대에게서 삭제', destructive: true },
   *      { key: 'me', label: '나만 삭제', destructive: true }]
   * 넘기지 않으면 기존처럼 [취소] [삭제] 확인 팝업입니다(option 없음).
   */
  deleteOptions?: { key: string; label: string; destructive?: boolean }[]
  /**
   * 삭제 확인 알럿에서 사용자가 삭제를 눌렀을 때 호출됩니다. 네이티브는 실제 데이터를
   * 지우지 않고(뷰어는 그대로 닫힘) 이 콜백으로만 알리므로, 메시지/사진을 실제로
   * 지우는 처리는 RN 쪽에서 담당해야 합니다.
   */
  onImageDeleted?: (event: { index: number; url: string; option?: string }) => void
  /**
   * Android only. 열기 애니메이션이 완전히 끝난 시점에 한 번 호출됩니다.
   * 배경(호스트 화면) 스크롤 보정을 이 콜백 안에서 실행하면, 애니메이션 도중에 보정이
   * 끼어들어 보이지 않고 뷰어가 화면을 완전히 가린 상태에서 안전하게 적용할 수 있습니다.
   */
  onViewerOpened?: () => void
  openDuration?: number
  closeDuration?: number
  /**
   * Android only. When true, opens the viewer as a full-screen DialogFragment
   * instead of a separate Activity. Avoids RN host Activity pausing (onPause),
   * which otherwise makes AppState briefly report background and the underlying
   * RN UI temporarily uncontrollable while the viewer is open.
   *
   * Known limitation: the DialogFragment is still a separate Android Window on
   * top of the host Activity's Window. While it's fully shown, the host Window
   * can be treated as not-visible by the system and its own render traversals
   * (layout/draw) can be skipped, so background RN view changes (e.g. list
   * scroll correction) may not actually take effect on screen until the
   * DialogFragment closes. See useOverlayViewer for a fix.
   * Default: false (existing Activity-based viewer).
   */
  useDialogViewer?: boolean
  /**
   * Android only. When true, opens the viewer as a View added directly on top
   * of the host Activity's existing Window (no separate Activity or Dialog
   * Window at all). This fixes the DialogFragment limitation above: since
   * there's only one Window, background RN view changes made while the viewer
   * is open are reflected immediately (same render tree, same frame).
   * Also avoids any window-focus-change AppState blips entirely.
   * Trade-off: back-press handling, touch blocking, and system-bar insets are
   * managed manually rather than via Activity/DialogFragment lifecycle, so
   * this needs extra QA (rotation, back gesture, other overlays like keyboard).
   * If both useDialogViewer and useOverlayViewer are true, useOverlayViewer wins.
   * Default: false.
   */
  useOverlayViewer?: boolean
}

export interface SelectionChangeEvent {
  selectedCount: number
  maxSelection: number
}

export interface EditorOptions {
  uri: string // 편집할 이미지의 uri (originalUri)
  editedFileUri?: string // 이전에 편집한 이미지의 파일 경로
  themeColor?: string // 편집기 테마 컬러
  /**
   * 화면 모드. "system"(기본)은 기기 설정을 따르고, "light"/"dark" 는 강제합니다.
   * 생략하면 init / setDefaults 의 appearance 기본값을 씁니다.
   */
  appearance?: Appearance
  maxWidth?: number // 최대 width
  maxHeight?: number // 최대 height
  /** 편집 결과 사진의 썸네일도 함께 만들기 (크롭·그리기 반영된 결과 기준) */
  thumbnail?: ThumbnailOptions
  openDuration?: number
  closeDuration?: number
}

// MARK: - Media gallery (사진 모아보기)

/** 갤러리 항목. 썸네일은 파일 경로만 주고받습니다(base64 금지). */
export interface MediaGalleryItem {
  /** 고유 키 (예: "<seq>_<idx>") — 같은 id 가 다시 오면 무시 */
  id: string
  /** 함께 삭제되는 묶음 (예: "<seq>"). 생략 시 id */
  groupId?: string
  /** ms — 월 표시용 */
  timestamp?: number
  /** file:// 썸네일 (그리드·뷰어 플레이스홀더) */
  thumbUri?: string
  /** 원본 (http(s) 또는 file://) */
  imageUri: string
  /** 원본 캐시 경로 (openViewer 의 cacheFiles 와 같은 의미) */
  cacheFile?: string
  /** 삭제 메뉴 구성용 */
  isMine?: boolean
  width?: number
  height?: number
  /** 생략 = 'image'. 'video' 면 imageUri/thumbUri 는 포스터, 재생은 videoUri */
  mediaType?: 'image' | 'video'
  /** 동영상 원본 (http(s) 또는 file://) */
  videoUri?: string
  /** 동영상 캐시 경로 (ViewerVideo.cacheFile 과 같은 의미) */
  videoCacheFile?: string
  /** 초 — 그리드 칸의 "▶ 0:12" 배지 */
  duration?: number
}

export interface MediaGalleryDeleteOption {
  key: string
  label: string
  destructive?: boolean
}

/**
 * 기본 모양·색은 피커 갤러리(openGallery)와 같습니다. isDark 로 다크/라이트 세트를 고르고,
 * 아래 색은 넘긴 것만 덮어씁니다 (생략 권장 — 피커와 똑같이 보이게).
 */
export interface MediaGalleryTheme {
  /** 다크 모드 (생략 시 시스템 설정) */
  isDark: boolean
  /** 시트·칸 사이 배경 */
  screenBg?: string
  /** 사진 로딩 전 칸 색 */
  cellBg?: string
  /** 스켈레톤 */
  skeleton?: string
  titleColor?: string
  subTextColor?: string
}

export interface MediaGalleryViewerOptions {
  themeColor?: string
  deleteOptionsForMine?: MediaGalleryDeleteOption[]
  deleteOptionsForOthers?: MediaGalleryDeleteOption[]
  /** 뷰어 제목 = 사진 날짜 */
  titleFormat?: "date" | "none"
  /** 기존 openViewer 문구 옵션(saveAllText 등)도 그대로 전달 */
  [key: string]: any
}

export interface MediaGalleryItemDeletedEvent {
  galleryId: string
  id: string
  groupId: string
  /** 선택한 삭제 옵션 key */
  option: string
}

export interface MediaGalleryNeedPageEvent {
  galleryId: string
  cursor: string | null
}

export interface MediaGalleryGridSizeChangedEvent {
  galleryId: string
  /** 사용자가 고른 그리드 크기 */
  gridSize: MediaGalleryGridSize
}

export interface MediaGalleryClosedEvent {
  galleryId: string
}

/** 사진 모아보기 그리드 크기 — 한 줄에 3 / 4 / 5칸 */
export type MediaGalleryGridSize = "3x3" | "4x4" | "5x5"

export interface MediaGalleryOptions {
  /** 이벤트 구분용 (생략 시 자동 생성해서 반환) */
  galleryId?: string
  /** (A) 네이티브에 등록된 데이터 소스 이름 (예: 'tinodeChatPhotos', 데모: 'turboDemo') */
  dataSource?: string
  /** (A) 데이터 소스에 그대로 전달 (예: { topic }, 데모: { count: 10000 }) */
  dataSourceParams?: Record<string, any>
  /** (B) JS 공급 — 첫 페이지 */
  initialItems?: MediaGalleryItem[]
  /** (B) 더 있으면 true → 끝에 가까울 때 onNeedPage 호출 */
  hasMore?: boolean
  nextCursor?: string
  /** 상단 바 제목 */
  title: string
  /**
   * 기본 그리드 크기 (사용자가 아직 고른 적이 없을 때). 생략 시 "3x3" (피커와 동일).
   * - "3x3": 한 줄 3칸 / "4x4": 한 줄 4칸 / "5x5": 한 줄 5칸
   * 사용자는 열린 화면의 상단 바 그리드 버튼으로 언제든 바꿀 수 있고, 고른 크기는 기기에 저장되어
   * 다음에 열 때 이 옵션보다 우선합니다. columns 보다 우선합니다.
   */
  gridSize?: MediaGalleryGridSize
  /** @deprecated gridSize 를 쓰세요. 기본 한 줄 칸 수 (gridSize 가 있거나 사용자가 고른 값이 있으면 무시) */
  columns?: number
  /** 칸 사이 간격 pt/dp (기본: 피커와 동일) */
  spacing?: number
  theme?: Partial<MediaGalleryTheme>
  /**
   * 화면 모드. "system"(기본)은 기기 설정을 따르고, "light"/"dark" 는 강제합니다.
   * 생략하면 init / setDefaults 의 appearance 기본값을 씁니다.
   */
  appearance?: Appearance
  /** 월 표시 로케일 */
  languageCode?: LanguageCode
  emptyTitle?: string
  emptySubtitle?: string
  /** 상단 오른쪽 개수, 더 있으면 more 형식 ("{count}" 치환, 기본 "{count}+") */
  countFormat?: { more: string }
  /** 사진을 누르면 그 칸에서 줌으로 열리는 뷰어 설정 (닫으면 지금 보던 사진의 칸으로 돌아감) */
  viewer?: MediaGalleryViewerOptions
  /** 뷰어에서 삭제를 고르면 호출. 모듈은 그 groupId 묶음을 화면에서 이미 지운 상태 — 실제 삭제는 앱이 처리 */
  onItemDeleted?: (event: MediaGalleryItemDeletedEvent) => void
  /** (B) 다음 페이지 요청 → appendGalleryItems 로 응답 */
  onNeedPage?: (event: MediaGalleryNeedPageEvent) => void
  onClosed?: (event: MediaGalleryClosedEvent) => void
  /** 사용자가 상단 바 그리드 버튼으로 크기를 바꿨을 때 (모듈이 이미 기기에 저장함 — 앱이 따로 저장하려면 사용) */
  onGridSizeChanged?: (event: MediaGalleryGridSizeChangedEvent) => void
}

export interface MediaGalleryAppendPayload {
  galleryId: string
  items: MediaGalleryItem[]
  nextCursor?: string
  hasMore: boolean
}

export interface MediaGalleryRemovePayload {
  galleryId: string
  groupIds: string[]
}

/**
 * AI 기능 (갤러리의 AI 생성 · 편집 화면의 AI 편집) 설정과 잔액. `AttachmentKit.setAIConfig` 로 넘기며, 넘긴 값만 바뀝니다.
 * 앱 서버가 진짜 장부이고 모듈은 화면 표시·사용 가능 판단용 사본을 들고 있습니다.
 * 사용 순서: 구독자의 남은 무료 횟수(freeCount, 예: 월 30회) → 포인트(points, 1회 costPerUse) → 모자라면 충전 안내(onAIChargeRequired).
 * 성공한 요청만 차감되고(실패·취소·안전 차단은 무료), 차감할 때마다 onAIUsage 가 옵니다.
 */
export interface AIConfig {
  /** AI 기능 on/off. 기본 false — 꺼져 있으면 갤러리·편집 화면에 AI 버튼이 보이지 않음 */
  enabled?: boolean
  /** 현재 포인트 */
  points?: number
  /** 구독자의 남은 무료 횟수 (예: 월 30회 중 남은 것 — 기간·횟수는 앱/서버가 정함). 0 보다 크면 포인트보다 먼저 씀 */
  freeCount?: number
  /** 1회 차감 포인트. 0 이면 과금 없음 (무제한) */
  costPerUse?: number
  /** 화질 옵션 "고화질(1K)" 1회 차감 포인트. 생략/null 이면 costPerUse */
  highQualityCost?: number | null
  /** 운영: 앱 서버(프록시) 주소. 모듈이 Gemini generateContent 본문을 이 주소로 보내고 서버가 키를 붙여 전달 (헤더 X-AI-Model = 모델 이름) */
  endpoint?: string | null
  /** endpoint 로 보낼 때 붙일 헤더 (예: { Authorization: "Bearer …" }) */
  headers?: Record<string, string>
  /** 테스트 전용 Gemini 키 (앱에 넣어 배포하지 말 것). endpoint 가 있으면 무시 */
  apiKey?: string | null
}

/** AI 를 한 번 성공적으로 썼을 때 (서버에 차감을 반영하는 데 사용) */
export interface AIUsageEvent {
  /** "generate" = 갤러리 AI 생성, "edit" = 편집 화면 AI 편집 */
  kind: "generate" | "edit"
  /** 무료 횟수를 썼으면 true (이때 pointsDeducted = 0) */
  usedFreeCount: boolean
  /** 이번에 차감한 포인트 */
  pointsDeducted: number
  /** 고화질(1K)로 만들었는지 */
  highQuality: boolean
  /** 차감 후 모듈이 들고 있는 값 */
  points: number
  freeCount: number
}

/** 포인트가 모자라 사용자가 '충전하기'를 눌렀을 때 (모듈은 AI 화면을 닫음 → 앱이 충전 화면으로 안내) */
export interface AIChargeRequiredEvent {
  kind: "generate" | "edit"
  /** 1회에 필요한 포인트 */
  required: number
  points: number
  freeCount: number
}
