export interface ImageResult {
  uri: string
  width: number
  height: number
  type: string
}

export interface GalleryOptions {
  maxSelection?: number
  mediaType?: "photo" | "video" | "all"
  quality?: number
  allItemsText?: string
  selectedItemsText?: string
  doneButtonText?: string
  recentsAlbumText?: string
  languageCode?: string
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
  themeColor?: string // 테마 컬러 지정 (ex: "#FFEB3B")
  onSelectionChange?: (event: SelectionChangeEvent) => void
}

export interface SelectionChangeEvent {
  selectedCount: number
  maxSelection: number
}

export interface RNAttachmentKit {
  init(licenseKey: string): Promise<boolean>;
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>;
  openEditor(options: EditorOptions): Promise<ImageResult>;
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
}

/**
 * Returns true if using Turbo Module (New Architecture)
 */
export const isUsingTurboModule: boolean

/**
 * Returns true if using Legacy Native Module (Old Architecture)
 */
export const isUsingLegacyModule: boolean

declare const AttachmentKit: RNAttachmentKit

export default AttachmentKit
