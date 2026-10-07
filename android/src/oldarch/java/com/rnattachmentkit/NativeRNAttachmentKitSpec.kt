package com.rnattachmentkit.rn

import com.rnattachmentkit.*

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReadableMap

abstract class NativeRNAttachmentKitSpec(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    abstract fun init(licenseKey: String, promise: Promise)
    abstract fun openGallery(options: ReadableMap, promise: Promise)
    abstract fun openViewer(options: ReadableMap, promise: Promise)
    abstract fun openEditor(options: ReadableMap, promise: Promise)
    abstract fun updateViewerSourceRect(rect: ReadableMap, promise: Promise)
    abstract fun closeGallery(promise: Promise)
}
