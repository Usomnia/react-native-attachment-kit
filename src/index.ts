import { NativeModules, Platform, TurboModuleRegistry, NativeEventEmitter } from "react-native"
import type { ImageResult, GalleryOptions, EditorOptions, SelectionChangeEvent, ViewerOptions, MediaGalleryOptions, MediaGalleryAppendPayload, MediaGalleryRemovePayload } from "./types"

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
}

// Fallback to Legacy Native Module (Old Architecture)
const LegacyModule = NativeModules.RNAttachmentKit

// Use Turbo Module if available, otherwise use Legacy Module
const RNAttachmentKitModule = NativeAttachmentKit || LegacyModule

if (!RNAttachmentKitModule) {
  throw new Error(LINKING_ERROR)
}

// Create event emitter
const eventEmitter = new NativeEventEmitter(RNAttachmentKitModule)

export type { SelectionChangeEvent } from "./types"
export type { MediaGalleryItem, MediaGalleryOptions, MediaGalleryGridSize, MediaGalleryGridSizeChangedEvent, MediaGalleryTheme, MediaGalleryViewerOptions, MediaGalleryDeleteOption, MediaGalleryItemDeletedEvent, MediaGalleryNeedPageEvent, MediaGalleryClosedEvent, MediaGalleryAppendPayload, MediaGalleryRemovePayload } from "./types"

export interface RNAttachmentKit {
  init(licenseKey: string, options?: InitOptions): Promise<boolean>
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateSourceRect(rect: import("./types").SourceRect): Promise<void>
  closeGallery(): Promise<boolean>
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
    }
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.init(licenseKey)
  },

  openGallery: async (options: GalleryOptions = {}): Promise<ImageResult[]> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }

    // 콜백 이벤트 임시 리스너 등록
    let subscriptionSelChange: any = null
    let subscriptionImgProcessed: any = null
    
    if (options.onSelectionChange) {
      subscriptionSelChange = eventEmitter.addListener("onSelectionChange", options.onSelectionChange)
    }
    if (options.onImageProcessed) {
      subscriptionImgProcessed = eventEmitter.addListener("onImageProcessed", options.onImageProcessed)
    }

    try {
      // 이벤트 콜백은 네이티브로 전달하지 않음
      const { onSelectionChange, onImageProcessed, ...restOptions } = options
      const nativeOptions = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        ...restOptions,
      }
      nativeOptions.languageCode = normalizeLanguageCode(nativeOptions.languageCode)
      const result = await RNAttachmentKitModule.openGallery(nativeOptions)
      return result
    } finally {
      // 갤러리가 닫히면 onSelectionChange 리스너 제거
      if (subscriptionSelChange) {
        subscriptionSelChange.remove()
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
    const mergedOptions = {
      themeColor: _defaultThemeColor,
      languageCode: _defaultLanguageCode,
      ...options,
    }
    mergedOptions.languageCode = normalizeLanguageCode(mergedOptions.languageCode)
    return RNAttachmentKitModule.openEditor(mergedOptions)
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

    if (options.onViewerWillClose) {
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
        const { DeviceEventEmitter } = require("react-native");
        deviceSubscriptionViewerWillClose = DeviceEventEmitter.addListener("onViewerWillClose", closeHandler);
      }
    }

    try {
      const { onPageSelected, onViewerWillClose, onViewerOpened, onImageDeleted, ...restOptions } = options
      const mergedOptions = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        ...restOptions,
      }
      mergedOptions.languageCode = normalizeLanguageCode(mergedOptions.languageCode)
      return await RNAttachmentKitModule.openViewer(mergedOptions)
    } finally {
      // Listeners are now removed inside the onViewerWillClose callback
    }
  },

  updateSourceRect: async (rect: import("./types").SourceRect): Promise<void> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNAttachmentKitModule.updateSourceRect(rect)
  },

  closeGallery: async (): Promise<boolean> => {
    if (!RNAttachmentKitModule) {
      throw new Error(LINKING_ERROR)
    }

    return RNAttachmentKitModule.closeGallery()
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
    nativeOptions.viewer = { themeColor: _defaultThemeColor, ...(rest.viewer || {}) }
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
