package com.rnattachmentkit

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.*

@ReactModule(name = RNAttachmentKitModule.NAME)
class RNAttachmentKitModule(reactContext: ReactApplicationContext) :
    NativeRNAttachmentKitSpec(reactContext), ActivityEventListener {

    companion object {
        const val NAME = "RNAttachmentKit"
        private const val E_PICKER_CANCELLED = "E_PICKER_CANCELLED"
        private const val E_NO_ACTIVITY = "E_NO_ACTIVITY"
        private const val E_FAILED_TO_PICK = "E_FAILED_TO_PICK"
        private const val REQUEST_CODE_IMAGE_PICKER = 3001
        private const val REQUEST_CODE_IMAGE_EDITOR = 3002
    }

    private var pickImagesPromise: Promise? = null
    private var editImagePromise: Promise? = null
    private val moduleScope = CoroutineScope(Dispatchers.Main)
    private var maxWidth: Int = 1024
    private var maxHeight: Int = 1024
    private var outputFormat: String = "webp" // Default to webp
    // ─── 동영상 (openGallery mediaType / video 옵션) ───
    private var mediaType: String = "photo"
    private var videoOptions = com.rnattachmentkit.VideoExportOptions()
    /** onSelectionChange 에 실어 보낼 maxSelection (예전엔 10 고정) */
    private var lastMaxSelection: Int = 10
    private var lastThemeColorInt: Int? = null
    private var lastLanguageCode: String = "en"
    @Volatile private var currentVideoExporter: com.rnattachmentkit.VideoExporter? = null
    @Volatile private var videoCancelled = false
    /** 진행 중인 전송 처리 (processingId → 작업). 보내는 중에 갤러리를 다시 열어 또 보낼 수 있어 여러 개일 수 있음 */
    private val activeProcessingJobs = java.util.concurrent.ConcurrentHashMap<String, com.rnattachmentkit.ProcessingJob>()
    /** 가장 최근에 시작한 처리 (cancelVideoProcessing 에 processingId 가 없을 때) */
    @Volatile private var lastProcessingId: String? = null

    /** 보낸 순간의 설정 — 처리 중에 갤러리를 다시 열면 모듈 필드가 새 호출 값으로 바뀌므로, 처리는 이 사본만 씀 */
    private class SendSnapshot(
        val maxWidth: Int, val maxHeight: Int, val outputFormat: String,
        val videoOptions: com.rnattachmentkit.VideoExportOptions,
        val states: Map<String, com.rnattachmentkit.VideoEditState>,
        val showHUD: Boolean, val themeColor: Int?, val language: String,
        val thumbnail: com.rnattachmentkit.PhotoThumbnail.Options?
    )
    private fun sendSnapshot() = SendSnapshot(maxWidth, maxHeight, outputFormat, videoOptions, HashMap(lastVideoEditStates),
        showVideoHUD, lastThemeColorInt, lastLanguageCode, thumbnailOptions)
    /** 사진 썸네일 (GalleryOptions.thumbnail / EditorOptions.thumbnail). null 이면 만들지 않음 (기존과 같음) */
    private var thumbnailOptions: com.rnattachmentkit.PhotoThumbnail.Options? = null
    /** 동영상 변환 진행 HUD — video.showProgressHUD, 없으면 asyncProcessing 이 아닐 때만 (이벤트로 말풍선에 그리는 앱은 HUD 없이) */
    private var showVideoHUD = true
    /** 시트가 닫힐 때 넘겨받은 동영상 편집 상태 (원본 uri 문자열 → 품질·음소거) */
    private var lastVideoEditStates: Map<String, com.rnattachmentkit.VideoEditState> = emptyMap()

    @ReactMethod
    fun addListener(eventName: String) {
        // Keep: Required for RN built in Event Emitter Calls.
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        // Keep: Required for RN built in Event Emitter Calls.
    }

    private val viewerWillCloseReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.rnattachmentkit.VIEWER_WILL_CLOSE") {
                reactApplicationContext
                    .getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    .emit("onViewerWillClose", com.facebook.react.bridge.Arguments.createMap())
            }
        }
    }

    // 이미지 뷰어 상단바의 삭제를 사용자가 확정했을 때(ImageViewerOverlayView.handleDeleteTapped).
    // iOS의 "onImageDeleted" 이벤트와 동일한 body(index, url)로 JS에 알립니다 - 실제 메시지 삭제는 RN이 담당.
    private val imageDeletedReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.rnattachmentkit.IMAGE_DELETED") {
                val params = Arguments.createMap()
                params.putInt("index", intent.getIntExtra("index", 0))
                params.putString("url", intent.getStringExtra("url") ?: "")
                // patch405: 사용자가 고른 삭제 방식(deleteOptions 의 key). 선택지가 없었으면 생략.
                intent.getStringExtra("option")?.let { params.putString("option", it) }
                reactApplicationContext
                    .getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    .emit("onImageDeleted", params)
            }
        }
    }

    // 열기 애니메이션이 끝난 시점을 JS에 알리는 이벤트 (배경 스크롤 보정 타이밍용).
    private val viewerOpenedReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.rnattachmentkit.VIEWER_OPENED") {
                reactApplicationContext
                    .getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    .emit("onViewerOpened", com.facebook.react.bridge.Arguments.createMap())
            }
        }
    }

    init {
        com.rnattachmentkit.EventEmitterHelper.reactContext = reactContext
        reactContext.addActivityEventListener(this)
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactContext)
            .registerReceiver(viewerWillCloseReceiver, android.content.IntentFilter("com.rnattachmentkit.VIEWER_WILL_CLOSE"))
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactContext)
            .registerReceiver(viewerOpenedReceiver, android.content.IntentFilter("com.rnattachmentkit.VIEWER_OPENED"))
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactContext)
            .registerReceiver(imageDeletedReceiver, android.content.IntentFilter("com.rnattachmentkit.IMAGE_DELETED"))
    }

    override fun getName(): String = NAME

    companion object {
        const val NAME = "RNAttachmentKit"
        const val REQUEST_CODE_IMAGE_EDITOR = 1002
        
        val defaultAnimationConfig = mapOf(
            "galleryOpen" to 300,
            "galleryClose" to 250,
            "editorOpen" to 250,
            "editorClose" to 200,
            "viewerOpen" to 250,
            "viewerClose" to 200
        )
    }

    @ReactMethod
    override fun init(licenseKey: String, promise: Promise) {
        val result = LicenseManager.initialize(reactApplicationContext, licenseKey)
        promise.resolve(result)
    }

    @ReactMethod
    fun getDefaultAnimationConfig(promise: Promise) {
        val config = com.facebook.react.bridge.Arguments.createMap().apply {
            putInt("galleryOpen", defaultAnimationConfig["galleryOpen"] ?: 300)
            putInt("galleryClose", defaultAnimationConfig["galleryClose"] ?: 250)
            putInt("editorOpen", defaultAnimationConfig["editorOpen"] ?: 250)
            putInt("editorClose", defaultAnimationConfig["editorClose"] ?: 200)
            putInt("viewerOpen", defaultAnimationConfig["viewerOpen"] ?: 250)
            putInt("viewerClose", defaultAnimationConfig["viewerClose"] ?: 200)
        }
        promise.resolve(config)
    }

    @ReactMethod
    override fun openEditor(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        TurboImagePickerConfig.updateAppearance(if (options.hasKey("appearance")) options.getString("appearance") else null)
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        val uriStr = if (options.hasKey("uri")) options.getString("uri") else null
        if (uriStr == null) {
            promise.reject(E_FAILED_TO_PICK, "uri is required")
            return
        }

        val themeColor = if (options.hasKey("themeColor")) options.getString("themeColor") else null
        
        if (options.hasKey("maxWidth")) maxWidth = options.getInt("maxWidth")
        if (options.hasKey("maxHeight")) maxHeight = options.getInt("maxHeight")
        thumbnailOptions = com.rnattachmentkit.PhotoThumbnail.parse(
            if (options.hasKey("thumbnail") && !options.isNull("thumbnail")) options.getMap("thumbnail")?.toHashMap() else null
        )
        
        editImagePromise = promise

        try {
            val intent = ImageEditorActivity.createIntent(
                activity = activity,
                uris = listOf(Uri.parse(uriStr)),
                startIndex = 0,
                themeColor = themeColor,
                singlePhotoMode = true
            )
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                activity.startActivityForResult(intent, REQUEST_CODE_IMAGE_EDITOR)
            }, 50)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image editor: ${e.message}", e)
            editImagePromise = null
        }
    }

    @ReactMethod
    override fun openGallery(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        // Parse options
        val autoCloseOnSelect = if (options.hasKey("autoCloseOnSelect")) {
            options.getBoolean("autoCloseOnSelect")
        } else false

        // 선택 방식 (selectionMode: 'single' | 'multi', 생략 시 기존 규칙)
        //  - 'multi' : maxSelection 이 1 이어도 멀티와 똑같이 (autoCloseOnSelect 무시, 1 미만이면 1장)
        //  - 'single': 기존 단일 동작 (maxSelection 을 1로, autoCloseOnSelect 면 0)
        //  - 생략     : 기존 그대로 (autoCloseOnSelect → 0, 아니면 maxSelection, 기본 1)
        val selectionMode = if (options.hasKey("selectionMode")) options.getString("selectionMode")?.lowercase() else null
        val forceMultiMode = selectionMode == "multi"
        val maxSelection = if (forceMultiMode) {
            (if (options.hasKey("maxSelection")) options.getInt("maxSelection") else 1).coerceAtLeast(1)
        } else if (autoCloseOnSelect) {
            0
        } else if (selectionMode == "single") {
            1
        } else if (options.hasKey("maxSelection")) {
            options.getInt("maxSelection")
        } else {
            1
        }
        
        val languageCode = if (options.hasKey("languageCode")) {
            options.getString("languageCode") ?: "en"
        } else {
            "en"
        }
        // 편집기/크롭 등 다른 화면들은 TurboImagePickerConfig.languageCode(전역)로 로케일을 잡는데,
        // 그동안 JS가 넘긴 languageCode를 여기에 반영하는 코드가 없어서 항상 기본값 "en"이었습니다.
        TurboImagePickerConfig.languageCode = languageCode
        TurboImagePickerConfig.updateAppearance(if (options.hasKey("appearance")) options.getString("appearance") else null)
        
        val themeColor = if (options.hasKey("themeColor")) {
            options.getString("themeColor")
        } else {
            null
        }
        
        maxWidth = if (options.hasKey("maxWidth")) {
            val value = options.getInt("maxWidth")
            if (value > 0) value else 1024
        } else {
            1024
        }
        
        maxHeight = if (options.hasKey("maxHeight")) {
            val value = options.getInt("maxHeight")
            if (value > 0) value else 1024
        } else {
            1024
        }

        outputFormat = if (options.hasKey("outputFormat")) {
            options.getString("outputFormat")?.lowercase() ?: "webp"
        } else if (options.hasKey("format")) {
            options.getString("format")?.lowercase() ?: "webp"
        } else {
            "webp"
        }

        val enableEditor = if (options.hasKey("enableEditor")) {
            options.getBoolean("enableEditor")
        } else {
            false
        }
        
        val profileMode = if (options.hasKey("profileMode")) {
            options.getBoolean("profileMode")
        } else {
            false
        }

        // 동영상: mediaType "photo"(기본) | "video" | "all", video: VideoOptions
        mediaType = (if (options.hasKey("mediaType") && !options.isNull("mediaType")) options.getString("mediaType") else null)
            ?.lowercase()?.takeIf { it == "video" || it == "all" } ?: "photo"
        videoOptions = com.rnattachmentkit.VideoExportOptions.fromMap(
            if (options.hasKey("video") && !options.isNull("video")) options.getMap("video")?.toHashMap() else null
        )
        // 사진 썸네일 (동영상 포스터 규칙은 그대로 — video.posterFormat, 긴 변 512)
        thumbnailOptions = com.rnattachmentkit.PhotoThumbnail.parse(
            if (options.hasKey("thumbnail") && !options.isNull("thumbnail")) options.getMap("thumbnail")?.toHashMap() else null
        )
        run {
            val async = options.hasKey("asyncProcessing") && !options.isNull("asyncProcessing") && options.getBoolean("asyncProcessing")
            val v = if (options.hasKey("video") && !options.isNull("video")) options.getMap("video") else null
            showVideoHUD = if (v != null && v.hasKey("showProgressHUD") && !v.isNull("showProgressHUD")) v.getBoolean("showProgressHUD") else !async
        }
        lastMaxSelection = maxSelection
        TurboImagePickerConfig.videoOptions = videoOptions
        lastLanguageCode = languageCode
        lastThemeColorInt = try { themeColor?.let { android.graphics.Color.parseColor(it) } } catch (_: Exception) { null }

        val fragmentActivity = activity as? FragmentActivity
        if (fragmentActivity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity is not a FragmentActivity")
            return
        }

        pickImagesPromise = promise
        // 이번 호출의 promise 를 붙잡아 둠 — 리스너가 모듈 필드를 읽으면, 시트가 열린 채 openGallery 를 다시 불렀을 때
        // 이전 시트가 치워지며 오는 onDismiss 가 "새" promise 를 거부해 버림. 시트마다 자기 promise 를 한 번만 끝냄
        val thisPromise = promise
        var settled = false
        val settle: ((Promise) -> Unit) -> Unit = { block ->
            if (!settled) {
                settled = true
                if (pickImagesPromise === thisPromise) pickImagesPromise = null
                block(thisPromise)
            }
        }
        // 지난 호출이 남긴 오래된 임시 파일(24시간 지난 것) 정리 — 백그라운드
        moduleScope.launch(Dispatchers.IO) {
            try { TempFileCleaner.cleanStale(reactApplicationContext) } catch (_: Exception) {}
        }

        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        // Android 13+ 에서 동영상도 보이면 READ_MEDIA_VIDEO 를 같이 요청
        val mediaPermissions: Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && mediaType != "photo") {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            arrayOf(permission)
        }

        val showSheet = {
            fragmentActivity.runOnUiThread {
                try {
                    val bottomSheet = ImagePickerBottomSheet.newInstance(
                        maxSelection, languageCode, enableEditor, profileMode, maxWidth, maxHeight, themeColor,
                        forceMultiMode = forceMultiMode,
                        // 첨부 메뉴(갤러리 / 위치 / 파일). 기본 false — 켜지 않으면 기존과 같음
                        showAttachMenu = options.hasKey("showAttachMenu") && options.getBoolean("showAttachMenu"),
                        // (Android) 첨부 메뉴 바 아래 여백 (dp). 없으면 기본 12 / 8
                        attachMenuSinkIntoNav = if (options.hasKey("attachMenuSinkIntoNav") && !options.isNull("attachMenuSinkIntoNav"))
                            options.getDouble("attachMenuSinkIntoNav").toFloat() else com.rnattachmentkit.AttachMenuBarView.SINK_INTO_NAV_DP.toFloat(),
                        attachMenuMinBottomMargin = if (options.hasKey("attachMenuMinBottomMargin") && !options.isNull("attachMenuMinBottomMargin"))
                            options.getDouble("attachMenuMinBottomMargin").toFloat() else com.rnattachmentkit.AttachMenuBarView.BOTTOM_MARGIN_DP.toFloat(),
                        // 위치 보내기 때 지도 이미지 캡처 여부. 기본 true (기존 그대로). false 면 이미지 없이 위치 정보만
                        captureLocationImage = !(options.hasKey("captureLocationImage") && !options.isNull("captureLocationImage")) ||
                            options.getBoolean("captureLocationImage"),
                        // 동영상 (mediaType "video"/"all" 일 때 그리드에 동영상, 길이 제한)
                        mediaType = mediaType,
                        maxVideoDurationSec = videoOptions.maxDurationSec
                    )
                    // 위치 탭에서 보내기 → onLocationSelected 이벤트로 결과를 넘기고, openGallery 는 빈 배열로 끝냄
                    bottomSheet.setOnLocationSelectedListener { loc ->
                        val body = com.facebook.react.bridge.Arguments.createMap()
                        for ((k, v) in loc) {
                            when (v) {
                                is Int -> body.putInt(k, v)
                                is Long -> body.putDouble(k, v.toDouble())
                                is Double -> body.putDouble(k, v)
                                is Float -> body.putDouble(k, v.toDouble())
                                is Boolean -> body.putBoolean(k, v)
                                is String -> body.putString(k, v)
                            }
                        }
                        emitGalleryEvent("onLocationSelected", body)
                        settle { it.resolve(com.facebook.react.bridge.Arguments.createArray()) }
                    }
                    // 파일 탭에서 보내기 → onFilesSelected 이벤트 { files: [{uri, path, name, size, mimeType}], failed: [{name, error}] }, openGallery 는 빈 배열
                    bottomSheet.setOnFilesResultListener { files, failed ->
                        val arr = com.facebook.react.bridge.Arguments.createArray()
                        for (file in files) {
                            val m = com.facebook.react.bridge.Arguments.createMap()
                            for ((k, v) in file) {
                                when (v) {
                                    is Double -> m.putDouble(k, v)
                                    is String -> m.putString(k, v)
                                }
                            }
                            arr.pushMap(m)
                        }
                        val body = com.facebook.react.bridge.Arguments.createMap()
                        body.putArray("files", arr)
                        // 복사에 실패한 파일 (추가 필드 — files 는 예전과 같음)
                        val failedArr = com.facebook.react.bridge.Arguments.createArray()
                        for (f in failed) {
                            val m = com.facebook.react.bridge.Arguments.createMap()
                            m.putString("name", f["name"]?.toString() ?: "")
                            m.putString("error", f["error"]?.toString() ?: "")
                            failedArr.pushMap(m)
                        }
                        body.putArray("failed", failedArr)
                        emitGalleryEvent("onFilesSelected", body)
                        settle { it.resolve(com.facebook.react.bridge.Arguments.createArray()) }
                    }
                    bottomSheet.setOnImagesSelectedListener { uris ->
                        lastVideoEditStates = HashMap(bottomSheet.videoEditStates)
                        val result = WritableNativeArray()
                        for (uri in uris) {
                            result.pushString(uri.toString())
                        }
                        settle { handleSelectedImages(result, it) }
                    }
                    bottomSheet.setOnCancelledListener {
                        settle { it.reject(E_PICKER_CANCELLED, "User cancelled image picker") }
                    }
                    
                    val existingFragment = fragmentActivity.supportFragmentManager.findFragmentByTag("ImagePickerBottomSheet")
                    existingFragment?.let {
                        fragmentActivity.supportFragmentManager.beginTransaction().remove(it).commitAllowingStateLoss()
                    }
                    
                    fragmentActivity.supportFragmentManager.beginTransaction()
                        .add(bottomSheet, "ImagePickerBottomSheet")
                        .commitAllowingStateLoss()
                        
                } catch (e: Exception) {
                    settle { it.reject(E_FAILED_TO_PICK, "Failed to open image picker: ${e.message}", e) }
                }
            }
        }

        if (mediaPermissions.all { ContextCompat.checkSelfPermission(fragmentActivity, it) == PackageManager.PERMISSION_GRANTED }) {
            showSheet()
        } else {
            val permissionAwareActivity = fragmentActivity as? PermissionAwareActivity
            if (permissionAwareActivity == null) {
                promise.reject(E_NO_ACTIVITY, "Activity is not PermissionAwareActivity")
                pickImagesPromise = null
                return
            }

            val permissionsToRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && permission == Manifest.permission.READ_MEDIA_IMAGES) {
                // 일부만 허용한 사용자는 열 때마다 사진 선택 창을 다시 띄우지 않으려고 바로 엶.
                //   단 동영상도 보여야 하는데 READ_MEDIA_VIDEO 를 한 번도 묻지 않았으면 한 번은 물어봄 — 예전엔 사진 전용으로
                //   권한을 받은 사용자(예: 가입 때 프로필 사진)가 여기서 바로 열려 동영상 권한을 영영 묻지 않아 동영상이 안 보였음
                if (ContextCompat.checkSelfPermission(fragmentActivity, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED &&
                    (mediaType == "photo" || ContextCompat.checkSelfPermission(fragmentActivity, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED || wasVideoPermissionAsked())) {
                    showSheet()
                    return
                }
                mediaPermissions + Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
            } else {
                mediaPermissions
            }

            if (permissionsToRequest.contains(Manifest.permission.READ_MEDIA_VIDEO)) markVideoPermissionAsked()
            permissionAwareActivity.requestPermissions(permissionsToRequest, 100, object : PermissionListener {
                override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray): Boolean {
                    if (requestCode == 100 && grantResults != null) {
                        val isGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            // 14+: 전체 허용이든 "일부 선택"이든 하나라도 허용이면 진행
                            grantResults.any { it == PackageManager.PERMISSION_GRANTED }
                        } else {
                            grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                        }

                        if (isGranted) {
                            showSheet()
                        } else {
                            settle { it.reject("E_PERMISSION_DENIED", "Permission denied") }
                        }
                    }
                    return true
                }
            })
        }
    }

    @ReactMethod
    override fun updateSourceRect(options: ReadableMap, promise: Promise) {
        var startX = -1f
        var startY = -1f
        var startWidth = -1f
        var startHeight = -1f

        if (options.hasKey("x")) {
            startX = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("x").toFloat())
        }
        if (options.hasKey("y")) {
            startY = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("y").toFloat())
        }
        if (options.hasKey("width")) {
            startWidth = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("width").toFloat())
        }
        if (options.hasKey("height")) {
            startHeight = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("height").toFloat())
        }

        // 브로드캐스트가 유실되는 타이밍(Fragment의 onViewCreated 전) 대비, sticky 값도 함께 저장.
        // (useDialogViewer/useOverlayViewer 중 실제 사용 중인 쪽만 값을 읽으므로 둘 다 갱신해도 무해함)
        ImageViewerDialogFragment.updatePendingCoordinates(startX, startY, startWidth, startHeight)
        ImageViewerOverlayView.updatePendingCoordinates(startX, startY, startWidth, startHeight)

        val intent = android.content.Intent("com.rnattachmentkit.UPDATE_COORDINATES")
        intent.putExtra("startX", startX)
        intent.putExtra("startY", startY)
        intent.putExtra("startWidth", startWidth)
        intent.putExtra("startHeight", startHeight)
        // 그동안 sourceBorderCorners(어느 모서리를 둥글릴지)가 여기서 전달되지 않아서, 그룹 이미지에서
        // 스와이프로 다른 셀(예: 오른쪽 위 모서리 이미지)로 이동해도 마스크의 라운드 코너 패턴이
        // 처음 열었던 이미지의 것으로 고정된 채 안 바뀌는 문제가 있었습니다. JS가 onPageSelected에서
        // 매번 새로 계산해서 보내주는 sourceBorderCorners를 브로드캐스트에 실어 보내도록 수정합니다.
        if (options.hasKey("sourceBorderCorners")) {
            val cornersArray = options.getArray("sourceBorderCorners")
            if (cornersArray != null) {
                val corners = java.util.ArrayList<String>()
                for (i in 0 until cornersArray.size()) {
                    cornersArray.getString(i)?.let { corners.add(it) }
                }
                intent.putStringArrayListExtra("sourceBorderCorners", corners)
            }
        }
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactApplicationContext).sendBroadcast(intent)
        promise.resolve(null)
    }

    /** 동영상 변환 취소 (HUD 없이 앱이 말풍선에서). index -1 = 남은 동영상 전부. 진행 중인 처리가 없으면 false */
    @ReactMethod
    fun cancelVideoProcessing(index: Double, processingId: String, promise: Promise) {
        val job = (processingId.ifEmpty { lastProcessingId })?.let { activeProcessingJobs[it] }
        if (job == null) { promise.resolve(false); return }
        job.cancel(if (index >= 0) index.toInt() else null)
        promise.resolve(true)
    }

    @ReactMethod
    override fun closeGallery(promise: Promise) {
        val currentActivity = currentActivity
        if (currentActivity != null) {
            val intent = android.content.Intent("com.rnattachmentkit.CLOSE_GALLERY")
            androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(currentActivity).sendBroadcast(intent)
            promise.resolve(true)
        } else {
            promise.resolve(false)
        }
    }

    @ReactMethod
    // 동영상 권한(READ_MEDIA_VIDEO)을 한 번 물어봤는지 — 물어본 뒤 거절했으면 다시 묻지 않음 (Android 14+ 일부 허용 경로)
    private fun mediaPermPrefs() = reactApplicationContext.getSharedPreferences("rnak_media_perm", android.content.Context.MODE_PRIVATE)
    private fun wasVideoPermissionAsked(): Boolean = mediaPermPrefs().getBoolean("video_asked", false)
    private fun markVideoPermissionAsked() { mediaPermPrefs().edit().putBoolean("video_asked", true).apply() }

    override fun openViewer(options: ReadableMap, promise: Promise) {
        // 동영상 페이지는 라이선스 키가 있어야
        if (!LicenseGate.isLicensed && options.hasKey("videos")) {
            val va = options.getArray("videos")
            val anyVideo = va != null && (0 until va.size()).any { i ->
                va.getType(i) == com.facebook.react.bridge.ReadableType.Map && va.getMap(i)?.let { it.hasKey("uri") && !it.isNull("uri") && !it.getString("uri").isNullOrEmpty() } == true
            }
            if (anyVideo) { promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return }
        }
        val activity = getCurrentActivity()
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        if (!options.hasKey("images")) {
            promise.reject(E_FAILED_TO_PICK, "images array is required")
            return
        }

        val imagesArray = options.getArray("images")
        if (imagesArray == null || imagesArray.size() == 0) {
            promise.reject(E_FAILED_TO_PICK, "images array cannot be empty")
            return
        }

        val images = ArrayList<String>()
        for (i in 0 until imagesArray.size()) {
            val str = imagesArray.getString(i)
            if (str != null) {
                images.add(str)
            }
        }

        // cacheFiles: images 와 같은 순서의 앱 캐시 파일 경로 (null → 빈 문자열). 뷰어 전체(모든 방식)에 적용.
        val cacheFiles = ArrayList<String>()
        if (options.hasKey("cacheFiles") && !options.isNull("cacheFiles")) {
            val arr = options.getArray("cacheFiles")
            if (arr != null) {
                for (i in 0 until arr.size()) {
                    cacheFiles.add(if (arr.isNull(i)) "" else (arr.getString(i) ?: ""))
                }
            }
        }
        ViewerCacheFiles.register(images, if (cacheFiles.isEmpty()) null else cacheFiles)

        val initialIndex = if (options.hasKey("initialIndex")) options.getInt("initialIndex") else 0
        val themeColor = if (options.hasKey("themeColor")) options.getString("themeColor") else "#FF6B35"
        val title = if (options.hasKey("title")) options.getString("title") else null
        val animationType = if (options.hasKey("animationType")) options.getString("animationType") else null
        // ⚠️ 뷰어가 항상 영어로만 나오던 원인: JS는 init()에서 설정한 기본 언어를 openViewer 옵션의
        // languageCode로 매번 같이 넘기는데, 안드로이드 쪽에서는 그 값을 한 번도 읽지 않았고
        // ImageViewerOverlayView는 TurboImagePickerConfig.attachBaseContext()(전역 languageCode,
        // 기본값 "en")로 로케일을 강제하고 있었습니다. 여기서 반영해야 뷰어의 모든 문구가
        // 설정된 언어를 따릅니다.
        val viewerLanguageCode = if (options.hasKey("languageCode")) (options.getString("languageCode") ?: "en") else "en"
        TurboImagePickerConfig.languageCode = viewerLanguageCode
        TurboImagePickerConfig.updateAppearance(if (options.hasKey("appearance")) options.getString("appearance") else null)
        
        val openDuration = if (options.hasKey("openDuration")) options.getInt("openDuration") else defaultAnimationConfig["viewerOpen"] ?: 250
        val closeDuration = if (options.hasKey("closeDuration")) options.getInt("closeDuration") else defaultAnimationConfig["viewerClose"] ?: 200

        var startX = -1f
        var startY = -1f
        var startWidth = -1f
        var startHeight = -1f

        if (options.hasKey("sourceRect")) {
            val sourceRect = options.getMap("sourceRect")
            if (sourceRect != null) {
                startX = if (sourceRect.hasKey("x")) com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(sourceRect.getDouble("x").toFloat()) else -1f
                startY = if (sourceRect.hasKey("y")) com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(sourceRect.getDouble("y").toFloat()) else -1f
                startWidth = if (sourceRect.hasKey("width")) com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(sourceRect.getDouble("width").toFloat()) else -1f
                startHeight = if (sourceRect.hasKey("height")) com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(sourceRect.getDouble("height").toFloat()) else -1f
            }
        }

        val useDialogViewer = options.hasKey("useDialogViewer") && options.getBoolean("useDialogViewer")
        val useOverlayViewer = options.hasKey("useOverlayViewer") && options.getBoolean("useOverlayViewer")

        try {
            if (useOverlayViewer) {
                val args = android.os.Bundle().apply {
                    putStringArrayList(ImageViewerActivity.EXTRA_IMAGES, images)
                    putInt(ImageViewerActivity.EXTRA_INITIAL_INDEX, initialIndex)
                    putString("EXTRA_THEME_COLOR", themeColor)
                    if (title != null) {
                        putString(ImageViewerActivity.EXTRA_TITLE, title)
                    }
                    if (animationType != null) {
                        putString("animationType", animationType)
                    }
                    if (options.hasKey("closeAnimationType")) {
                        putString("closeAnimationType", options.getString("closeAnimationType"))
                    }
                    if (startX != -1f) {
                        putFloat("startX", startX)
                        putFloat("startY", startY)
                        putFloat("startWidth", startWidth)
                        putFloat("startHeight", startHeight)
                    }
                    if (options.hasKey("sourceBorderRadius")) {
                        putFloat("sourceBorderRadius", com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("sourceBorderRadius").toFloat()))
                    }
                    if (options.hasKey("sourceBorderCorners")) {
                        val cornersArray = options.getArray("sourceBorderCorners")
                        if (cornersArray != null) {
                            val corners = ArrayList<String>()
                            for (i in 0 until cornersArray.size()) {
                                cornersArray.getString(i)?.let { corners.add(it) }
                            }
                            putStringArrayList("sourceBorderCorners", corners)
                        }
                    }
                    // sourceBackgroundColor가 그동안 어느 뷰어 분기에서도 전달되지 않아
                    // mMaskView(닫기/열기 애니메이션 중 원본 썸네일을 가리는 마스크)가 항상 생성되지
                    // 않던 문제를 수정: JS의 sourceBackgroundColor(hex 문자열)를 그대로 전달합니다.
                    if (options.hasKey("sourceBackgroundColor")) {
                        putString("sourceBackgroundColor", options.getString("sourceBackgroundColor"))
                    }
                    // placeholderImages: 타입/뷰어 코드에는 있었지만 브릿지에서 한 번도 전달되지 않았던
                    // 필드. 네이티브 뷰어가 onlyRetrieveFromCache(true)로 첫 프레임을 즉시 그리려 할 때
                    // 쓰는 저해상도 대체 이미지 목록입니다(원본 다운로드 전 임시 표시용).
                    if (options.hasKey("placeholderImages")) {
                        val placeholderArray = options.getArray("placeholderImages")
                        if (placeholderArray != null) {
                            val placeholders = ArrayList<String>()
                            for (i in 0 until placeholderArray.size()) {
                                placeholders.add(placeholderArray.getString(i) ?: "")
                            }
                            putStringArrayList("placeholderImages", placeholders)
                        }
                    }
                    // 동영상 페이지 (뷰어 동영상 작업 지시서 V1): videos[i] = { uri, cacheFile? } 또는 null(사진).
                    // images[i] 는 그 동영상의 포스터. 이 오버레이 뷰어에서만 재생합니다.
                    if (options.hasKey("videos")) {
                        val videoArray = options.getArray("videos")
                        if (videoArray != null) {
                            val uris = ArrayList<String>()
                            val caches = ArrayList<String>()
                            for (i in 0 until videoArray.size()) {
                                val m = if (videoArray.getType(i) == com.facebook.react.bridge.ReadableType.Map) videoArray.getMap(i) else null
                                uris.add(if (m != null && m.hasKey("uri") && !m.isNull("uri")) m.getString("uri") ?: "" else "")
                                caches.add(if (m != null && m.hasKey("cacheFile") && !m.isNull("cacheFile")) m.getString("cacheFile") ?: "" else "")
                            }
                            putStringArrayList(com.rnattachmentkit.ViewerVideoSource.ARG_URIS, uris)
                            putStringArrayList(com.rnattachmentkit.ViewerVideoSource.ARG_CACHE_FILES, caches)
                        }
                    }
                    // 상단바 저장/공유/삭제 버튼과 그 문구들 (iOS와 동일한 옵션 키). 문구를 안 넘기면
                    // 네이티브 쪽 로케일 리소스(values-ko/ja/zh, 그 외 en)가 자동 적용됩니다.
                    putBoolean("showActionButtons", !options.hasKey("showActionButtons") || options.getBoolean("showActionButtons"))
                    putBoolean("showDeleteButton", !options.hasKey("showDeleteButton") || options.getBoolean("showDeleteButton"))
                    for (key in listOf(
                        "saveAllText", "saveOneText", "shareAllText", "shareOneText", "actionCancelText",
                        "deleteConfirmTitle", "deleteConfirmMessage", "deleteConfirmGroupMessage", "deleteButtonText"
                    )) {
                        if (options.hasKey(key)) {
                            options.getString(key)?.let { putString(key, it) }
                        }
                    }
                    // patch405: 삭제 방식 선택지 [{ key, label, destructive }] → 나란한 배열 3개로 전달
                    if (options.hasKey("deleteOptions") && !options.isNull("deleteOptions")) {
                        val arr = options.getArray("deleteOptions")
                        if (arr != null) {
                            val keys = ArrayList<String>()
                            val labels = ArrayList<String>()
                            val destructive = ArrayList<Boolean>()
                            for (i in 0 until arr.size()) {
                                val m = arr.getMap(i) ?: continue
                                val k = if (m.hasKey("key")) m.getString("key") else null
                                val l = if (m.hasKey("label")) m.getString("label") else null
                                if (k.isNullOrEmpty() || l.isNullOrEmpty()) continue
                                keys.add(k)
                                labels.add(l)
                                destructive.add(m.hasKey("destructive") && !m.isNull("destructive") && m.getBoolean("destructive"))
                            }
                            if (keys.isNotEmpty()) {
                                putStringArrayList("deleteOptionKeys", keys)
                                putStringArrayList("deleteOptionLabels", labels)
                                putBooleanArray("deleteOptionDestructive", destructive.toBooleanArray())
                            }
                        }
                    }
                }
                // 이전 세션에서 남은 sticky 좌표가 이번 오픈에 잘못 적용되지 않도록 초기화.
                ImageViewerOverlayView.clearPendingCoordinates()
                activity.runOnUiThread {
                    ImageViewerOverlayView.present(activity, args)
                }
                promise.resolve(null)
                return
            }

            if (useDialogViewer && activity is androidx.fragment.app.FragmentActivity) {
                val args = android.os.Bundle().apply {
                    putStringArrayList(ImageViewerActivity.EXTRA_IMAGES, images)
                    putInt(ImageViewerActivity.EXTRA_INITIAL_INDEX, initialIndex)
                    putString("EXTRA_THEME_COLOR", themeColor)
                    if (title != null) {
                        putString(ImageViewerActivity.EXTRA_TITLE, title)
                    }
                    if (animationType != null) {
                        putString("animationType", animationType)
                    }
                    if (options.hasKey("closeAnimationType")) {
                        putString("closeAnimationType", options.getString("closeAnimationType"))
                    }
                    if (startX != -1f) {
                        putFloat("startX", startX)
                        putFloat("startY", startY)
                        putFloat("startWidth", startWidth)
                        putFloat("startHeight", startHeight)
                    }
                    if (options.hasKey("sourceBorderRadius")) {
                        putFloat("sourceBorderRadius", com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("sourceBorderRadius").toFloat()))
                    }
                    if (options.hasKey("sourceBorderCorners")) {
                        val cornersArray = options.getArray("sourceBorderCorners")
                        if (cornersArray != null) {
                            val corners = ArrayList<String>()
                            for (i in 0 until cornersArray.size()) {
                                cornersArray.getString(i)?.let { corners.add(it) }
                            }
                            putStringArrayList("sourceBorderCorners", corners)
                        }
                    }
                    // sourceBackgroundColor가 그동안 어느 뷰어 분기에서도 전달되지 않아
                    // mMaskView(닫기/열기 애니메이션 중 원본 썸네일을 가리는 마스크)가 항상 생성되지
                    // 않던 문제를 수정: JS의 sourceBackgroundColor(hex 문자열)를 그대로 전달합니다.
                    if (options.hasKey("sourceBackgroundColor")) {
                        putString("sourceBackgroundColor", options.getString("sourceBackgroundColor"))
                    }
                    // placeholderImages: 타입/뷰어 코드에는 있었지만 브릿지에서 한 번도 전달되지 않았던
                    // 필드. 네이티브 뷰어가 onlyRetrieveFromCache(true)로 첫 프레임을 즉시 그리려 할 때
                    // 쓰는 저해상도 대체 이미지 목록입니다(원본 다운로드 전 임시 표시용).
                    if (options.hasKey("placeholderImages")) {
                        val placeholderArray = options.getArray("placeholderImages")
                        if (placeholderArray != null) {
                            val placeholders = ArrayList<String>()
                            for (i in 0 until placeholderArray.size()) {
                                placeholders.add(placeholderArray.getString(i) ?: "")
                            }
                            putStringArrayList("placeholderImages", placeholders)
                        }
                    }
                }
                // 이전 세션에서 남은 sticky 좌표가 이번 오픈에 잘못 적용되지 않도록 초기화.
                ImageViewerDialogFragment.clearPendingCoordinates()
                activity.runOnUiThread {
                    ImageViewerDialogFragment.newInstance(args)
                        .show(activity.supportFragmentManager, "image_viewer_dialog")
                }
                promise.resolve(null)
                return
            }

            val intent = Intent(activity, ImageViewerActivity::class.java).apply {
                putStringArrayListExtra(ImageViewerActivity.EXTRA_IMAGES, images)
                putExtra(ImageViewerActivity.EXTRA_INITIAL_INDEX, initialIndex)
                putExtra("EXTRA_THEME_COLOR", themeColor)
                if (title != null) {
                    putExtra(ImageViewerActivity.EXTRA_TITLE, title)
                }
                if (animationType != null) {
                    putExtra("animationType", animationType)
                }
                if (options.hasKey("closeAnimationType")) {
                    putExtra("closeAnimationType", options.getString("closeAnimationType"))
                }
                putExtra("openDuration", openDuration)
                putExtra("closeDuration", closeDuration)
                if (startX != -1f) {
                    putExtra("startX", startX)
                    putExtra("startY", startY)
                    putExtra("startWidth", startWidth)
                    putExtra("startHeight", startHeight)
                }
                if (options.hasKey("sourceBorderRadius")) {
                    putExtra("sourceBorderRadius", com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(options.getDouble("sourceBorderRadius").toFloat()))
                }
                if (options.hasKey("sourceBorderCorners")) {
                    val cornersArray = options.getArray("sourceBorderCorners")
                    if (cornersArray != null) {
                        val corners = java.util.ArrayList<String>()
                        for (i in 0 until cornersArray.size()) {
                            cornersArray.getString(i)?.let { corners.add(it) }
                        }
                        putStringArrayListExtra("sourceBorderCorners", corners)
                    }
                }
                if (options.hasKey("sourceBackgroundColor")) {
                    putExtra("sourceBackgroundColor", options.getString("sourceBackgroundColor"))
                }
                if (options.hasKey("placeholderImages")) {
                    val placeholderArray = options.getArray("placeholderImages")
                    if (placeholderArray != null) {
                        val placeholders = ArrayList<String>()
                        for (i in 0 until placeholderArray.size()) {
                            placeholders.add(placeholderArray.getString(i) ?: "")
                        }
                        putStringArrayListExtra("placeholderImages", placeholders)
                    }
                }
            }
            activity.startActivity(intent)
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image viewer: ${e.message}", e)
        }
    }

    override fun onActivityResult(
        activity: Activity,
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        if (requestCode == REQUEST_CODE_IMAGE_EDITOR) {
            val promise = editImagePromise ?: return
            editImagePromise = null

            if (resultCode != Activity.RESULT_OK || data == null) {
                promise.reject(E_PICKER_CANCELLED, "User cancelled image editor")
                return
            }

            val uriStrings = data.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_URIS)
            if (uriStrings == null || uriStrings.isEmpty()) {
                promise.reject(E_PICKER_CANCELLED, "User cancelled image editor")
                return
            }

            val uris = uriStrings.mapNotNull { uriString ->
                try { Uri.parse(uriString) } catch (e: Exception) { null }
            }

            if (uris.isEmpty()) {
                promise.reject(E_FAILED_TO_PICK, "Failed to parse image URIs")
                return
            }

            val snap = sendSnapshot()
            moduleScope.launch {
                try {
                    val results = processImages(uris, snap)
                    if (results.isNotEmpty()) {
                        promise.resolve(results[0])
                    } else {
                        promise.reject(E_FAILED_TO_PICK, "Failed to process image")
                    }
                } catch (e: Exception) {
                    promise.reject(E_FAILED_TO_PICK, "Failed to process image: ${e.message}", e)
                }
            }
            return
        }


    }

    override fun onNewIntent(intent: Intent) {
        // Not needed for this module
    }

    private fun handleSelectedImages(uriStrings: ReadableArray, promise: Promise?) {
        val actualPromise = promise ?: return

        // Convert string URIs to Uri objects
        val uris = mutableListOf<Uri>()
        for (i in 0 until uriStrings.size()) {
            val uriString = uriStrings.getString(i)
            if (uriString != null) {
                try {
                    uris.add(Uri.parse(uriString))
                } catch (e: Exception) {
                    // Ignore
                }
            }
        }

        if (uris.isEmpty()) {
            actualPromise.reject(E_FAILED_TO_PICK, "Failed to parse image URIs")
            return
        }

        // Process images asynchronously
        val eventMap = com.facebook.react.bridge.WritableNativeMap()
        eventMap.putInt("selectedCount", uris.size)
        eventMap.putInt("maxSelection", lastMaxSelection)
        try {
            reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit("onSelectionChange", eventMap)
        } catch (e: Exception) {
            // Ignore
        }

        val snap = sendSnapshot()
        moduleScope.launch {
            try {
                val results = processImages(uris, snap)
                val array = com.facebook.react.bridge.Arguments.createArray()
                results.forEach { array.pushMap(it) }
                actualPromise.resolve(array)
            } catch (e: com.rnattachmentkit.VideoExporter.CancelledException) {
                actualPromise.reject("CANCELLED", "Video export cancelled")
            } catch (e: Exception) {
                actualPromise.reject(E_FAILED_TO_PICK, "Failed to process images: ${e.message}", e)
            }
        }
    }

    private suspend fun processImages(uris: List<Uri>, snap: SendSnapshot): List<com.facebook.react.bridge.WritableMap> = withContext(Dispatchers.IO) {
        // 보낸 순간의 설정 (모듈 필드와 같은 이름으로 가림 — 아래 코드는 그대로)
        val maxWidth = snap.maxWidth
        val maxHeight = snap.maxHeight
        val outputFormat = snap.outputFormat
        val videoOptions = snap.videoOptions
        val lastVideoEditStates = snap.states
        val showVideoHUD = snap.showHUD
        val lastThemeColorInt = snap.themeColor
        val lastLanguageCode = snap.language
        val thumbnailOptions = snap.thumbnail
        val processingId = java.util.UUID.randomUUID().toString()
        val results = mutableListOf<com.facebook.react.bridge.WritableMap>()
        val contentResolver = reactApplicationContext.contentResolver
        val totalCount = uris.size
        var currentIndex = 0

        // 동영상이 섞여 있으면 진행 HUD 를 띄우고, 동영상은 VideoExporter 로 (사진 처리와 같은 루프)
        val isVideoUri: (Uri) -> Boolean = { u ->
            u.toString().contains("/video/") || (try { contentResolver.getType(u)?.startsWith("video/") == true } catch (_: Exception) { false })
        }
        val hasVideo = uris.any(isVideoUri)
        videoCancelled = false
        val job = com.rnattachmentkit.ProcessingJob()
        activeProcessingJobs[processingId] = job
        lastProcessingId = processingId
        // ✅ 처리 시작: 모든 자리(사진·동영상)를 먼저 알림 → 앱이 말풍선을 바로 만들고 진행률을 그림
        try {
            val items = Arguments.createArray()
            uris.forEachIndexed { i, u ->
                val it0 = if (isVideoUri(u)) {
                    val st = lastVideoEditStates[u.toString()] ?: com.rnattachmentkit.VideoEditState(qualityHeight = videoOptions.defaultQuality)
                    com.rnattachmentkit.MediaProcessing.videoItem(reactApplicationContext, i, u, st, videoOptions)
                } else {
                    com.rnattachmentkit.MediaProcessing.imageItem(reactApplicationContext, i, u, maxWidth, maxHeight)
                }
                items.pushMap(Arguments.createMap().apply {
                    putInt("index", it0.index)
                    putString("mediaType", if (it0.isVideo) "video" else "image")
                    putString("originalUri", it0.originalUri)
                    putInt("width", it0.width)
                    putInt("height", it0.height)
                    it0.durationSec?.let { d -> putDouble("duration", d) }
                    it0.thumbnailUri?.let { t ->
                        putString("thumbnailUri", t)
                        putInt("thumbnailWidth", it0.thumbnailWidth)
                        putInt("thumbnailHeight", it0.thumbnailHeight)
                    }
                })
            }
            emitGalleryEvent("onProcessingStart", Arguments.createMap().apply {
                putString("processingId", processingId)
                putInt("total", totalCount)
                putArray("items", items)
            })
        } catch (e: Exception) {
            android.util.Log.w("RNAttachmentKit", "onProcessingStart failed: ${e.message}")
        }
        var hud: com.rnattachmentkit.VideoExportHUD? = null
        if (hasVideo && showVideoHUD) {
            withContext(Dispatchers.Main) {
                val act = getCurrentActivity() ?: return@withContext
                hud = com.rnattachmentkit.VideoExportHUD(act, lastThemeColorInt, lastLanguageCode).also { h ->
                    h.onCancel = {
                        videoCancelled = true
                        currentVideoExporter?.cancel()
                    }
                    h.show()
                }
            }
        }
        val videoFiles = mutableListOf<File>()

        try {
        for (uri in uris) {
            if (videoCancelled) throw com.rnattachmentkit.VideoExporter.CancelledException()
            if (isVideoUri(uri)) {
                val idx = currentIndex
                val exporter = com.rnattachmentkit.VideoExporter(reactApplicationContext)
                currentVideoExporter = exporter
                val cancelledMap = {
                    WritableNativeMap().apply {
                        putString("originalUri", uri.toString())
                        putString("mediaType", "video")
                        putString("error", "CANCELLED")
                        putBoolean("cancelled", true)
                    }
                }
                val resultMap = try {
                    // 앱이 이미 취소한 동영상은 건너뜀
                    if (job.isCancelled(idx)) throw com.rnattachmentkit.VideoExporter.CancelledException()
                    job.begin(idx, exporter)
                    val state = lastVideoEditStates[uri.toString()] ?: com.rnattachmentkit.VideoEditState(qualityHeight = videoOptions.defaultQuality)
                    val throttle = com.rnattachmentkit.ProgressThrottle()
                    val onProgress: (Float) -> Unit = { p ->
                        hud?.let { h -> android.os.Handler(android.os.Looper.getMainLooper()).post { h.update(p, idx, totalCount) } }
                        if (throttle.shouldSend(p)) emitGalleryEvent("onVideoProgress", Arguments.createMap().apply {
                            putInt("index", idx); putInt("total", totalCount); putDouble("progress", p.toDouble())
                            putString("processingId", processingId)
                        })
                    }
                    // 편집 화면에서 미리 만들어 둔 파일이 있으면(또는 만드는 중이면 끝나고) 그대로 씀
                    // 기다리는 동안 앱(X)이나 HUD 가 취소하면 바로 멈춤 (전엔 미리 만들기가 끝날 때까지 못 빠져나왔음)
                    val stop = { videoCancelled || job.isCancelled(idx) }
                    val res = com.rnattachmentkit.VideoPrepareManager.takeReady(uri, state, onProgress, stop)
                        ?: run {
                            if (stop()) throw com.rnattachmentkit.VideoExporter.CancelledException()
                            exporter.export(uri, state, videoOptions, reactApplicationContext.cacheDir, "turbo_video_${System.currentTimeMillis()}_$idx", onProgress)
                        }
                    withContext(Dispatchers.Main) { hud?.update(1f, idx, totalCount) }
                    // 미리 만든 파일을 기다리는 동안 취소됐으면 결과를 쓰지 않음
                    if (job.isCancelled(idx)) throw com.rnattachmentkit.VideoExporter.CancelledException()
                    videoFiles += res.file
                    res.thumbnailFile?.let { videoFiles += it }
                    WritableNativeMap().apply {
                        putString("uri", Uri.fromFile(res.file).toString())
                        putString("originalUri", uri.toString())
                        putString("mediaType", "video")
                        putString("type", "video/mp4")
                        putInt("width", res.width)
                        putInt("height", res.height)
                        putDouble("duration", res.durationMs / 1000.0)
                        putDouble("fileSize", res.fileSize.toDouble())
                        putString("fileName", res.file.name)
                        putString("fileExtension", "mp4")
                        putString("videoCodec", res.codec)
                        putInt("videoBitrate", res.bitrate)
                        putBoolean("edited", res.edited)
                        if (res.thumbnailFile != null) {
                            putString("thumbnailUri", Uri.fromFile(res.thumbnailFile).toString())
                            putInt("thumbnailWidth", res.thumbnailWidth)
                            putInt("thumbnailHeight", res.thumbnailHeight)
                        }
                    }
                } catch (e: com.rnattachmentkit.VideoExporter.CancelledException) {
                    // 앱이 이 동영상만 취소 → 나머지는 계속. HUD 취소면 전체 취소
                    if (job.isCancelled(idx) && !videoCancelled) cancelledMap() else throw e
                } catch (e: Exception) {
                    // 취소하면서 변환기가 다른 예외로 끝날 수도 있음 → 취소로 처리
                    if (job.isCancelled(idx) && !videoCancelled) cancelledMap() else {
                        android.util.Log.w("RNAttachmentKit", "video export failed: ${e.message}", e)
                        WritableNativeMap().apply {
                            putString("originalUri", uri.toString())
                            putString("mediaType", "video")
                            putString("error", e.message ?: "export failed")
                        }
                    }
                } finally {
                    currentVideoExporter = null
                    job.end()
                }
                results.add(resultMap)
                try {
                    val copy = WritableNativeMap().apply { merge(resultMap) }
                    reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                        .emit("onImageProcessed", WritableNativeMap().apply {
                            putInt("total", totalCount); putInt("index", idx); putMap("image", copy)
                            putString("processingId", processingId)
                        })
                } catch (_: Exception) {}
                currentIndex++
                continue
            }
            try {
                // 1. Get EXIF Orientation
                var orientation = android.media.ExifInterface.ORIENTATION_NORMAL
                try {
                    contentResolver.openInputStream(uri)?.use { exifInputStream ->
                        val exif = android.media.ExifInterface(exifInputStream)
                        orientation = exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)
                    }
                } catch (e: Exception) {}

                contentResolver.openInputStream(uri)?.use { inputStream ->
                    // Get original image dimensions
                    val originalOptions = BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    BitmapFactory.decodeStream(inputStream, null, originalOptions)
                    
                    var originalWidth = originalOptions.outWidth
                    var originalHeight = originalOptions.outHeight
                    
                    // Swap width and height if rotated by 90 or 270 degrees
                    if (orientation == android.media.ExifInterface.ORIENTATION_ROTATE_90 || orientation == android.media.ExifInterface.ORIENTATION_ROTATE_270) {
                        val temp = originalWidth
                        originalWidth = originalHeight
                        originalHeight = temp
                    }
                    
                    // Load and resize image
                    contentResolver.openInputStream(uri)?.use { resizedInputStream ->
                        // Initial decode for sizing
                        val decodeOptions = BitmapFactory.Options().apply {
                            inSampleSize = calculateInSampleSize(originalWidth, originalHeight, maxWidth, maxHeight)
                        }
                        var bitmap = BitmapFactory.decodeStream(resizedInputStream, null, decodeOptions)
                        
                        if (bitmap != null) {
                            // Apply EXIF Rotation
                            val matrix = android.graphics.Matrix()
                            when (orientation) {
                                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                                android.media.ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                                android.media.ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                            }
                            
                            if (!matrix.isIdentity) {
                                val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                                if (rotatedBitmap != bitmap) {
                                    bitmap.recycle()
                                    bitmap = rotatedBitmap
                                }
                            }

                            // Precise resize if needed
                            val finalBitmap = if (bitmap.width > maxWidth || bitmap.height > maxHeight) {
                                resizeBitmap(bitmap, maxWidth, maxHeight)
                            } else {
                                bitmap
                            }
                            
                            val processedBitmap = ImageProcessor.applyWatermarkIfNeeded(reactApplicationContext, finalBitmap)
                            
                            // Determine format and extension
                            val compressFormat: Bitmap.CompressFormat
                            val extension: String
                            val mimeType: String
                            
                            when (outputFormat) {
                                "png" -> {
                                    compressFormat = Bitmap.CompressFormat.PNG
                                    extension = "png"
                                    mimeType = "image/png"
                                }
                                "jpg", "jpeg" -> {
                                    compressFormat = Bitmap.CompressFormat.JPEG
                                    extension = "jpg"
                                    mimeType = "image/jpeg"
                                }
                                else -> { // webp
                                    compressFormat = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                        Bitmap.CompressFormat.WEBP_LOSSY
                                    } else {
                                        @Suppress("DEPRECATION")
                                        Bitmap.CompressFormat.WEBP
                                    }
                                    extension = "webp"
                                    mimeType = "image/webp"
                                }
                            }

                            // Save to temporary file
                            val tempFile = File.createTempFile("turbo_edited_${System.currentTimeMillis()}_", ".$extension", reactApplicationContext.cacheDir)
                            FileOutputStream(tempFile).use { out ->
                                processedBitmap.compress(compressFormat, 85, out)
                            }
                            // 썸네일: 같은 비트맵(방향·크롭·그리기 반영)에서 — 원본을 다시 읽지 않음
                            val thumb = thumbnailOptions?.let {
                                com.rnattachmentkit.PhotoThumbnail.make(processedBitmap, it, reactApplicationContext.cacheDir, currentIndex)
                            }
                            
                            val finalWidth = processedBitmap.width
                            val finalHeight = processedBitmap.height

                            // Cleanup
                            if (bitmap != processedBitmap) {
                                bitmap.recycle()
                            }
                            if (finalBitmap != processedBitmap && finalBitmap != bitmap) {
                                finalBitmap.recycle()
                            }
                            processedBitmap.recycle()
                            
                            val createImageInfo = {
                                WritableNativeMap().apply {
                                    putString("uri", Uri.fromFile(tempFile).toString())
                                    putInt("width", finalWidth)
                                    putInt("height", finalHeight)
                                    putString("type", mimeType)
                                    putString("fileName", tempFile.name)
                                    putString("fileExtension", extension)
                                    putDouble("fileSize", tempFile.length().toDouble())
                                    putString("originalUri", uri.toString())
                                    putInt("originalWidth", originalWidth)
                                    putInt("originalHeight", originalHeight)
                                    if (thumb != null) {
                                        putString("thumbnailUri", Uri.fromFile(thumb.file).toString())
                                        putInt("thumbnailWidth", thumb.width)
                                        putInt("thumbnailHeight", thumb.height)
                                        putDouble("thumbnailFileSize", thumb.fileSize.toDouble())
                                    }
                                }
                            }
                            val imageInfo = createImageInfo()
                            results.add(imageInfo)

                            try {
                                val eventMap = WritableNativeMap().apply {
                                    putInt("total", totalCount)
                                    putInt("index", currentIndex)
                                    putString("processingId", processingId)
                                    putMap("image", createImageInfo())
                                }
                                reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                                    .emit("onImageProcessed", eventMap)
                            } catch (e: Exception) { }
                        }
                    }
                }
                currentIndex++
            } catch (e: Exception) {
                currentIndex++
                // Skip failed images
                continue
            }
        }
        } catch (e: com.rnattachmentkit.VideoExporter.CancelledException) {
            // 취소: 지금까지 만든 동영상 파일은 지움
            videoFiles.forEach { try { it.delete() } catch (_: Exception) {} }
            throw e
        } finally {
            activeProcessingJobs.remove(processingId)
            if (hud != null) withContext(Dispatchers.Main) { hud?.dismiss() }
        }

        results
    }
    
    private fun calculateInSampleSize(
        reqWidth: Int,
        reqHeight: Int,
        maxWidth: Int,
        maxHeight: Int
    ): Int {
        var inSampleSize = 1
        
        if (reqHeight > maxHeight || reqWidth > maxWidth) {
            val halfHeight = reqHeight / 2
            val halfWidth = reqWidth / 2
            
            while ((halfHeight / inSampleSize) >= maxHeight && (halfWidth / inSampleSize) >= maxWidth) {
                inSampleSize *= 2
            }
        }
        
        return inSampleSize
    }
    
    private fun resizeBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        
        val ratioBitmap = width.toFloat() / height.toFloat()
        val ratioMax = maxWidth.toFloat() / maxHeight.toFloat()
        
        var finalWidth = maxWidth
        var finalHeight = maxHeight
        
        if (ratioMax > ratioBitmap) {
            finalWidth = (maxHeight * ratioBitmap).toInt()
        } else {
            finalHeight = (maxWidth / ratioBitmap).toInt()
        }
        
        return Bitmap.createScaledBitmap(bitmap, finalWidth, finalHeight, true)
    }


    // MARK: - Media gallery (사진 모아보기)

    /** 열려 있는 미디어 갤러리 (galleryId → 화면). 메인 스레드에서만 접근 */
    private val mediaGalleries = HashMap<String, MediaGalleryOverlay>()

    private fun emitGalleryEvent(name: String, body: WritableMap) {
        try {
            reactApplicationContext
                .getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit(name, body)
        } catch (e: Exception) {
            android.util.Log.w("TurboMediaGallery", "emit $name failed", e)
        }
    }

    /**
     * openMediaGallery(options) → { galleryId }
     * - dataSource: 등록된 네이티브 데이터 소스 이름 (MediaGalleryRegistry) — 페이지 요청이 JS 를 거치지 않음
     * - initialItems / nextCursor / hasMore: JS 공급 방식 (끝에 가까우면 onGalleryNeedPage → appendGalleryItems)
     * Activity 를 띄우지 않고 호스트 Activity 위에 View 로 얹습니다.
     */
    @ReactMethod
    fun openMediaGallery(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }
        val o: Map<String, Any?> = options.toHashMap()
        // 동영상 항목은 라이선스 키가 있어야
        if (!LicenseGate.isLicensed && MediaGalleryItem.listFrom(o["items"]).any { it.isVideo }) {
            promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return
        }
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            try {
                val systemDark = (activity.resources.configuration.uiMode and
                    android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
                val config = MediaGalleryConfig(o, systemDark)
                val galleryId = config.galleryId
                if (mediaGalleries[galleryId]?.isShowing == true) {
                    promise.reject("E_GALLERY_OPEN", "Media gallery '$galleryId' is already open")
                    return@runOnUiThread
                }
                MediaGalleryRegistry.ensureDemo(activity.applicationContext)
                val dataSourceName = o["dataSource"] as? String
                val store: MediaGalleryStore
                if (!dataSourceName.isNullOrEmpty()) {
                    val dataSource = MediaGalleryRegistry.source(dataSourceName)
                    if (dataSource == null) {
                        promise.reject("E_NO_DATA_SOURCE", "Media gallery data source '$dataSourceName' is not registered")
                        return@runOnUiThread
                    }
                    @Suppress("UNCHECKED_CAST")
                    val params = (o["dataSourceParams"] as? Map<String, Any?>) ?: emptyMap()
                    store = MediaGalleryStore(galleryId, MediaGalleryStore.Source.Native(dataSource, params))
                } else {
                    store = MediaGalleryStore(
                        galleryId,
                        MediaGalleryStore.Source.JavaScript,
                        MediaGalleryItem.listFrom(o["initialItems"]),
                        o["nextCursor"] as? String,
                        o["hasMore"] as? Boolean ?: false
                    )
                    store.onNeedPage = { cursor ->
                        emitGalleryEvent("onGalleryNeedPage", Arguments.createMap().apply {
                            putString("galleryId", galleryId)
                            if (cursor != null) putString("cursor", cursor) else putNull("cursor")
                        })
                    }
                }
                val overlay = MediaGalleryOverlay(activity, store, config)
                overlay.onClosed = {
                    if (mediaGalleries[galleryId] === overlay) mediaGalleries.remove(galleryId)
                    emitGalleryEvent("onGalleryClosed", Arguments.createMap().apply { putString("galleryId", galleryId) })
                }
                // 뷰어에서 삭제를 고르면: 모듈은 그 묶음을 그리드·뷰어에서 지우고, 실제 삭제는 앱이 하도록 이벤트만 보냄
                overlay.onItemDeleted = { item, option ->
                    emitGalleryEvent("onGalleryItemDeleted", Arguments.createMap().apply {
                        putString("galleryId", galleryId)
                        putString("id", item.id)
                        putString("groupId", item.groupId)
                        if (option != null) putString("option", option) else putNull("option")
                    })
                }
                // 상단 바 메뉴에서 그리드 크기를 바꾸면 (모듈이 기기에 저장, 앱에도 알림)
                overlay.onGridSizeChanged = { columns ->
                    emitGalleryEvent("onGalleryGridSizeChanged", Arguments.createMap().apply {
                        putString("galleryId", galleryId)
                        putString("gridSize", MediaGalleryGridPreference.gridSizeString(columns))
                    })
                }
                mediaGalleries[galleryId] = overlay
                overlay.show()
                promise.resolve(Arguments.createMap().apply { putString("galleryId", galleryId) })
            } catch (e: Exception) {
                promise.reject("E_MEDIA_GALLERY", "Failed to open media gallery: ${e.message}", e)
            }
        }
    }

    @ReactMethod
    fun closeMediaGallery(galleryId: String, promise: Promise) {
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            mediaGalleries[galleryId]?.close(includeViewer = true)
            promise.resolve(null)
        }
    }

    /** JS 공급 방식: { galleryId, items, nextCursor?, hasMore } */
    @ReactMethod
    fun appendGalleryItems(payload: ReadableMap, promise: Promise) {
        val p: Map<String, Any?> = payload.toHashMap()
        val galleryId = p["galleryId"] as? String ?: ""
        val page = MediaGalleryPage(
            MediaGalleryItem.listFrom(p["items"]),
            p["nextCursor"] as? String,
            p["hasMore"] as? Boolean ?: false
        )
        if (!LicenseGate.isLicensed && page.items.any { it.isVideo }) {
            promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return
        }
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            mediaGalleries[galleryId]?.store?.appendExternal(page)
            promise.resolve(null)
        }
    }

    /** 앱이 다른 경로로 지운 묶음 반영: { galleryId, groupIds } */
    @ReactMethod
    fun removeGalleryItems(payload: ReadableMap, promise: Promise) {
        val p: Map<String, Any?> = payload.toHashMap()
        val galleryId = p["galleryId"] as? String ?: ""
        val groupIds = (p["groupIds"] as? List<*> ?: emptyList<Any?>()).mapNotNull { v ->
            when (v) {
                is String -> v
                is Number -> v.toDouble().let { d -> if (d % 1.0 == 0.0) d.toLong().toString() else d.toString() }
                else -> null
            }
        }.toSet()
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            mediaGalleries[galleryId]?.store?.removeGroups(groupIds)
            promise.resolve(null)
        }
    }

    override fun invalidate() {
        super.invalidate()
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            val open = mediaGalleries.values.toList()
            mediaGalleries.clear()
            open.forEach { it.dismissImmediately() }
        }
        reactApplicationContext.removeActivityEventListener(this)
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactApplicationContext)
            .unregisterReceiver(viewerOpenedReceiver)
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(reactApplicationContext)
            .unregisterReceiver(imageDeletedReceiver)
    }

    // ── 지도 뷰어 (위치 메시지 → 지도) ──

    private var mapViewer: java.lang.ref.WeakReference<MapViewerDialogFragment>? = null
    /** updateMapViewerSourceRect 로 갱신되는 닫힘 위치 (화면 px) */
    @Volatile private var mapViewerSourceRect: android.graphics.Rect? = null

    /** RN measureInWindow 값(dp, 창 기준) → 화면 px Rect */
    private fun mapRectFromDp(map: ReadableMap?, activity: Activity): android.graphics.Rect? {
        if (map == null || !map.hasKey("x") || !map.hasKey("y") || !map.hasKey("width") || !map.hasKey("height")) return null
        val w = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(map.getDouble("width").toFloat())
        val h = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(map.getDouble("height").toFloat())
        if (w <= 0f || h <= 0f) return null
        val loc = IntArray(2)
        try { activity.window?.decorView?.getLocationOnScreen(loc) } catch (_: Exception) {}
        val x = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(map.getDouble("x").toFloat()) + loc[0]
        val y = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(map.getDouble("y").toFloat()) + loc[1]
        return android.graphics.Rect(Math.round(x), Math.round(y), Math.round(x + w), Math.round(y + h))
    }

    /** 말풍선 이미지 → 로컬 파일 경로. file:// 는 그대로, http(s) 는 Glide 캐시 파일. 실패·지연 시 null (이미지 없이 엶) */
    private fun mapSourceImagePath(uri: String?): String? {
        if (uri.isNullOrBlank()) return null
        if (uri.startsWith("/")) return uri.takeIf { File(it).exists() }
        if (uri.startsWith("file://")) return Uri.parse(uri).path?.takeIf { File(it).exists() }
        if (!uri.startsWith("http://") && !uri.startsWith("https://")) return null
        return try {
            com.bumptech.glide.Glide.with(reactApplicationContext.applicationContext)
                .downloadOnly().load(uri).submit()
                .get(1500, java.util.concurrent.TimeUnit.MILLISECONDS)
                ?.absolutePath
        } catch (e: Exception) {
            android.util.Log.w("RNAttachmentKit", "openMapViewer: source image not loaded (${e.javaClass.simpleName})")
            null
        }
    }

    @ReactMethod
    fun openMapViewer(options: ReadableMap, promise: Promise) {
        // 위치 기능은 라이선스 키가 있어야
        if (!LicenseGate.isLicensed) { promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return }
        val activity = getCurrentActivity() as? FragmentActivity
        if (activity == null) {
            promise.reject("NO_ACTIVITY", "Activity is not a FragmentActivity")
            return
        }
        if (!options.hasKey("latitude") || !options.hasKey("longitude")) {
            promise.reject("ERROR", "latitude and longitude are required")
            return
        }
        fun str(key: String) = if (options.hasKey(key) && !options.isNull(key)) options.getString(key) else null
        fun num(key: String) = if (options.hasKey(key) && !options.isNull(key)) options.getDouble(key) else null
        val lat = options.getDouble("latitude")
        val lng = options.getDouble("longitude")
        val rect = mapRectFromDp(if (options.hasKey("sourceRect") && !options.isNull("sourceRect")) options.getMap("sourceRect") else null, activity)
        val imageUri = str("sourceImageUri")
        val themeColor = str("themeColor")?.let { try { android.graphics.Color.parseColor(it) } catch (_: Exception) { null } }
        val radiusPx = com.facebook.react.uimanager.PixelUtil.toPixelFromDIP((num("sourceCornerRadius") ?: 12.0).toFloat())
        val showDirections = if (options.hasKey("showDirections") && !options.isNull("showDirections")) options.getBoolean("showDirections") else true

        CoroutineScope(Dispatchers.IO).launch {
            val imagePath = if (rect != null) mapSourceImagePath(imageUri) else null
            withContext(Dispatchers.Main) {
                if (activity.isFinishing || activity.isDestroyed || activity.supportFragmentManager.isStateSaved) {
                    promise.reject("ERROR", "Activity is not available")
                    return@withContext
                }
                try {
                    mapViewerSourceRect = rect
                    val f = MapViewerDialogFragment.show(
                        activity, lat, lng,
                        title = str("title"),
                        address = str("address"),
                        markerType = str("markerType"),
                        themeColor = themeColor,
                        languageCode = str("languageCode") ?: "en",
                        showDirections = showDirections,
                        sourceRect = rect,
                        sourceImagePath = imagePath,
                        sourceCornerRadius = radiusPx,
                        spanMeters = num("spanMeters") ?: 0.0,
                        appearance = str("appearance"),
                        addressLanguageCode = str("addressLanguageCode"),
                    )
                    if (rect != null) f.sourceRectProvider = { mapViewerSourceRect }
                    var settled = false
                    f.onWillClose = { ms ->
                        try {
                            reactApplicationContext
                                .getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                                .emit("onMapViewerWillClose", com.facebook.react.bridge.Arguments.createMap().apply { putInt("durationMs", ms) })
                        } catch (_: Exception) {}
                    }
                    f.onClosed = {
                        if (!settled) { settled = true; promise.resolve(null) }
                        mapViewerSourceRect = null
                        mapViewer = null
                    }
                    mapViewer = java.lang.ref.WeakReference(f)
                } catch (e: Exception) {
                    promise.reject("ERROR", e.message, e)
                }
            }
        }
    }

    @ReactMethod
    fun updateMapViewerSourceRect(rect: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        if (mapViewer?.get() != null && activity != null) mapViewerSourceRect = mapRectFromDp(rect, activity)
        promise.resolve(null)
    }

    /**
     * 위치 메시지 지도 썸네일을 이 기기에서 그림 (테마별 캐시). 결과 { uri, path, width, height(px), cached }
     * options: latitude, longitude, width, height (dp, 필수) / markerType, placeCategory, spanMeters, themeColor,
     *          appearance ("light"/"dark"/"system"), myLatitude + myLongitude (둘 다 있을 때만)
     * aspect ("square" | "portrait" | "device"): 주면 width 만 필수, height 는 비율로 (square = 1:1,
     *          portrait = 480:1040 보내던 이미지와 같은 9:19.5, device = 실제 화면 긴 변/짧은 변). 모르는 값이면 없는 것과 같음
     * maxWidth / maxHeight (px, 기본 512, 0 이하면 무시): 출력 WebP 가 이 안에 들어가게 비율대로 줄임
     *          (k = min(density, maxWidth / widthDp, maxHeight / heightDp)) → 결과 width/height 는 출력 px
     */
    @ReactMethod
    fun renderLocationThumbnail(options: ReadableMap, promise: Promise) {
        // 위치 기능은 라이선스 키가 있어야
        if (!LicenseGate.isLicensed) { promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return }
        fun str(key: String) = if (options.hasKey(key) && !options.isNull(key)) options.getString(key) else null
        fun num(key: String) = if (options.hasKey(key) && !options.isNull(key)) options.getDouble(key) else null
        val lat = num("latitude")
        val lng = num("longitude")
        val wDp = num("width")
        val activity = getCurrentActivity()
        val aspectRatio: Double? = when (str("aspect")?.lowercase()) {
            "square" -> 1.0
            "portrait" -> 1040.0 / 480.0
            "device" -> {
                // 실제 화면 크기 (세로 기준: 긴 변 / 짧은 변 → h > w)
                val dm = (activity ?: reactApplicationContext).resources.displayMetrics
                var sw = dm.widthPixels; var sh = dm.heightPixels
                if (activity != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    try {
                        val b = activity.windowManager.currentWindowMetrics.bounds
                        if (b.width() > 0 && b.height() > 0) { sw = b.width(); sh = b.height() }
                    } catch (_: Exception) {}
                }
                val lo = minOf(sw, sh); val hi = maxOf(sw, sh)
                if (lo > 0) hi.toDouble() / lo else 19.5 / 9.0
            }
            else -> null
        }
        val hDp = if (aspectRatio != null) wDp?.let { it * aspectRatio } else num("height")
        if (lat == null || lng == null || wDp == null || hDp == null || wDp <= 0 || hDp <= 0 ||
            lat.isNaN() || lng.isNaN()) {
            promise.reject("E_INVALID_ARGS", "latitude, longitude, width, height (> 0) are required")
            return
        }
        val myLat = num("myLatitude")
        val myLng = num("myLongitude")
        if ((myLat == null) != (myLng == null)) {
            promise.reject("E_INVALID_ARGS", "myLatitude and myLongitude must be given together")
            return
        }
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }
        val accent = str("themeColor")?.let { try { android.graphics.Color.parseColor(it) } catch (_: Exception) { null } }
            ?: android.graphics.Color.parseColor("#FF6B35")
        val dark = when (str("appearance")?.lowercase()) {
            "dark" -> true
            "light" -> false
            else -> (activity.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
        }
        val wPx = Math.round(com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(wDp.toFloat())).coerceAtLeast(1)
        val hPx = Math.round(com.facebook.react.uimanager.PixelUtil.toPixelFromDIP(hDp.toFloat())).coerceAtLeast(1)
        val maxOutW = num("maxWidth")?.takeIf { it > 0 }?.let { Math.round(it).toInt() }
        val maxOutH = num("maxHeight")?.takeIf { it > 0 }?.let { Math.round(it).toInt() }
        val req = LocationThumbnailRenderer.Request(
            lat = lat, lng = lng, widthPx = wPx, heightPx = hPx,
            density = activity.resources.displayMetrics.density,
            dark = dark,
            markerType = str("markerType"),
            placeCategory = str("placeCategory"),
            spanMeters = num("spanMeters"),
            accent = accent,
            myLat = myLat, myLng = myLng,
            // 출력 최대 크기 (0 이하·없음 → 기본 512)
            // 결과 최대 크기 (px). 둘 다 없으면 512 × 512, 하나만 주면 다른 쪽은 제한 없음(0)
            maxOutWidthPx = maxOutW ?: if (maxOutH != null) 0 else LocationThumbnailRenderer.DEFAULT_MAX_OUT_PX,
            maxOutHeightPx = maxOutH ?: if (maxOutW != null) 0 else LocationThumbnailRenderer.DEFAULT_MAX_OUT_PX,
        )
        com.facebook.react.bridge.UiThreadUtil.runOnUiThread {
            try {
                LocationThumbnailRenderer.render(activity, req) { r ->
                    r.fold(
                        onSuccess = { m ->
                            val body = Arguments.createMap()
                            body.putString("uri", m["uri"] as? String)
                            body.putString("path", m["path"] as? String)
                            body.putInt("width", (m["width"] as? Int) ?: wPx)
                            body.putInt("height", (m["height"] as? Int) ?: hPx)
                            body.putBoolean("cached", (m["cached"] as? Boolean) ?: false)
                            promise.resolve(body)
                        },
                        onFailure = { e -> promise.reject("E_THUMBNAIL_FAILED", e.message ?: "Thumbnail render failed", e) }
                    )
                }
            } catch (e: Exception) {
                promise.reject("E_THUMBNAIL_FAILED", e.message ?: "Thumbnail render failed", e)
            }
        }
    }

    /** 지도 썸네일 캐시 비우기 */
    @ReactMethod
    fun clearLocationThumbnailCache(promise: Promise) {
        CoroutineScope(Dispatchers.IO).launch {
            try { LocationThumbnailRenderer.clearCache(reactApplicationContext) } catch (_: Exception) {}
            promise.resolve(null)
        }
    }

    // ── AI 기능 설정·잔액 (넘긴 값만 바뀜). 사용·충전 요청은 onAIUsage / onAIChargeRequired 이벤트로 알림 ──

    @ReactMethod
    fun setAIConfig(config: ReadableMap, promise: Promise) {
        // 라이선스 키가 없어도 설정은 받아 둠 (AI 버튼은 보이고, 누르면 "라이선스 필요" 안내)
        if (!LicenseGate.isLicensed && config.hasKey("enabled") && !config.isNull("enabled") && config.getBoolean("enabled")) {
            android.util.Log.w("RNAttachmentKit", "AI needs a license key — the AI buttons show a license notice until init() gets a valid key")
        }
        AIBilling.apply(config.toHashMap())
        val ctx = reactApplicationContext
        fun emit(name: String, body: Map<String, Any>) {
            // 앱이 내려가는 중이면 조용히 무시
            runCatching {
                ctx.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    .emit(name, com.facebook.react.bridge.Arguments.makeNativeMap(body))
            }
        }
        AIBilling.onUsage = { emit("onAIUsage", it) }
        AIBilling.onChargeRequired = { emit("onAIChargeRequired", it) }
        promise.resolve(null)
    }

    // ── 역지오코딩 (기기 Geocoder, 디스크 캐시) ──

    @ReactMethod
    fun reverseGeocode(options: ReadableMap, promise: Promise) {
        // 위치 기능은 라이선스 키가 있어야
        if (!LicenseGate.isLicensed) { promise.reject(LicenseGate.ERROR_CODE, LicenseGate.ERROR_MESSAGE); return }
        val lat = if (options.hasKey("latitude") && !options.isNull("latitude")) options.getDouble("latitude") else Double.NaN
        val lng = if (options.hasKey("longitude") && !options.isNull("longitude")) options.getDouble("longitude") else Double.NaN
        val lang = if (options.hasKey("languageCode") && !options.isNull("languageCode")) options.getString("languageCode") else null
        ReverseGeocoder.reverseGeocode(reactApplicationContext, lat, lng, lang) { r, e ->
            if (r != null) {
                val map = Arguments.createMap()
                r.address?.let { map.putString("address", it) } ?: map.putNull("address")
                r.shortAddress?.let { map.putString("shortAddress", it) } ?: map.putNull("shortAddress")
                map.putBoolean("cached", r.cached)
                promise.resolve(map)
            } else {
                promise.reject(e?.code ?: "E_GEOCODE_FAILED", e?.message ?: "Reverse geocoding failed")
            }
        }
    }

    @ReactMethod
    fun clearReverseGeocodeCache(promise: Promise) {
        CoroutineScope(Dispatchers.IO).launch {
            try { ReverseGeocoder.clearCache(reactApplicationContext) } catch (_: Exception) {}
            promise.resolve(null)
        }
    }
}
