# Changelog

## 1.0.2 — 2026-10-09

Android:
- Overlay image viewer (`useOverlayViewer`) open/close animations are 50ms shorter: open 250→200ms (photo zoom now follows `openDuration` instead of a fixed 250ms), close 200→150ms.

## 1.0.1 — 2026-10-09

New:
- `appearance: 'system' | 'light' | 'dark'` option — global default via `init(key, { appearance })`, per-call override on every `open*`. `'system'` (default) follows the device setting.
- `AttachmentKit.setDefaults({ languageCode, themeColor, appearance })` / `AttachmentKit.getDefaults()` — change global defaults any time after `init`.

Android fixes:
- Picker → editor no longer flashes the wrong theme when the app forces `appearance: 'light' | 'dark'` that differs from the device setting. The night mode is now set in `attachBaseContext` instead of `onCreate`, so AppCompat no longer draws the screen once and then recreates it. Same fix in `CropActivity`, `ProfileCropActivity`, `DrawingActivity`, `ImageViewerActivity`.
- Fixed crash `UninitializedPropertyAccessException: lateinit property viewPager` in `ImageEditorActivity.finish()` when the editor was recreated (theme recreate above, system dark-mode switch, or process restore). `finish()` now closes immediately if the screen was never set up, and the editor's photo list (`EditorDataHolder`) is cleared only when the editor really closes and only if it still holds that editor's list.
- Editor open/close/pull-to-dismiss background now uses the theme color `@color/editor_background` instead of hard-coded black. In light mode the editor used to fade in black and then flash to white when the photo pager appeared.
- Tapping a photo in the picker no longer blinks the grid cell before the zoom animation. The cell is now hidden right after the editor draws its first frame (the editor's overlay photo covers the cell at that moment), instead of when the picker launches the editor.
- Pull-to-dismiss in the editor now slides the selection badge away with the top bar (it used to stay floating on screen while the photo was dragged).
- Picker grid spacing reduced from 4dp to 1dp between cells (same as iOS).
- Guard against sending the same photo twice after editing (multi-select): the selection returned from the editor is mapped back to original URIs and de-duplicated, the editor keeps only original URIs in its selection, and `sendSelectedImagesNow()` de-duplicates after mapping to edited files.

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
