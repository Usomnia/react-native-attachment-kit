import { NativeModules, Platform, TurboModuleRegistry, NativeEventEmitter, DeviceEventEmitter } from "react-native"
import type { ImageResult, GalleryOptions, EditorOptions, SelectionChangeEvent, ViewerOptions, MediaGalleryOptions, MediaGalleryAppendPayload, MediaGalleryRemovePayload, Appearance, AIConfig, AIUsageEvent, AIChargeRequiredEvent } from "./types"

const LINKING_ERROR = `The package 'react-native-attachment-kit' doesn't seem to be linked. Make sure: \n\n` + Platform.select({ ios: "- You have run 'pod install'\n", default: "" }) + "- You rebuilt the app after installing the package\n" + "- You are not using Expo Go\n"

// Try to get Turbo Module first (New Architecture)
let NativeAttachmentKit: any = null

try {
  // @ts-ignore - TurboModuleRegistry might not be available
  NativeAttachmentKit = TurboModuleRegistry?.get?.("RNAttachmentKit")
} catch (e) {
  // Turbo Module not available
}

let _defaultThemeColor = "#10b981";
let _defaultLanguageCode = "en";
/** setDefaults/init 에 넘긴 언어 코드 그대로 (예: "zh-Hans", "pt-BR") — 주소(역지오코딩)는 UI 언어 목록으로 줄이지 않음 */
let _rawLanguageCode: string | null = null;
let _defaultAppearance: Appearance = "system";

/** "light" | "dark" 외의 값(생략·오타 포함)은 "system" */
export function normalizeAppearance(value?: string | null): Appearance {
  const v = String(value ?? "").trim().toLowerCase()
  return v === "light" || v === "dark" ? v : "system"
}

/** 모듈이 번역을 내장한 언어 코드 (ISO 639-1, 59개) */
export const SUPPORTED_LANGUAGE_CODES: readonly string[] = ["af", "ar", "be", "bg", "bn", "ca", "cs", "cy", "da", "de", "el", "en", "eo", "es", "et", "fa", "fi", "fr", "ga", "gl", "gu", "he", "hi", "hr", "ht", "hu", "id", "is", "it", "ja", "ka", "kn", "ko", "lt", "lv", "mk", "mr", "ms", "mt", "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sq", "sv", "sw", "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh"]
const LANGUAGE_ALIASES: Record<string, string> = { iw: "he", in: "id", nb: "no", nn: "no", fil: "tl" }

/**
 * "pt-BR", "zh_Hant", "EN", "iw" 같은 값을 모듈 지원 언어 코드로 정규화합니다.
 * 지원하지 않는 언어면 "en" 을 돌려줍니다.
 */
export function normalizeLanguageCode(code?: string | null): string {
  if (!code) return "en"
  const base = String(code).trim().toLowerCase().split(/[-_]/)[0]
  const mapped = LANGUAGE_ALIASES[base] ?? base
  return SUPPORTED_LANGUAGE_CODES.includes(mapped) ? mapped : "en"
}

export interface InitOptions {
  languageCode?: string;
  themeColor?: string;
  /**
   * 화면 모드 기본값. "system"(기본) = 기기 설정을 따름, "light"/"dark" = 강제.
   * 각 open* 호출의 appearance 옵션이 있으면 그게 우선합니다.
   */
  appearance?: Appearance;
}

/** 기본값만 바꿀 때 (예: 앱 설정에서 테마/언어를 바꾼 직후). 넘긴 값만 바뀝니다. */
export type DefaultOptions = InitOptions

// Fallback to Legacy Native Module (Old Architecture)
const LegacyModule = NativeModules.RNAttachmentKit

// Use Turbo Module if available, otherwise use Legacy Module
const RNAttachmentKitModule = NativeAttachmentKit || LegacyModule

if (!RNAttachmentKitModule) {
  throw new Error(LINKING_ERROR)
}

// Create event emitter
const eventEmitter = new NativeEventEmitter(RNAttachmentKitModule)

/** 같은 화면을 중복으로 열려고 할 때 reject 하는 Error (code: "E_ALREADY_OPEN") */
function alreadyOpenError(what: string): Error {
  const err = new Error(`${what} is already open`)
  ;(err as any).code = "E_ALREADY_OPEN"
  return err
}

/**
 * openGallery 가 아직 끝나지 않았는지. 네이티브는 갤러리 Promise 를 하나만 보관하므로(iOS currentGalleryVC,
 * Android pickImagesPromise) 중복 호출하면 앞 호출의 Promise 가 영영 끝나지 않습니다 → JS 에서 먼저 막습니다.
 */
let _galleryOpen = false
/** 어느 openGallery 호출이 _galleryOpen 을 잡고 있는지 — 처리 시작(onProcessingStart)에 먼저 풀고, 늦게 끝난 앞 호출이 새 호출의 잠금을 풀지 않게 */
let _galleryOpenToken = 0
/** openEditor 도 Android 가 editImagePromise 하나만 보관하므로 같은 보호가 필요 */
let _editorOpen = false
/**
 * asyncProcessing 모드의 onImageProcessed 구독. 이 모드에선 openGallery 가 끝난 뒤에도 이벤트가 오므로
 * finally 에서 제거하지 않고, 다음 openGallery(asyncProcessing) 호출 때 이전 구독만 제거합니다 (최대 1개 유지).
 */
let _asyncImgProcessedSub: { remove: () => void } | null = null

export type { AIConfig, AIUsageEvent, AIChargeRequiredEvent } from "./types"
export type { VideoOptions, VideoProgressEvent, ViewerVideo, ProcessingStartEvent, ProcessingStartItem, ThumbnailOptions } from "./types"
export type { SelectionChangeEvent, Appearance, AttachLocationResult, MapViewerOptions, ReverseGeocodeOptions, ReverseGeocodeResult, ReverseGeocodeErrorCode, AttachFileResult, AttachFileFailure, LocationThumbnailOptions, LocationThumbnailResult } from "./types"
export type { MediaGalleryItem, MediaGalleryOptions, MediaGalleryGridSize, MediaGalleryGridSizeChangedEvent, MediaGalleryTheme, MediaGalleryViewerOptions, MediaGalleryDeleteOption, MediaGalleryItemDeletedEvent, MediaGalleryNeedPageEvent, MediaGalleryClosedEvent, MediaGalleryAppendPayload, MediaGalleryRemovePayload } from "./types"

export interface RNAttachmentKit {
  init(licenseKey: string, options?: InitOptions): Promise<boolean>
  /** 기본 언어 / 테마 색 / 화면 모드를 바꿈 (init 이후 언제든) */
  setDefaults(options: DefaultOptions): void
  /** 현재 기본값 */
  getDefaults(): { languageCode: string; themeColor: string; appearance: Appearance }
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateSourceRect(rect: import("./types").SourceRect): Promise<void>
  /** 지도 뷰어. 닫히면 resolve */
  openMapViewer(options: import("./types").MapViewerOptions): Promise<void>
  /** 지도 뷰어가 열린 동안 말풍선 위치가 바뀌었을 때 (닫힐 때 돌아갈 자리) */
  updateMapViewerSourceRect(rect: import("./types").SourceRect | null): Promise<void>
  /** 위치 메시지 말풍선 지도 썸네일을 이 기기에서 그려 캐시 (같은 요청이면 캐시에서 바로) */
  renderLocationThumbnail(options: import("./types").LocationThumbnailOptions): Promise<import("./types").LocationThumbnailResult>
  /** renderLocationThumbnail 캐시 비우기 */
  clearLocationThumbnailCache(): Promise<void>
  /**
   * 좌표 → 주소 (기기 지오코더, 무료). 언어는 languageCode 그대로 (생략하면 setDefaults 의 languageCode).
   * 결과("결과 없음" 포함)는 디스크에 캐시. 오류는 ReverseGeocodeErrorCode 로 reject (캐시 안 함)
   */
  reverseGeocode(options: import("./types").ReverseGeocodeOptions): Promise<import("./types").ReverseGeocodeResult>
  /** reverseGeocode 캐시 비우기 */
  clearReverseGeocodeCache(): Promise<void>
  closeGallery(): Promise<boolean>
  /**
   * processingId: 어느 보내기인지 (onProcessingStart 의 값). 생략하면 가장 최근 보내기
   *
   * 보내는 중인 동영상 변환 취소 (HUD 없이 말풍선에서 취소할 때). index 생략 = 남은 동영상 전부.
   * 취소된 동영상은 onImageProcessed·결과에 { error: "CANCELLED", cancelled: true } 로 오고 나머지는 계속 처리됩니다.
   * 진행 중인 처리가 없으면 false
   */
  cancelVideoProcessing(index?: number, processingId?: string): Promise<boolean>
  /**
   * AI 기능 on/off · 포인트 · 무료 횟수 · 1회 차감 포인트 (넘긴 값만 바뀜). 앱 시작 때 한 번, 잔액이 바뀔 때마다(충전·서버 동기화) 다시 호출.
   * AI 화면이 열려 있으면 바로 반영됩니다.
   */
  setAIConfig(config: AIConfig): Promise<void>
  /** AI 를 한 번 쓸 때마다 (무료 횟수 사용 또는 포인트 차감) — 앱이 서버에 반영. 해제 함수를 돌려줌 */
  addAIUsageListener(listener: (event: AIUsageEvent) => void): () => void
  /** 포인트가 모자라 사용자가 '충전하기'를 눌렀을 때 — 앱이 충전 화면으로 안내 (필요하면 closeGallery() 로 시트도 닫기). 해제 함수를 돌려줌 */
  addAIChargeRequiredListener(listener: (event: AIChargeRequiredEvent) => void): () => void
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
  getDefaultAnimationConfig(): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }>
  injectImageCache(urlString: string, localPath: string): Promise<boolean>
  /** 네이티브 미디어 갤러리(사진 모아보기)를 지원하는 네이티브 빌드인지 (옛 빌드면 false → 앱 RN 화면으로 폴백) */
  isMediaGallerySupported(): boolean
  /** 네이티브 미디어 갤러리 열기. 화면이 뜨면 resolve (닫힘은 onClosed) */
  openMediaGallery(options: MediaGalleryOptions): Promise<{ galleryId: string }>
  closeMediaGallery(galleryId: string): Promise<void>
  /** (B) JS 공급: onNeedPage 에 대한 응답 */
  appendGalleryItems(payload: MediaGalleryAppendPayload): Promise<void>
  /** 앱이 다른 경로로 지운 묶음을 갤러리·뷰어에서 제거 */
  removeGalleryItems(payload: MediaGalleryRemovePayload): Promise<void>
}

const AttachmentKit: RNAttachmentKit = {
  init: async (licenseKey: string, options?: InitOptions): Promise<boolean> => {
    if (options?.themeColor) {
      _defaultThemeColor = options.themeColor;
    }
    if (options?.languageCode) {
      _defaultLanguageCode = normalizeLanguageCode(options.languageCode);
      _rawLanguageCode = options.languageCode;
    }
    if (options?.appearance) {
      _defaultAppearance = normalizeAppearance(options.appearance);
    }
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.init(licenseKey)
  },

  setDefaults: (options: DefaultOptions): void => {
    if (options?.themeColor) _defaultThemeColor = options.themeColor
    if (options?.languageCode) {
      _defaultLanguageCode = normalizeLanguageCode(options.languageCode)
      _rawLanguageCode = options.languageCode
    }
    if (options?.appearance) _defaultAppearance = normalizeAppearance(options.appearance)
  },

  getDefaults: () => ({ languageCode: _defaultLanguageCode, themeColor: _defaultThemeColor, appearance: _defaultAppearance }),

  openGallery: async (options: GalleryOptions = {}): Promise<ImageResult[]> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    // 이미 열려 있으면 네이티브를 건드리지 않고 바로 reject (앞 호출의 Promise 를 지키기 위해)
    if (_galleryOpen) {
      throw alreadyOpenError("Gallery")
    }
    _galleryOpen = true
    const myToken = ++_galleryOpenToken
    // 갤러리 화면이 닫히고 처리가 시작되면(onProcessingStart) 바로 잠금을 풂 — 동영상을 변환하는 동안에도
    // 다시 열어 보낼 수 있게. Promise 는 지금처럼 처리가 다 끝나야 resolve
    let myProcessingId: string | null = null
    const subscriptionOpenLock = eventEmitter.addListener("onProcessingStart", (e: any) => {
      if (myProcessingId) return
      myProcessingId = typeof e?.processingId === "string" ? e.processingId : ""
      if (_galleryOpenToken === myToken) _galleryOpen = false
    })
    /** 이 호출의 이벤트인지 — processingId 가 붙은 이벤트는 내 처리의 것만, 안 붙은(옛 네이티브·사진 1장 편집) 이벤트는 처리 ID 를 모를 때만 */
    const isMine = (e: any) => {
      const id = e?.processingId
      if (typeof id !== "string" || id === "") return !myProcessingId
      return myProcessingId === id
    }
    const mine = <T,>(fn?: (e: T) => void) => fn ? (e: T) => { if (isMine(e)) fn(e) } : undefined

    // 콜백 이벤트 임시 리스너 등록
    let subscriptionSelChange: any = null
    let subscriptionImgProcessed: any = null

    if (options.onSelectionChange) {
      subscriptionSelChange = eventEmitter.addListener("onSelectionChange", options.onSelectionChange)
    }
    if (options.onImageProcessed) {
      if (options.asyncProcessing) {
        // async 모드: 이전 호출이 남겨 둔 구독을 먼저 제거해서 리스너가 쌓이지 않게 함
        if (_asyncImgProcessedSub) {
          try { _asyncImgProcessedSub.remove() } catch (e) { /* noop */ }
          _asyncImgProcessedSub = null
        }
        subscriptionImgProcessed = eventEmitter.addListener("onImageProcessed", mine(options.onImageProcessed)!)
        _asyncImgProcessedSub = subscriptionImgProcessed
      } else {
        subscriptionImgProcessed = eventEmitter.addListener("onImageProcessed", mine(options.onImageProcessed)!)
      }
    }
    let subscriptionLocation: any = null
    if (options.onLocationSelected) {
      subscriptionLocation = eventEmitter.addListener("onLocationSelected", options.onLocationSelected)
    }
    // 동영상 변환 진행률 (video.onProgress)
    let subscriptionVideoProgress: any = null
    if (options.video?.onProgress) {
      subscriptionVideoProgress = eventEmitter.addListener("onVideoProgress", mine(options.video.onProgress)!)
    }
    // 처리 시작 (보낸 직후 한 번, 결과보다 먼저)
    let subscriptionProcessingStart: any = null
    if (options.onProcessingStart) {
      // 내 처리 시작만 (앞 보내기의 시작 이벤트는 이 호출 전에 이미 지나감)
      const onStart = options.onProcessingStart
      let started = false
      subscriptionProcessingStart = eventEmitter.addListener("onProcessingStart", (e: any) => {
        if (started) return
        started = true
        onStart(e)
      })
    }
    let subscriptionFiles: any = null
    if (options.onFilesSelected) {
      const onFiles = options.onFilesSelected
      // failed: 복사에 실패한 파일 목록 [{ name, error }] (없으면 undefined)
      subscriptionFiles = eventEmitter.addListener("onFilesSelected", (e: any) => onFiles(e?.files ?? [], e?.failed ?? undefined))
    }

    try {
      // 이벤트 콜백은 네이티브로 전달하지 않음
      const { onSelectionChange, onImageProcessed, onLocationSelected, onFilesSelected, onProcessingStart, video, ...restOptions } = options
      const nativeOptions: any = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        appearance: _defaultAppearance,
        ...restOptions,
      }
      if (video) {
        // onProgress 콜백은 네이티브로 넘기지 않음
        const { onProgress, ...videoRest } = video
        nativeOptions.video = videoRest
      }
      nativeOptions.languageCode = normalizeLanguageCode(nativeOptions.languageCode)
      nativeOptions.appearance = normalizeAppearance(nativeOptions.appearance)
      const result = await RNAttachmentKitModule.openGallery(nativeOptions)
      return result
    } finally {
      // 처리 시작 때 이미 풀었고 그 뒤 새 호출이 잡았을 수 있음 → 내 잠금일 때만
      if (_galleryOpenToken === myToken) _galleryOpen = false
      subscriptionOpenLock.remove()
      // 갤러리가 닫히면 onSelectionChange 리스너 제거
      if (subscriptionSelChange) {
        subscriptionSelChange.remove()
      }
      // 위치 이벤트는 openGallery 가 끝나기 전에 오므로 여기서 바로 제거
      if (subscriptionLocation) {
        subscriptionLocation.remove()
      }
      if (subscriptionFiles) {
        subscriptionFiles.remove()
      }
      if (subscriptionVideoProgress) {
        subscriptionVideoProgress.remove()
      }
      if (subscriptionProcessingStart) {
        subscriptionProcessingStart.remove()
      }
      // asyncProcessing 모드가 아닐 때만 onImageProcessed 리스너 제거 (async 모드에선 백그라운드 처리를 위해 유지해야 함)
      // 호출부에서 수동으로 제거하거나, 최종 완료 시 정리하는 구조가 필요할 수 있음
      if (!options.asyncProcessing && subscriptionImgProcessed) {
        subscriptionImgProcessed.remove()
      }
    }
  },

  openEditor: async (options: EditorOptions): Promise<ImageResult> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    // Android 는 editImagePromise 를 하나만 보관해서 중복 호출 시 앞 Promise 가 끝나지 않음 → JS 에서 막음
    if (_editorOpen) {
      throw alreadyOpenError("Editor")
    }
    _editorOpen = true
    const mergedOptions = {
      themeColor: _defaultThemeColor,
      languageCode: _defaultLanguageCode,
      appearance: _defaultAppearance,
      ...options,
    }
    mergedOptions.languageCode = normalizeLanguageCode(mergedOptions.languageCode)
    mergedOptions.appearance = normalizeAppearance(mergedOptions.appearance)
    try {
      return await RNAttachmentKitModule.openEditor(mergedOptions)
    } finally {
      _editorOpen = false
    }
  },

  openViewer: async (options: ViewerOptions): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }

    let subscriptionPageSelected: any = null
    if (options.onPageSelected) {
      subscriptionPageSelected = eventEmitter.addListener("onPageSelected", (event: any) => {
        if (options.onPageSelected && event && typeof event.index === 'number') {
          options.onPageSelected(event.index)
        }
      })
    }

    let subscriptionViewerOpened: any = null
    // iOS 네이티브 쪽에는 "onViewerOpened" 이벤트가 구현되어 있지 않습니다(Android 전용 —
    // 오버레이 뷰어의 열기 애니메이션 완료 시점을 알려주는 이벤트). iOS에서 무조건 구독을
    // 시도하면 RCTEventEmitter가 "onViewerOpened is not a supported event type" 경고를 던지므로,
    // Android에서만 등록합니다.
    if (options.onViewerOpened && Platform.OS === "android") {
      subscriptionViewerOpened = eventEmitter.addListener("onViewerOpened", () => {
        try {
          if (options.onViewerOpened) {
            options.onViewerOpened()
          }
        } catch (e) {
          console.error("[RNAttachmentKit] options.onViewerOpened() threw:", e)
        }
        if (subscriptionViewerOpened) {
          subscriptionViewerOpened.remove()
        }
      })
    }

    let subscriptionViewerWillClose: any = null
    let deviceSubscriptionViewerWillClose: any = null

    let subscriptionImageDeleted: any = null
    if (options.onImageDeleted) {
      subscriptionImageDeleted = eventEmitter.addListener("onImageDeleted", (event: any) => {
        if (options.onImageDeleted && event && typeof event.index === 'number') {
          // patch405: deleteOptions 중 사용자가 고른 항목의 key (선택지를 안 넘겼으면 undefined)
          options.onImageDeleted({
            index: event.index,
            url: event.url,
            option: typeof event.option === 'string' && event.option.length > 0 ? event.option : undefined,
          })
        }
      })
    }

    // 네이티브 "onViewerWillClose"(iOS sendEvent / Android RCTDeviceEventEmitter) 는 앱이 콜백을 넘기지 않아도
    // 항상 구독합니다 — 이 이벤트가 와야 onPageSelected / onImageDeleted 구독을 정리할 수 있기 때문입니다
    // (예전엔 options.onViewerWillClose 가 없으면 구독을 안 해서 뷰어를 열 때마다 리스너가 누수됐음).
    const closeHandler = () => {
      if (options.onViewerWillClose) {
        options.onViewerWillClose()
      }
      if (subscriptionPageSelected) {
        subscriptionPageSelected.remove()
      }
      if (subscriptionViewerOpened) {
        subscriptionViewerOpened.remove()
      }
      if (subscriptionViewerWillClose) {
        subscriptionViewerWillClose.remove()
      }
      if (deviceSubscriptionViewerWillClose) {
        deviceSubscriptionViewerWillClose.remove()
      }
      if (subscriptionImageDeleted) {
        subscriptionImageDeleted.remove()
      }
    };

    subscriptionViewerWillClose = eventEmitter.addListener("onViewerWillClose", closeHandler);

    if (Platform.OS === "android") {
      deviceSubscriptionViewerWillClose = DeviceEventEmitter.addListener("onViewerWillClose", closeHandler);
    }

    try {
      const { onPageSelected, onViewerWillClose, onViewerOpened, onImageDeleted, ...restOptions } = options
      const mergedOptions = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        appearance: _defaultAppearance,
        ...restOptions,
      }
      mergedOptions.languageCode = normalizeLanguageCode(mergedOptions.languageCode)
      mergedOptions.appearance = normalizeAppearance(mergedOptions.appearance)
      return await RNAttachmentKitModule.openViewer(mergedOptions)
    } catch (e) {
      // 뷰어가 아예 안 떴으면(reject) onViewerWillClose 가 오지 않으므로 여기서 구독 정리 (앱 콜백은 호출 안 함)
      for (const sub of [subscriptionPageSelected, subscriptionViewerOpened, subscriptionImageDeleted, subscriptionViewerWillClose, deviceSubscriptionViewerWillClose]) {
        try { sub?.remove() } catch (err) { /* noop */ }
      }
      throw e
    }
    // 정상적으로 열렸으면 리스너는 onViewerWillClose 콜백 안에서 제거됨
  },

  updateSourceRect: async (rect: import("./types").SourceRect): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.updateSourceRect(rect)
  },

  openMapViewer: async (options: import("./types").MapViewerOptions): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    const mergedOptions: Record<string, any> = {
      themeColor: _defaultThemeColor,
      languageCode: _defaultLanguageCode,
      appearance: _defaultAppearance,
      ...options,
    }
    // 주소를 안 넘기면 네이티브가 채움 — reverseGeocode 와 같은 캐시를 쓰도록 같은 언어(넘긴 그대로)
    mergedOptions.addressLanguageCode = options.languageCode || _rawLanguageCode || _defaultLanguageCode
    mergedOptions.languageCode = normalizeLanguageCode(mergedOptions.languageCode)
    mergedOptions.appearance = normalizeAppearance(mergedOptions.appearance)
    // 함수는 네이티브로 못 넘김 — 닫기 시작은 이벤트로 받음 (Android 는 RCTDeviceEventEmitter 로도 올 수 있어 둘 다 듣고 한 번만)
    const onWillClose = options.onViewerWillClose
    delete mergedOptions.onViewerWillClose
    let willCloseSent = false
    const willCloseHandler = (e: any) => {
      if (willCloseSent) return
      willCloseSent = true
      onWillClose?.({ durationMs: typeof e?.durationMs === 'number' ? e.durationMs : 0 })
    }
    const subs: any[] = [eventEmitter.addListener("onMapViewerWillClose", willCloseHandler)]
    if (Platform.OS === "android") subs.push(DeviceEventEmitter.addListener("onMapViewerWillClose", willCloseHandler))
    try {
      await RNAttachmentKitModule.openMapViewer(mergedOptions)
    } finally {
      subs.forEach(s => s.remove())
    }
  },

  updateMapViewerSourceRect: async (rect: import("./types").SourceRect | null): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.updateMapViewerSourceRect(rect ?? {})
  },

  renderLocationThumbnail: async (options: import("./types").LocationThumbnailOptions): Promise<import("./types").LocationThumbnailResult> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    const mergedOptions = {
      themeColor: _defaultThemeColor,
      appearance: _defaultAppearance,
      ...options,
    }
    mergedOptions.appearance = normalizeAppearance(mergedOptions.appearance)
    // 내 위치는 둘 다 있을 때만
    if (typeof mergedOptions.myLatitude !== "number" || typeof mergedOptions.myLongitude !== "number") {
      delete mergedOptions.myLatitude
      delete mergedOptions.myLongitude
    }
    return RNAttachmentKitModule.renderLocationThumbnail(mergedOptions)
  },

  clearLocationThumbnailCache: async (): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.clearLocationThumbnailCache()
  },

  reverseGeocode: async (options: import("./types").ReverseGeocodeOptions): Promise<import("./types").ReverseGeocodeResult> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    const languageCode = options.languageCode || _rawLanguageCode || _defaultLanguageCode
    const r = await RNAttachmentKitModule.reverseGeocode({ latitude: options.latitude, longitude: options.longitude, languageCode })
    return { address: r?.address ?? null, shortAddress: r?.shortAddress ?? null, cached: !!r?.cached }
  },

  clearReverseGeocodeCache: async (): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.clearReverseGeocodeCache()
  },

  closeGallery: async (): Promise<boolean> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }

    return RNAttachmentKitModule.closeGallery()
  },

  cancelVideoProcessing: async (index?: number, processingId?: string): Promise<boolean> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    if (typeof RNAttachmentKitModule.cancelVideoProcessing !== "function") return false   // 옛 네이티브 빌드
    return RNAttachmentKitModule.cancelVideoProcessing(typeof index === "number" && index >= 0 ? index : -1, processingId ?? "")
  },

  setAIConfig: async (config: AIConfig): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    if (typeof RNAttachmentKitModule.setAIConfig !== "function") return   // 옛 네이티브 빌드
    // undefined 는 "바꾸지 않음" 이므로 빼고 보냄 (null 은 "비움")
    const payload: Record<string, unknown> = {}
    Object.entries(config ?? {}).forEach(([k, v]) => { if (v !== undefined) payload[k] = v })
    return RNAttachmentKitModule.setAIConfig(payload)
  },

  addAIUsageListener: (listener: (event: AIUsageEvent) => void) => {
    const subscription = eventEmitter.addListener("onAIUsage", listener as any)
    return () => subscription.remove()
  },

  addAIChargeRequiredListener: (listener: (event: AIChargeRequiredEvent) => void) => {
    const subscription = eventEmitter.addListener("onAIChargeRequired", listener as any)
    return () => subscription.remove()
  },

  addSelectionChangeListener: (listener: (event: SelectionChangeEvent) => void) => {
    const subscription = eventEmitter.addListener("onSelectionChange", listener)

    // Return cleanup function
    return () => {
      subscription.remove()
    }
  },

  getDefaultAnimationConfig: async (): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.getDefaultAnimationConfig()
  },

  injectImageCache: async (urlString: string, localPath: string): Promise<boolean> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    if (RNAttachmentKitModule.injectImageCache) {
      return RNAttachmentKitModule.injectImageCache(urlString, localPath)
    }
    return false;
  },

  isMediaGallerySupported: (): boolean => {
    return !!RNAttachmentKitModule && typeof RNAttachmentKitModule.openMediaGallery === "function"
  },

  openMediaGallery: async (options: MediaGalleryOptions): Promise<{ galleryId: string }> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    if (typeof RNAttachmentKitModule.openMediaGallery !== "function") {
      throw new Error("[RNAttachmentKit] openMediaGallery is not available in this native build")
    }
    const { onItemDeleted, onNeedPage, onClosed, onGridSizeChanged, ...rest } = options
    // 이벤트를 열기 전에 구독해야 하므로 galleryId 는 JS 에서 정함
    const galleryId = rest.galleryId || `mg_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
    const subs: { remove: () => void }[] = []
    const removeAll = () => {
      while (subs.length) {
        try { subs.pop()?.remove() } catch (e) { /* noop */ }
      }
    }
    if (onItemDeleted) {
      subs.push(eventEmitter.addListener("onGalleryItemDeleted", (e: any) => {
        if (e && e.galleryId === galleryId) onItemDeleted(e)
      }))
    }
    if (onNeedPage) {
      subs.push(eventEmitter.addListener("onGalleryNeedPage", (e: any) => {
        if (e && e.galleryId === galleryId) onNeedPage({ galleryId, cursor: e.cursor ?? null })
      }))
    }
    if (onGridSizeChanged) {
      subs.push(eventEmitter.addListener("onGalleryGridSizeChanged", (e: any) => {
        if (e && e.galleryId === galleryId) onGridSizeChanged({ galleryId, gridSize: e.gridSize })
      }))
    }
    subs.push(eventEmitter.addListener("onGalleryClosed", (e: any) => {
      if (!e || e.galleryId !== galleryId) return
      removeAll()
      try {
        onClosed?.({ galleryId })
      } catch (err) {
        console.error("[RNAttachmentKit] options.onClosed() threw:", err)
      }
    }))
    const nativeOptions: Record<string, any> = {
      languageCode: _defaultLanguageCode,
      ...rest,
      galleryId,
    }
    nativeOptions.languageCode = normalizeLanguageCode(nativeOptions.languageCode)
    // 화면 모드: theme.isDark 를 직접 넘기지 않았으면 appearance(옵션 > 기본값)로 정함 ("system" 이면 기기 설정)
    const appearance = normalizeAppearance(rest.appearance ?? _defaultAppearance)
    delete nativeOptions.appearance
    if (appearance !== "system" && (rest.theme == null || rest.theme.isDark == null)) {
      nativeOptions.theme = { ...(rest.theme || {}), isDark: appearance === "dark" }
    }
    nativeOptions.viewer = { themeColor: _defaultThemeColor, appearance, ...(rest.viewer || {}) }
    try {
      const result = await RNAttachmentKitModule.openMediaGallery(nativeOptions)
      return { galleryId: (result && result.galleryId) || galleryId }
    } catch (e) {
      removeAll()
      throw e
    }
  },

  closeMediaGallery: async (galleryId: string): Promise<void> => {
    if (!RNAttachmentKitModule || typeof RNAttachmentKitModule.closeMediaGallery !== "function") return
    return RNAttachmentKitModule.closeMediaGallery(galleryId)
  },

  appendGalleryItems: async (payload: MediaGalleryAppendPayload): Promise<void> => {
    if (!RNAttachmentKitModule || typeof RNAttachmentKitModule.appendGalleryItems !== "function") return
    return RNAttachmentKitModule.appendGalleryItems(payload)
  },

  removeGalleryItems: async (payload: MediaGalleryRemovePayload): Promise<void> => {
    if (!RNAttachmentKitModule || typeof RNAttachmentKitModule.removeGalleryItems !== "function") return
    return RNAttachmentKitModule.removeGalleryItems(payload)
  },
}

// Export info about which architecture is being used
export const isUsingTurboModule = !!NativeAttachmentKit
export const isUsingLegacyModule = !!LegacyModule && !NativeAttachmentKit

export default AttachmentKit
