package com.rnattachmentkit

import com.rnattachmentkit.*

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class RNAttachmentKitPackage : TurboReactPackage() {
    
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return if (name == RNAttachmentKitModule.NAME) {
            RNAttachmentKitModule(reactContext)
        } else {
            null
        }
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            mapOf(
                RNAttachmentKitModule.NAME to ReactModuleInfo(
                    RNAttachmentKitModule.NAME,
                    "com.rnattachmentkit.RNAttachmentKitModule",
                    false, // canOverrideExistingModule
                    false, // needsEagerInit
                    false, // hasConstants
                    false, // isCxxModule
                    true   // isTurboModule
                )
            )
        }
    }
}

