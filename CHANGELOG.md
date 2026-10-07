# Changelog

## 1.0.0 — 2026-10-02

Renamed from `react-native-turbo-image-picker` 2.0.8 (source 1.2.43 + the 2026-10-02 grid-menu and Android expand-position fixes) to `react-native-attachment-kit`. **JS API, options, event names and type names are unchanged** — apps only change the import path.

Renamed (externally visible):
- npm `react-native-attachment-kit`; default export `AttachmentKit` (interface `RNAttachmentKit`); linking error message
- Native module name `RNAttachmentKit`, codegen `RNAttachmentKitSpec` (`src/NativeAttachmentKit.ts`), Java package `com.rnattachmentkit`
- iOS: `RNAttachmentKit.xcframework` / Swift module `RNAttachmentKit`, bridge `@objc(RNAttachmentKit)`, resource bundle `RNAttachmentKitAssets`, podspecs `RNAttachmentKit.podspec` (dev) and `react-native-attachment-kit.podspec` (dist)
- Android: module `android/rnattachmentkit`, package `com.rnattachmentkit(.glide/.rn)`, `RNAttachmentKitModule` / `RNAttachmentKitPackage` / `NativeRNAttachmentKitSpec`, `AttachmentKitGlideModule`, AAR `rnattachmentkit-release.aar`

Changed so the package does not collide with the original when installed side by side (side-by-side use is still unsupported — see docs):
- FileProvider authority `${applicationId}.attachmentkit.fileprovider`, paths file `res/xml/attachment_kit_file_paths.xml`
- Grid-size storage keys: iOS `UserDefaults` `RNAttachmentKit.mediaGallery.gridColumns`, Android `SharedPreferences` `RNAttachmentKit.mediaGallery` (previously saved grid size is not migrated)
- iOS cache folder `Caches/RNAttachmentKit`, `NSError` domain `RNAttachmentKit`
- License notice text now says `react-native-attachment-kit`; license keys are unchanged and keep working

Unchanged on purpose: internal class/resource names (`TurboImageCache`, `TurboImagePickerConfig`, `turbo_*` strings, layouts/styles), i18n strings, the editor watermark text.
