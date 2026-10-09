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
  mediaType?: "photo" | "video" | "all"
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
  openDuration?: number
  closeDuration?: number
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
  openDuration?: number
  closeDuration?: number
}

export interface RNAttachmentKit {
  init(licenseKey: string): Promise<boolean>
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateViewerSourceRect(rect: SourceRect): Promise<void>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
  getDefaultAnimationConfig(): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }>
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
