# React Native Attachment Kit 🚀

A fully native attachment toolkit for React Native chat apps: a Telegram-style photo picker with an attach menu (Gallery / Location / File), an image editor, a sticky image viewer, a "all photos" media gallery, and everything a **location message** needs — map thumbnails, reverse geocoding and a full-screen map viewer.

---

## ✨ Features

- **Pure native UI** (Swift / Kotlin) — smooth on both platforms, New Architecture (Turbo Modules) and old architecture supported.
- **Photo picker** — bottom-sheet gallery, single or multi selection, albums, camera cell, optional editor step, profile (1:1) crop mode.
- **Attach menu** — Gallery / **Location** / **File** tabs under the gallery (Telegram style).
  - Location: map with a center pin, "send my current location", place search, "Share my location" switch, map snapshot image.
  - File: system file picker, files copied into the app's temp folder.
- **Image editor** — crop, rotate, filters, drawing, mosaic, text, caption.
- **Image viewer** — paging, pinch-to-zoom, thumbnails, save / share / delete actions, and a **sticky** open/close animation from the tapped thumbnail.
- **Location messages**
  - `renderLocationThumbnail` — draws a chat-bubble map thumbnail on the receiving device from coordinates only (cached).
  - `reverseGeocode` — coordinates → address in the app's language with the device geocoder (free, cached, throttle-safe).
  - `openMapViewer` — full-screen map with the sender's marker, distance · address card and Directions; the bubble image grows into the map and shrinks back on close.
- **Media gallery** — native grid for thousands of photos (3×3 / 4×4 / 5×5), date scroller, opens the viewer from a cell.
- **Theming** — theme color, light / dark / system appearance, 59 UI languages.

---

## 🎥 Demo

### Android

| Editor | Mosaic | Multi-Select |
|:---:|:---:|:---:|
| ![Android Editor](docs/aos_edit.gif) | ![Android Mosaic](docs/aos_mozaic.gif) | ![Android Multi](docs/aos_multi.gif) |

### iOS

| Editor | Mosaic | Multi-Select |
|:---:|:---:|:---:|
| ![iOS Editor](docs/ios_edit.gif) | ![iOS Mosaic](docs/ios_mozaic.gif) | ![iOS Multi](docs/ios_multi.gif) |

---

## 📋 Requirements

| | |
|---|---|
| iOS | 15.1+ (Apple Maps / MapKit — no API key) |
| Android | minSdk 24, compileSdk 34. Google Maps — **the app supplies its own key** (see below) |
| React Native | New Architecture (Turbo Modules) or old architecture |

---

## 📦 Installation

```bash
yarn add react-native-attachment-kit
# or
npm install react-native-attachment-kit

cd ios && pod install
```

Rebuild the app after installing or updating (the module ships compiled native code — a Metro reload is not enough).

### iOS — `Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to select images.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need access to save photos to your library.</string>
<!-- Attach menu → Location ("send my current location", my-location dot) -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to share it in a chat.</string>
```

### Android — Google Maps key

The Location tab, the map viewer and `renderLocationThumbnail` use Google Maps. The library ships **no key**; add your own to the app's `AndroidManifest.xml`:

```xml
<application>
  <meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_KEY"/>
</application>
```

Enable on the key: **Maps SDK for Android**, and **Places API (New)** for place search in the Location tab (Autocomplete (New) + Place Details Essentials only; on failure it falls back to the device `Geocoder`). Addresses shown while dragging the map and `reverseGeocode` use only the free device `Geocoder`.

### Android — permissions merged from the library

`INTERNET`, `ACCESS_NETWORK_STATE`, `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` (Android 9 and below, viewer "save"), `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`. Remove any you don't use with `tools:node="remove"`. Runtime prompts are shown by the module when needed. Dependencies `play-services-maps:19.0.0` and `play-services-location:21.3.0` come with the library.

---

## 🛠 Quick start

```ts
import AttachmentKit from 'react-native-attachment-kit'

// Once at app start
await AttachmentKit.init('YOUR_LICENSE_KEY', {   // '' = evaluation (editor watermark)
  languageCode: 'ko',      // any app language code; see Localization
  themeColor: '#10b981',
  appearance: 'system',    // 'system' | 'light' | 'dark'
})

// Pick photos
const images = await AttachmentKit.openGallery({ maxSelection: 10, enableEditor: true })
```

### Global defaults

`init` options become defaults for every screen. Change them any time (e.g. when the user changes the app theme or language) — only the values you pass change:

```ts
AttachmentKit.setDefaults({ appearance: 'dark', languageCode: 'en' })
AttachmentKit.getDefaults()   // { languageCode, themeColor, appearance }
```

Every `open*` / `render*` call also accepts `themeColor`, `languageCode` and `appearance` to override per call.

### Localization

The UI is translated into 59 languages (ISO 639-1):
`af ar be bg bn ca cs cy da de el en eo es et fa fi fr ga gl gu he hi hr ht hu id is it ja ka kn ko lt lv mk mr ms mt nl no pl pt ro ru sk sl sq sv sw ta te th tl tr uk ur vi zh`

- Region/script variants are normalized for the UI (`"pt-BR"` → `pt`, `"zh-Hans"` → `zh`, `"iw"` → `he`, `"nb"` → `no`, `"fil"` → `tl`); unsupported codes fall back to English. `zh` is Simplified Chinese.
- Addresses (`reverseGeocode`, map viewer) use the code **as given** (e.g. `'zh-Hant'`), since geocoders support more locales than the UI.
- `normalizeLanguageCode()` and `SUPPORTED_LANGUAGE_CODES` are exported.

---

## 📖 API reference

### Photo picker

#### `openGallery(options?: GalleryOptions): Promise<ImageResult[]>`

Opens the gallery bottom sheet. Resolves with the picked images (`[]` when the user sent a location or files from the attach menu, or closed it). Calling it while a gallery is open rejects with `E_ALREADY_OPEN`.

| Option | Type | Default | Description |
|---|---|---|---|
| `maxSelection` | `number` | `1` | Maximum number of photos. |
| `selectionMode` | `'single' \| 'multi'` | auto | `'single'`: tap returns immediately (with editor: tap → edit → send). `'multi'`: numbered checks + Done, even with `maxSelection: 1`. Omitted: single when `autoCloseOnSelect` or `maxSelection <= 1`. |
| `autoCloseOnSelect` | `boolean` | `false` | Single mode: close right after the tap. |
| `enableEditor` | `boolean` | `false` | Open the editor after selection. |
| `profileMode` | `boolean` | `false` | 1:1 (circle) crop for profile photos. |
| `maxWidth` / `maxHeight` | `number` | `1024` | Output images are scaled down to fit. |
| `outputFormat` | `'webp' \| 'jpg' \| 'png'` | `'webp'` | Output file format. (Not in the TS type yet — pass it with a cast.) |
| `themeColor` / `languageCode` / `appearance` | | defaults | Per-call overrides. |
| `doneButtonText` / `allItemsText` / `selectedItemsText` / `recentsAlbumText` | `string` | translated | Label overrides. |
| `asyncProcessing` | `boolean` | `false` | Event-driven sending: each item is delivered through `onImageProcessed` as soon as it is ready (the Promise still resolves with everything at the end), and videos show no progress HUD — draw progress in your own UI. See [Sending progress](#sending-progress-events). |
| `onSelectionChange` | `(e: SelectionChangeEvent) => void` | — | `{ selectedCount, maxSelection }` on every change. |
| `onProcessingStart` | `(e: ProcessingStartEvent) => void` | — | Once, right after Send, before any processing. |
| `onImageProcessed` | `(e) => void` | — | Per item `{ index, total, image }` as soon as it is ready. |
| `mediaType` | `'photo' \| 'all' \| 'video'` | `'photo'` | `'all'` mixes photos and videos. |
| `video` | `VideoOptions` | — | `maxDurationSec`, `maxFileSizeMB`, `qualities`, `defaultQuality`, `codec`, `onProgress`, `showProgressHUD`. |
| `openDuration` / `closeDuration` | `number` (ms) | native | Animation durations. |
| `showAttachMenu` … | | | Attach menu options — see [Attach menu](#attach-menu-location--file). |

`quality` is accepted for compatibility but currently ignored (output quality is fixed).

#### `ImageResult`

| Field | Type | Description |
|---|---|---|
| `originalUri` | `string` | Original asset (`ph://` or `file://`). |
| `originalFileUri?` | `string` | Original-resolution file (`file://`). |
| `originalWidth` / `originalHeight` | `number` | Original size. |
| `uri?` | `string` | Resized / edited output (`file://`). |
| `width?` / `height?` | `number` | Output size. |
| `type` | `string` | MIME type. |
| `caption?` | `string` | Caption typed in the editor. |
| `fileName?` / `fileExtension?` / `fileSize?` | | Output file info (bytes). |

#### `closeGallery(): Promise<boolean>`
Closes the picker from code. `true` if it was open.

#### `addSelectionChangeListener(listener): () => void`
Selection events outside `openGallery`; returns an unsubscribe function.

#### Sending progress (events)

A chat can show every sent item at once and fill it in as it finishes (photos are resized, videos are encoded), the same way for photos and videos:

1. **`onProcessingStart`** `{ total, items }`: once, right after Send. Each item has `index`, `mediaType` (`'image' | 'video'`), `originalUri`, and the expected output `width` / `height` (for the aspect ratio). Videos also have `duration` (seconds, after trim) and `thumbnailUri` / `thumbnailWidth` / `thumbnailHeight` (a poster jpg with crop and drawing applied). Create the placeholders here.
2. **`onVideoProgress`** `{ index, total, progress }`: video encoding 0…1 (at most every 1% / 0.1 s). Draw a progress ring on that placeholder.
3. **`onImageProcessed`** `{ index, total, image }`: the item is ready. Replace the placeholder with `image.uri`. A video the app cancelled comes as `{ error: 'CANCELLED', cancelled: true }`; a failed one has `error`.

```ts
const sub = emitter.addListener('onProcessingStart', ({ items }) => addPlaceholders(items))
const prog = emitter.addListener('onVideoProgress', ({ index, progress }) => setProgress(index, progress))
const done = emitter.addListener('onImageProcessed', ({ index, image }) => fillPlaceholder(index, image))
await AttachmentKit.openGallery({ mediaType: 'all', asyncProcessing: true, enableEditor: true })
// or pass onProcessingStart / onImageProcessed / video.onProgress as options
```

- **HUD:** `video.showProgressHUD` sets the full-screen progress HUD. The default is `true`, but `false` when `asyncProcessing: true`.
- **Cancel:** without the HUD, cancel from your UI with `AttachmentKit.cancelVideoProcessing(index?, processingId?)`. No `index` cancels all remaining videos; no `processingId` targets the latest send. The rest keep going, and the cancelled item is reported as above. It returns `false` when nothing is in progress.
- **Sending again while a video encodes:** the gallery can be opened again as soon as `onProcessingStart` arrives; you don't have to wait for the Promise, which still resolves with everything at the end. Every event carries `processingId`, so an app that listens with global listeners should use it to tell sends apart (`index` restarts at 0 for each send). Callbacks passed in the options are already filtered to their own send.

---

### Attach menu (Location / File)

```ts
const images = await AttachmentKit.openGallery({
  showAttachMenu: true,
  captureLocationImage: false,   // send coordinates only; receivers draw the thumbnail
  onLocationSelected: (location) => sendLocationMessage(location),
  onFilesSelected: (files, failed) => sendFiles(files),
})
// images is [] when a location or files were sent
```

| Option | Type | Default | Description |
|---|---|---|---|
| `showAttachMenu` | `boolean` | `false` | Show the Gallery / Location / File bar. |
| `onLocationSelected` | `(location: AttachLocationResult) => void` | — | Location sent from the Location tab. |
| `onFilesSelected` | `(files: AttachFileResult[], failed?: AttachFileFailure[]) => void` | — | Files sent from the File tab. `failed` lists files that could not be copied (omitted when all succeeded). |
| `captureLocationImage` | `boolean` | `true` | `false` = no map snapshot; the location is sent immediately (no `image*` fields, everything else is returned). |
| `attachMenuSinkIntoNav` | `number` (dp) | `12` | **Android** — how far the bar sinks into the navigation-bar area (`0` = right above it). |
| `attachMenuMinBottomMargin` | `number` (dp) | `8` | **Android** — minimum gap to the screen bottom. |

Both callbacks fire before `openGallery` resolves; their listeners are removed when it settles.

**Location tab**
- Map with a center pin: drag the map to choose a point (address from the device geocoder), tap a place, or "Send my current location" (accuracy shown).
- Search: iOS Apple Maps search; Android Places Autocomplete (New) with a session token + Place Details Essentials (location only) on pick, falling back to the device `Geocoder`.
- Full-screen map, map type (standard / hybrid), my-location button, light/dark map style.
- **"Share my location"** switch (off by default, remembered on the device): only affects the snapshot image — my-location dot drawn and the area widened so both points fit.

**`AttachLocationResult`**

| Field | Type | Description |
|---|---|---|
| `latitude`, `longitude` | `number` | Sent point. |
| `accuracy?` | `number` (m) | Only when the current location was sent. |
| `title?` | `string` | Place name when a place was picked. |
| `address?` | `string` | Address (no country name). |
| `isCurrentLocation` | `boolean` | `false` = dragged pin or place. |
| `markerType?` | `'current' \| 'pin' \| 'place'` | Marker icon — pass it to the thumbnail / map viewer so they draw the same marker. |
| `placeCategory?` | `string` | **iOS** — `MKPointOfInterestCategory` of a place (category icon). |
| `imageSpanMeters?` | `number` | Real distance covered by the image width — pass it as `spanMeters` to keep the same scale. Returned even with `captureLocationImage: false`. |
| `imageUri?`, `imagePath?`, `imageWidth?`, `imageHeight?` | | Map snapshot: portrait **480×1040 webp** (9:19.5), the point exactly centered, marker drawn. Omitted when `captureLocationImage: false` or the capture fails. |
| `includesMyLocation?` | `boolean` | Whether my-location was drawn into the snapshot ("Share my location"). |
| `currentLatitude?`, `currentLongitude?`, `currentAccuracy?` | `number` | The device's own location at send time (when known), independent of what was sent. |

**`AttachFileResult`** — `{ uri (file://), path, name, size (bytes), mimeType }`
**`AttachFileFailure`** — `{ name, error }`

**File tab** — iOS Files picker, Android system picker (`ACTION_OPEN_DOCUMENT`, multiple, any type). Files are **copied** to the app's temp folder; copy or upload them promptly (see [Caches & temp files](#-caches--temp-files)).

---

### Image editor

#### `openEditor(options: EditorOptions): Promise<ImageResult>`

| Option | Type | Description |
|---|---|---|
| `uri` | `string` | Image to edit (`originalUri` from a picker result). |
| `editedFileUri?` | `string` | A previous edit to continue from. |
| `maxWidth` / `maxHeight` | `number` | Output bounds. |
| `themeColor` / `appearance` | | Per-call overrides. |
| `openDuration` / `closeDuration` | `number` (ms) | Animation durations. |

Rejects with `E_ALREADY_OPEN` while an editor is open. Without a license key the editor output carries a watermark.

---

### Image viewer

#### `openViewer(options: ViewerOptions): Promise<void>`

```ts
const ref = useRef<View>(null)

ref.current?.measure((x, y, width, height, pageX, pageY) => {
  AttachmentKit.openViewer({
    images: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    initialIndex: 0,
    sourceRect: { x: pageX, y: pageY, width, height },   // sticky open/close
    sourceBorderRadius: 12,
    useOverlayViewer: true,                              // Android: recommended
    onPageSelected: async (index) => {
      const rect = await measureThumbnail(index)
      if (rect) AttachmentKit.updateSourceRect(rect)      // close back into the right thumbnail
    },
  })
})
```

**Basic**

| Option | Type | Default | Description |
|---|---|---|---|
| `images` | `string[]` | **required** | Image URIs (`https://`, `file://`, `ph://`). |
| `initialIndex` | `number` | `0` | First page. |
| `placeholderImages` | `string[]` | — | Low-res placeholders shown while the full image loads (same order). |
| `cacheFiles` | `(string \| null)[]` | — | Local cache paths per image: if the file exists it is shown without network, otherwise the downloaded bytes are saved there. |
| `title` | `string` | — | Toolbar title. |
| `themeColor` / `appearance` / `languageCode` | | defaults | Per-call overrides. |
| `animationType` / `closeAnimationType` | `'zoom' \| 'fade' \| 'slide'` | `zoom` with `sourceRect`, else `slide` | Open / close animation. |
| `openDuration` / `closeDuration` | `number` (ms) | native | Animation durations. |

**Sticky transition**

| Option | Type | Description |
|---|---|---|
| `sourceRect` | `SourceRect` | On-screen rect of the tapped thumbnail (`measure` page coordinates). |
| `sourceBorderRadius` | `number` | Thumbnail corner radius (animates to 0 and back). |
| `sourceBorderCorners` | `('topLeft' \| 'topRight' \| 'bottomLeft' \| 'bottomRight')[]` | Which corners are rounded (chat-bubble groups). `[]` = none. |
| `sourceBackgroundColor` | `string` | Background behind the thumbnail during the animation. |
| `hideSourceImage` | `boolean` | A native mask hides the source thumbnail while the viewer is open. |

**Actions**

| Option | Type | Description |
|---|---|---|
| `showActionButtons` | `boolean` (default `true`) | Save / share / delete buttons in the top bar. |
| `saveAllText` / `saveOneText` / `shareAllText` / `shareOneText` / `actionCancelText` | `string` | Action-sheet labels for groups. |
| `deleteConfirmTitle` / `deleteConfirmMessage` / `deleteConfirmGroupMessage` / `deleteButtonText` | `string` | Delete-confirm texts (translated by default). |
| `deleteOptions` | `{ key, label, destructive? }[]` | Several delete choices (e.g. "Delete for everyone" / "Delete for me"); the chosen `key` comes back as `option`. |
| `onImageDeleted` | `({ index, url, option? }) => void` | The user confirmed delete. The module does not delete anything — the app does. |

**Events**

| Option | Platform | Description |
|---|---|---|
| `onPageSelected(index)` | both | Page changed. |
| `onViewerWillClose()` | both | Close animation starts. |
| `onViewerOpened()` | Android | Open animation finished (safe moment for background scroll corrections). |

**Android viewer modes**

| Option | Description |
|---|---|
| (default) | Separate Activity — `AppState` briefly reports `background`. |
| `useDialogViewer: true` | DialogFragment — no `AppState` blip, but background RN layout changes may not render until it closes. |
| `useOverlayViewer: true` | ⭐ View on top of the host Activity's window — no `AppState` blip, background changes render in real time. Wins over `useDialogViewer`. |

#### `updateSourceRect(rect: SourceRect & { sourceBorderRadius?, sourceBorderCorners? }): Promise<void>`
Updates where the viewer closes to (e.g. after paging to another thumbnail or scrolling).

#### `injectImageCache(url: string, localPath: string): Promise<boolean>`
Seeds the viewer's image cache with a local file for a remote URL, so it opens instantly without network.

#### `SourceRect`
`{ x: number, y: number, width: number, height: number }` — screen / window coordinates in dp (pt).

---

### Location messages

Recommended flow for a chat app that sends **coordinates only** (`captureLocationImage: false`):

1. **Sender**: `openGallery({ showAttachMenu: true, captureLocationImage: false, onLocationSelected })` → send `latitude`, `longitude`, `title?`, `markerType`, `placeCategory?`, `imageSpanMeters`, and `currentLatitude/Longitude` only if `includesMyLocation`.
2. **Receiver bubble**: `renderLocationThumbnail(...)` → show `uri` in the bubble (e.g. 170×128, `resizeMode="cover"`); `reverseGeocode(...)` → show the address in the app's language.
3. **Tap**: `openMapViewer({ ..., sourceRect, sourceImageUri: thumb.uri })` → the bubble image grows into the map.

```tsx
const bubbleRef = useRef<View>(null)

// bubble
const thumb = await AttachmentKit.renderLocationThumbnail({
  latitude, longitude, markerType, placeCategory, spanMeters: imageSpanMeters,
  width: 170, aspect: 'device',          // screen-ratio image, shown cropped in a 4:3 bubble
  maxWidth: 512, maxHeight: 1152,        // sharp on 3× screens
})
const { address } = await AttachmentKit.reverseGeocode({ latitude, longitude })

// tap
bubbleRef.current?.measureInWindow((x, y, width, height) => {
  AttachmentKit.openMapViewer({
    latitude, longitude, title, markerType, placeCategory, spanMeters: imageSpanMeters,
    sourceRect: { x, y, width, height },
    sourceImageUri: thumb.uri,           // pass the uri as returned
    sourceCornerRadius: 16,
  })
})
```

#### `renderLocationThumbnail(options: LocationThumbnailOptions): Promise<LocationThumbnailResult>`

Draws a map thumbnail on this device from the location info alone, in this device's theme, and caches it on disk.

| Option | Type | Description |
|---|---|---|
| `latitude`, `longitude` | `number` | **Required.** |
| `width` | `number` (dp/pt) | **Required.** Output px = width × screen scale (capped by `maxWidth/maxHeight`). |
| `height` / `aspect` | `number` / `'square' \| 'portrait' \| 'device'` | Height directly, or from the width: `square` 1:1, `portrait` 9:19.5 (same as the sent snapshot), `device` this screen's ratio (the image then fills the screen exactly in the map viewer). |
| `maxWidth` / `maxHeight` | `number` (px) | Scale down to fit. Both omitted → 512 × 512; only one given → the other is not limited. |
| `markerType`, `placeCategory` | | Marker icon (as `AttachLocationResult`). Android has no per-category icons. |
| `spanMeters` | `number` | Distance covered by the width (`imageSpanMeters`). Default 400. |
| `myLatitude`, `myLongitude` | `number` | Only if the sender shared their location (`includesMyLocation`): draws the dot and widens the area. |
| `themeColor`, `appearance` | | Marker color, light/dark map (`system` = current app/device mode). |

Result: `{ uri: 'file://…webp', path, width, height (px), cached }`.

- Cached by coordinates, output size, theme, marker, span, color and my-location; identical requests in flight are merged. A theme change renders once more, then that is cached too.
- Errors: `E_INVALID_ARGS`, `E_THUMBNAIL_FAILED` (no tiles — e.g. offline — or a 10 s timeout). Failures are not cached.
- The renderer also stores the same map without the marker; the map viewer uses it so the marker keeps the right size while the bubble grows into the map.

#### `reverseGeocode(options: ReverseGeocodeOptions): Promise<ReverseGeocodeResult>`

Coordinates → address with the **device geocoder** (iOS `CLGeocoder`, Android `Geocoder`) — free, no key.

```ts
const { address, shortAddress, cached } = await AttachmentKit.reverseGeocode({
  latitude: 37.5665, longitude: 126.978,
  languageCode: 'ko',   // optional — defaults to the init/setDefaults languageCode, as given
})
```

- `address`: full address (Location-tab format, no country). `shortAddress`: street / neighbourhood + number. Both `null` when there is no address (e.g. open sea) — a **resolve**, not a reject.
- Disk cache, key `round(lat,5)|round(lng,5)|languageCode`; "no result" is cached too. 1000 entries max, trimmed to 800 least recently used. A hit resolves with `cached: true` in a few ms.
- Same-key requests are merged; the geocoder is called **one request at a time** (Apple allows ~50 per app per minute). 8 s timeout per call.
- Rejects (never cached): `E_INVALID_COORDINATE`, `E_GEOCODE_UNAVAILABLE` (Android device without a geocoder), `E_GEOCODE_THROTTLED` (retry later; on iOS new requests are rejected right away until the throttle resets), `E_GEOCODE_TIMEOUT`, `E_GEOCODE_NETWORK` (offline), `E_GEOCODE_FAILED`.
- Logs never contain coordinates or addresses.
- iOS data limits (Apple Maps): Korean addresses come without the district (`중구`), and Korea has only Korean/English data, so `ja`, `zh-Hans`, … return Korean there. Android (Google) includes the district.

#### `openMapViewer(options: MapViewerOptions): Promise<void>`

Full-screen map (Android Google Maps, iOS MapKit) with the sender's marker, a card (title, distance · address), map type / my-location buttons and an optional **Directions** button. Resolves when the viewer closes.

| Option | Type | Description |
|---|---|---|
| `latitude`, `longitude` | `number` | **Required.** |
| `title?`, `address?` | `string` | Without `address` it is filled with `reverseGeocode` (same cache and language). |
| `markerType?`, `placeCategory?` | | Same marker as the sender. |
| `spanMeters?` | `number` | Initial zoom = same scale as the bubble image (`imageSpanMeters`). The point is exactly at the screen center. |
| `showDirections?` | `boolean` (default `true`) | Android: chooser of installed map apps (`geo:`). iOS: Apple Maps / Google Maps, plus Kakao Map / Naver Map when `languageCode` is `ko`. |
| `sourceRect?` | `SourceRect` | Bubble rect (`measureInWindow` values). Sticky open/close; omitted → fade. |
| `sourceImageUri?` | `string` | Bubble image (`file://` or `https://`). May have a different aspect than `sourceRect` (screen-ratio image in a 4:3 bubble): it is always drawn center-cropped, so the first frame equals the bubble, then the cropped top/bottom unfold; closing crops back. Not loaded within ~1.5 s → opens without it. |
| `sourceCornerRadius?` | `number` (default 12) | Bubble corner radius. |
| `themeColor?`, `languageCode?`, `appearance?` | | Per-call overrides. |

#### `updateMapViewerSourceRect(rect: SourceRect | null): Promise<void>`
While the map viewer is open, updates where it closes to (e.g. the chat list scrolled). `null` → the original `sourceRect`.

#### `clearLocationThumbnailCache()` / `clearReverseGeocodeCache(): Promise<void>`
Delete the thumbnail / address caches (e.g. on logout).

---

### Media gallery ("all photos")

#### `openMediaGallery(options: MediaGalleryOptions): Promise<{ galleryId }>`

A native grid built for thousands of photos. It opens like the picker (same bottom sheet: 60% → drag up to expand, drag down to close), with a date quick-scroller. Tapping a photo opens the image viewer with the sticky zoom from that cell; the viewer pages through every loaded photo and closes back into the cell you were viewing. Resolves when the screen is shown.

- **Native data source (recommended)**: implement `MediaGalleryDataSource` in your app's native code and register it with `MediaGalleryRegistry.register("name", source)` (iOS Swift / Android Kotlin). Pass `dataSource: "name"` and `dataSourceParams`. Pages are loaded natively, no JS round trip. Built-in demo: `dataSource: "turboDemo", dataSourceParams: { count: 10000 }`.
- **JS data source**: pass `initialItems`, `hasMore`, `nextCursor`; answer `onNeedPage` with `appendGalleryItems({ galleryId, items, nextCursor, hasMore })`.
- `MediaGalleryItem`: `{ id, groupId?, timestamp?, thumbUri? (file:// only — no base64), imageUri, cacheFile?, isMine?, width?, height? }`.
- `title` (required), `gridSize: '3x3' | '4x4' | '5x5'` (default until the user picks one; the user's choice is saved on the device and wins), `spacing`, `theme`, `appearance`, `languageCode`, `emptyTitle`, `emptySubtitle`, `countFormat`.
- `viewer`: `{ themeColor, deleteOptionsForMine, deleteOptionsForOthers, titleFormat: 'date' | 'none', …openViewer text options }`.
- Events: `onItemDeleted({ galleryId, id, groupId, option })` (the module already removed that group from the screen — delete it in the app), `onNeedPage`, `onGridSizeChanged`, `onClosed`.
- Other: `closeMediaGallery(galleryId)`, `removeGalleryItems({ galleryId, groupIds })`, `isMediaGallerySupported()`.
- Android: the sheet is a view on top of the host Activity (no Activity / Dialog window); system back closes it.

---

### AI (generate & edit)

The gallery's ✦ button (AI image generation) and the editor's 6th tool **AI** (AI photo editing) use Google Gemini. They are **off until you call `setAIConfig({ enabled: true, ... })`**. In apps other than ZemTalk the AI screens are chat-only: generate shows an aspect-ratio bar and the chat input, edit shows the photo and the chat input, and the text is sent to the model as typed. The style/option menus, sample prompts, recommendation chips and recent works are ZemTalk-only.

```ts
await AttachmentKit.setAIConfig({
  enabled: true,
  endpoint: "https://api.example.com/ai/generate",   // your server: forwards the Gemini generateContent body with your key
  headers: { Authorization: `Bearer ${token}` },     // header X-AI-Model carries the model name
  points: 1200,          // current points
  freeCount: 27,         // subscribers: free uses left (e.g. 30 per month — your server decides); used before points
  costPerUse: 100,       // points per use (0 = free / unlimited)
  highQualityCost: 150,  // points per use with Quality "High (1K)" (default: costPerUse)
})

const offUsage = AttachmentKit.addAIUsageListener(e => {
  // { kind: "generate" | "edit", usedFreeCount, pointsDeducted, highQuality, points, freeCount }
  api.reportAIUsage(e)
})
const offCharge = AttachmentKit.addAIChargeRequiredListener(e => {
  // { kind, required, points, freeCount } — the AI screen has closed
  AttachmentKit.closeGallery(); navigation.navigate("PointShop")
})
```

- Only the values you pass change; call it again whenever the balance changes (after a top-up, after a server sync). An open AI screen updates at once.
- Order of use: free uses → points → when points are short the user sees "Not enough points · Top up" (Top up → `onAIChargeRequired`, AI screen closes).
- Only successful requests are charged (failures, cancel and safety blocks are free). The module lowers its own copy and sends `onAIUsage`; your server stays the source of truth.
- The AI screen title shows "N free left" or "points · cost per use".
- `apiKey` exists for testing only — never ship a Gemini key in the app.

#### Your backend (the `endpoint`)

The module never needs a Gemini key in the app. Point `endpoint` at **your own server**; it only has to pass the request through to Gemini with your key.

**Request the module sends**

```
POST {endpoint}
Content-Type: application/json
X-AI-Model: gemini-3.1-flash-image        ← model to call (image: gemini-3.1-flash-image / gemini-3.1-flash-lite-image, photo analysis: gemini-3.5-flash-lite)
…plus every header you passed in setAIConfig({ headers })   ← e.g. Authorization

{ …Gemini generateContent request body… }
```

**What your server does**

1. Check the user (your `headers`) and that `X-AI-Model` is a model you allow.
2. Forward the body unchanged to `https://generativelanguage.googleapis.com/v1beta/models/{X-AI-Model}:generateContent` with header `x-goog-api-key: <your key>`.
3. Return Gemini's status code and JSON body **as is**.

```js
// Minimal Express example
app.post('/ai/generate', auth, express.json({ limit: '20mb' }), async (req, res) => {
  const model = req.get('X-AI-Model');
  if (!ALLOWED_MODELS.includes(model)) return res.status(400).json({ code: 'MODEL_NOT_ALLOWED' });
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': process.env.GEMINI_API_KEY },
    body: JSON.stringify(req.body),
  });
  res.status(r.status).type('application/json').send(await r.text());
});
```

**Billing (optional, on your server)** — the module's `points` / `freeCount` are only a display copy. If you charge, do it on the server: reserve before calling Gemini, confirm only when the response contains an image, refund otherwise (failures and safety blocks should be free). Then send the new balance back with `setAIConfig` (e.g. in `addAIUsageListener`).

**Errors** — any status other than 200 is a failed attempt (nothing is deducted in the module). To show your own reason, answer in Gemini's error shape: `{ "error": { "message": "…" } }`. The "Not enough points · Top up" prompt comes from the module's own copy of `points` / `freeCount`, so keep it in sync with `setAIConfig`.

**Security** — keep the key only on the server, allow-list models, limit the body size, and rate-limit per user (photo analysis requests carry no image output and are easy to abuse if left unlimited).

---

### Misc

| API | Description |
|---|---|
| `getDefaultAnimationConfig()` | Native default durations (ms): `{ galleryOpen, galleryClose, editorOpen, editorClose, viewerOpen, viewerClose }`. |
| `isUsingTurboModule` / `isUsingLegacyModule` | Which architecture is in use. |
| `normalizeLanguageCode(code)` / `SUPPORTED_LANGUAGE_CODES` | UI language helpers. |
| `normalizeAppearance(value)` | `'light' \| 'dark'`, anything else → `'system'`. |

---

## ⚠️ Error codes

| Code | Where |
|---|---|
| `E_ALREADY_OPEN` | `openGallery` / `openEditor` while one is already open. |
| `E_INVALID_ARGS`, `E_THUMBNAIL_FAILED` | `renderLocationThumbnail`. |
| `E_INVALID_COORDINATE`, `E_GEOCODE_UNAVAILABLE`, `E_GEOCODE_THROTTLED`, `E_GEOCODE_TIMEOUT`, `E_GEOCODE_NETWORK`, `E_GEOCODE_FAILED` | `reverseGeocode` (type `ReverseGeocodeErrorCode`). |

---

## 🗂 Caches & temp files

| What | iOS | Android | Lifetime |
|---|---|---|---|
| Files from the File tab | `tmp/AttachmentKitFiles/<uuid>/<name>` | `cache/AttachmentKitFiles/<uuid>/<name>` | Deleted after 24 h (next gallery open); the OS may purge earlier — copy/upload promptly. |
| Location snapshots | `tmp/AttachmentKitLocation/` | `cache/AttachmentKitLocation/` | Deleted after 24 h. |
| Location thumbnails | `Library/Caches/RNAttachmentKit/LocationThumbs/` | `cache/RNAttachmentKitLocationThumbs/` | 300 max → 250, least recently used. `clearLocationThumbnailCache()`. |
| Reverse-geocode results | `Library/Caches/RNAttachmentKit/Geocode/` | `cache/RNAttachmentKitGeocode/` | 1000 max → 800, least recently used. `clearReverseGeocodeCache()`. |

---

## 📜 License & Contact

`react-native-attachment-kit` is released under the **MIT License**. Removing the editor watermark requires a license key passed to `init()`.

🛒 **License**: [https://license.rnturboimagepicker.usomnia.co.kr](https://license.rnturboimagepicker.usomnia.co.kr)
📧 **Contact**: [contact@usomnia.co.kr](mailto:contact@usomnia.co.kr)

See `CHANGELOG.md` for version history.
