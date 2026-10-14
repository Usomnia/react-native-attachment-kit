//
//  RNAttachmentKit.swift
//  RNAttachmentKit
//
//  Supports both Turbo Module (New Architecture) and Legacy Native Module
//

import UIKit
import Photos
import ImageIO
import CoreLocation
import RNAttachmentKit

#if RCT_NEW_ARCH_ENABLED
import React
#else
import React
#endif

#if canImport(SDWebImageWebPCoder)
import SDWebImageWebPCoder
#endif

@objc(RNAttachmentKit)
class RNAttachmentKit: RCTEventEmitter {

    /// RN 옵션 appearance: "light" | "dark" | "system"(기본, 생략) → 화면 강제 모드.
    /// "system" 이면 기기 설정을 따릅니다 (.unspecified).
    static func interfaceStyle(_ options: NSDictionary?) -> UIUserInterfaceStyle {
        switch (options?["appearance"] as? String)?.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return .unspecified
        }
    }
    
    public static var shared: RNAttachmentKit?
    
    private var zoomAnimator = ZoomTransitionAnimator()
    private weak var activeViewerVC: RemoteImageViewerViewController?
    
    override init() {
        super.init()
        RNAttachmentKit.shared = self
    }
    
    // 현재 표시 중인 갤러리 참조
    private weak var currentGalleryVC: GalleryViewController?
    private var editorTransitionDelegate: ImageEditorTransitionDelegate?
    /// 열려 있는 미디어 갤러리 (galleryId → 화면)
    fileprivate var mediaGalleries: [String: MediaGalleryViewController] = [:]
    /// 진행 중인 전송 처리 (processingId → 작업, 메인 스레드에서만). 보내는 중에 갤러리를 다시 열어 또 보낼 수 있어 여러 개일 수 있음
    private var processingJobs: [String: MediaProcessingJob] = [:]
    /// 가장 최근에 시작한 처리 (cancelVideoProcessing 에 processingId 가 없을 때)
    private var lastProcessingId: String?
    /// 동영상 변환 진행 HUD 를 띄울지 — video.showProgressHUD, 없으면 asyncProcessing 이 아닐 때만
    /// (앱이 onProcessingStart / onVideoProgress / onImageProcessed 로 말풍선에 진행 상황을 그리는 구조면 HUD 없이)
    private var galleryShowsVideoHUD = true
    
    // MARK: - Module Setup
    
    @objc
    override static func moduleName() -> String! {
        return "RNAttachmentKit"
    }
    
    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc
    override func supportedEvents() -> [String]! {
        return ["onSelectionChange", "onImageProcessed", "onPageSelected", "onViewerWillClose", "onImageDeleted",
                "onGalleryItemDeleted", "onGalleryNeedPage", "onGalleryClosed", "onGalleryGridSizeChanged",
                "onLocationSelected", "onFilesSelected", "onAIUsage", "onAIChargeRequired", "onVideoProgress",
                "onMapViewerWillClose", "onProcessingStart"]
    }
    
    // MARK: - Public Methods

    static let defaultAnimationConfig: [String: Double] = [
        "galleryOpen": 300.0,
        "galleryClose": 250.0,
        "editorOpen": 350.0,
        "editorClose": 350.0,
        "viewerOpen": 370.0,
        "viewerClose": 370.0
    ]
    
    @objc
    func getDefaultAnimationConfig(_ resolve: @escaping RCTPromiseResolveBlock,
                                   reject: @escaping RCTPromiseRejectBlock) -> Void {
        resolve(RNAttachmentKit.defaultAnimationConfig)
    }

    
    @objc
    func `init`(_ licenseKey: String,
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) -> Void {
        let result = LicenseManager.shared.initialize(with: licenseKey)
        resolve(result)
    }
    
    // MARK: - Public Methods
    
    @objc
    func injectImageCache(_ urlString: String, localPath: String,
                          resolve: @escaping RCTPromiseResolveBlock,
                          reject: @escaping RCTPromiseRejectBlock) -> Void {
        if ViewerImageCache.shared.hasCache(for: urlString) {
            resolve(true)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // localPath might be a file:// URI or raw path
            var path = localPath
            if path.hasPrefix("file://") {
                path = path.replacingOccurrences(of: "file://", with: "")
            }
            if let image = UIImage(contentsOfFile: path) {
                if #available(iOS 15.0, *) {
                    image.prepareForDisplay { preparedImage in
                        let finalImage = preparedImage ?? image
                        ViewerImageCache.shared.saveImage(finalImage, for: urlString)
                        resolve(true)
                    }
                } else {
                    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
                    image.draw(at: .zero)
                    let decodedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                    UIGraphicsEndImageContext()
                    ViewerImageCache.shared.saveImage(decodedImage, for: urlString)
                    resolve(true)
                }
            } else {
                reject("ERROR", "Failed to load image from local path", nil)
            }
        }
    }

    @objc
    func updateSourceRect(_ options: NSDictionary,
                          resolve: @escaping RCTPromiseResolveBlock,
                          reject: @escaping RCTPromiseRejectBlock) -> Void {
        let optDict = options as? [String: Any] ?? [:]
        let x = (optDict["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["x"] as? Double).map { CGFloat($0) }
        let y = (optDict["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["y"] as? Double).map { CGFloat($0) }
        let w = (optDict["width"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["width"] as? Double).map { CGFloat($0) }
        let h = (optDict["height"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["height"] as? Double).map { CGFloat($0) }
        
        if let x = x, let y = y, let w = w, let h = h {
            DispatchQueue.main.async {
                self.zoomAnimator.sourceRect = CGRect(x: x, y: y, width: w, height: h)
                
                var mask: CACornerMask = []
                if let corners = optDict["sourceBorderCorners"] as? [String] {
                    if corners.contains("topLeft") { mask.insert(.layerMinXMinYCorner) }
                    if corners.contains("topRight") { mask.insert(.layerMaxXMinYCorner) }
                    if corners.contains("bottomLeft") { mask.insert(.layerMinXMaxYCorner) }
                    if corners.contains("bottomRight") { mask.insert(.layerMaxXMaxYCorner) }
                } else {
                    mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                }
                self.zoomAnimator.sourceBorderCorners = mask
                // 넘긴 사진 자리의 라운드 값도 갱신 (예: 원형 대표 사진 → 둥근 사각 카드).
                // 이전에는 처음 연 사진의 라운드가 그대로 남아, 다른 모양의 자리로 닫힐 때 모양이 틀어졌음.
                if let r = optDict["sourceBorderRadius"] as? NSNumber {
                    self.zoomAnimator.sourceBorderRadius = CGFloat(truncating: r)
                } else if let r = optDict["sourceBorderRadius"] as? Double {
                    self.zoomAnimator.sourceBorderRadius = CGFloat(r)
                }
                self.zoomAnimator.updateMaskView()
                
                resolve(true)
            }
        } else {
            reject("ERROR", "Invalid coordinates", nil)
        }
    }
    
    // MARK: - Map Viewer (위치 메시지 → 지도)

    private weak var activeMapViewerVC: MapViewerViewController?
    /// updateMapViewerSourceRect 로 갱신되는 닫힘 위치 (window points)
    private var mapViewerSourceRect: CGRect?

    private static func cgFloat(_ v: Any?) -> CGFloat? {
        if let n = v as? NSNumber { return CGFloat(truncating: n) }
        if let d = v as? Double { return CGFloat(d) }
        return nil
    }

    private static func parseRect(_ v: Any?) -> CGRect? {
        guard let d = v as? NSDictionary,
              let x = cgFloat(d["x"]), let y = cgFloat(d["y"]),
              let w = cgFloat(d["width"]), let h = cgFloat(d["height"]), w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 말풍선 이미지(정적 지도 스냅샷) 로드. 메모리/디스크 캐시 → file:// → 다운로드 순.
    /// 실패하거나 너무 오래 걸리면 nil (이미지 없이 지도만 엶)
    /// completion(이미지, 마커 뺀 이미지인지). renderLocationThumbnail 결과면 마커 뺀 짝을 씀 → 뷰어가 마커를 따로 그려
    /// 말풍선 속 크기 ↔ 지도 마커 크기로 자연스럽게 바꿈
    private func loadMapSourceImage(_ uri: String?, completion: @escaping (UIImage?, Bool) -> Void) {
        guard let uri = uri, !uri.isEmpty else { completion(nil, false); return }
        if uri.hasPrefix("file://") || uri.hasPrefix("/") {
            let path = uri.hasPrefix("file://") ? (URL(string: uri)?.path ?? String(uri.dropFirst(7))) : uri
            DispatchQueue.global(qos: .userInitiated).async {
                if let base = LocationThumbnailRenderer.markerlessFile(for: path), let img = UIImage(contentsOfFile: base) {
                    DispatchQueue.main.async { completion(img, true) }
                    return
                }
                let image = UIImage(contentsOfFile: path)
                DispatchQueue.main.async { completion(image, false) }
            }
            return
        }
        if let cached = ViewerImageCache.shared.getMemoryImage(for: uri) { completion(cached, false); return }
        var done = false
        let finish: (UIImage?) -> Void = { image in
            DispatchQueue.main.async {
                guard !done else { return }
                done = true
                completion(image, false)
            }
        }
        // 다운로드가 늦으면 이미지 없이 바로 엶 (탭 반응이 늦어지지 않게)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { finish(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            if let disk = ViewerImageCache.shared.getDiskImageSynchronously(for: uri) { finish(disk); return }
            RemoteImageViewerViewController.prefetchImage(from: uri) { finish($0) }
        }
    }

    @objc
    func openMapViewer(_ options: NSDictionary,
                       resolve: @escaping RCTPromiseResolveBlock,
                       reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let lat = RNAttachmentKit.cgFloat(options["latitude"]),
              let lng = RNAttachmentKit.cgFloat(options["longitude"]) else {
            reject("ERROR", "latitude and longitude are required", nil)
            return
        }
        let sourceRect = RNAttachmentKit.parseRect(options["sourceRect"])
        let imageUri = options["sourceImageUri"] as? String
        DispatchQueue.main.async {
            // 위치 정보만으로 여는 경우엔 이미지 로드를 기다리지 않음
            let load: (@escaping (UIImage?, Bool) -> Void) -> Void = { done in
                if sourceRect == nil { done(nil, false) } else { self.loadMapSourceImage(imageUri, completion: done) }
            }
            load { image, markerless in
                guard let root = self.getRootViewController() else {
                    reject("ERROR", "Unable to get root view controller", nil)
                    return
                }
                var accent = UIColor(red: 1, green: 0.42, blue: 0.21, alpha: 1)
                if let hex = options["themeColor"] as? String, let c = UIColor(hexString: hex) { accent = c }
                let vc = MapViewerViewController(
                    latitude: Double(lat), longitude: Double(lng),
                    title: options["title"] as? String,
                    address: options["address"] as? String,
                    markerType: options["markerType"] as? String,
                    placeCategory: options["placeCategory"] as? String,
                    accentColor: accent,
                    languageCode: options["languageCode"] as? String ?? "en")
                vc.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
                vc.showsDirections = (options["showDirections"] as? Bool) ?? true
                vc.addressLanguageCode = (options["addressLanguageCode"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if let span = RNAttachmentKit.cgFloat(options["spanMeters"]), span > 0 { vc.spanMeters = Double(span) }
                if let r = RNAttachmentKit.cgFloat(options["sourceCornerRadius"]) { vc.sourceCornerRadius = r }
                self.mapViewerSourceRect = sourceRect
                if let rect = sourceRect {
                    vc.sourceRect = rect
                    vc.sourceImage = image
                    vc.sourceImageIsMarkerless = markerless && image != nil
                    vc.sourceRectProvider = { [weak self] in self?.mapViewerSourceRect }
                }
                vc.onWillClose = { [weak self] dur in
                    self?.sendEvent(withName: "onMapViewerWillClose", body: ["durationMs": Int(dur * 1000)])
                }
                vc.onClosed = { [weak self] in
                    self?.mapViewerSourceRect = nil
                    resolve(nil)
                }
                self.activeMapViewerVC = vc
                root.present(vc, animated: sourceRect == nil)
            }
        }
    }

    @objc
    func updateMapViewerSourceRect(_ rect: NSDictionary,
                                   resolve: @escaping RCTPromiseResolveBlock,
                                   reject: @escaping RCTPromiseRejectBlock) -> Void {
        let parsed = RNAttachmentKit.parseRect(rect)
        DispatchQueue.main.async {
            if self.activeMapViewerVC != nil { self.mapViewerSourceRect = parsed }
            resolve(nil)
        }
    }

    /// 위치 메시지 말풍선 지도 썸네일을 이 기기에서 그려 캐시 (보낸 이미지 없이 위치 정보만으로)
    @objc
    func renderLocationThumbnail(_ options: NSDictionary,
                                 resolve: @escaping RCTPromiseResolveBlock,
                                 reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let lat = RNAttachmentKit.cgFloat(options["latitude"]),
              let lng = RNAttachmentKit.cgFloat(options["longitude"]),
              let w = RNAttachmentKit.cgFloat(options["width"]), w > 0 else {
            reject("E_INVALID_ARGS", "latitude, longitude and width are required", nil)
            return
        }
        DispatchQueue.main.async {
            // 비율(aspect)이 있으면 세로는 가로에서 계산, 없으면 height 그대로
            guard let h = LocationThumbnailRenderer.height(forWidth: w, aspect: options["aspect"] as? String)
                    ?? RNAttachmentKit.cgFloat(options["height"]), h > 0 else {
                reject("E_INVALID_ARGS", "height (or aspect) is required", nil)
                return
            }
            var accent = UIColor(red: 1, green: 0.42, blue: 0.21, alpha: 1)
            if let hex = options["themeColor"] as? String, let c = UIColor(hexString: hex) { accent = c }
            var style = RNAttachmentKit.interfaceStyle(options)
            if style == .unspecified {
                // "system": 지금 앱 화면 모드
                style = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
                    .first?.traitCollection.userInterfaceStyle ?? UITraitCollection.current.userInterfaceStyle
            }
            var me: CLLocationCoordinate2D?
            if let mlat = RNAttachmentKit.cgFloat(options["myLatitude"]), let mlng = RNAttachmentKit.cgFloat(options["myLongitude"]) {
                me = CLLocationCoordinate2D(latitude: Double(mlat), longitude: Double(mlng))
            }
            let span = RNAttachmentKit.cgFloat(options["spanMeters"]).map { Double($0) }
            var req = LocationThumbnailRequest(
                latitude: Double(lat), longitude: Double(lng),
                size: CGSize(width: w, height: h), scale: min(UIScreen.main.scale, 3),
                isDark: style == .dark,
                markerType: options["markerType"] as? String,
                placeCategory: options["placeCategory"] as? String,
                spanMeters: (span ?? 0) > 0 ? span : nil,
                accentColor: accent,
                myLocation: me)
            // 결과 이미지 최대 크기 (px). 둘 다 없으면 512 × 512, 하나만 주면 다른 쪽은 제한 없음
            // (예: maxWidth 512 만 주고 세로가 기본 512 에 잘려 작아지는 일이 없게)
            let maxW = RNAttachmentKit.cgFloat(options["maxWidth"]).flatMap { $0 > 0 ? $0 : nil }
            let maxH = RNAttachmentKit.cgFloat(options["maxHeight"]).flatMap { $0 > 0 ? $0 : nil }
            if maxW != nil || maxH != nil {
                req.maxPixelWidth = maxW ?? .greatestFiniteMagnitude
                req.maxPixelHeight = maxH ?? .greatestFiniteMagnitude
            }
            LocationThumbnailRenderer.render(req) { result in
                switch result {
                case .success(let dict): resolve(dict)
                case .failure(let error): reject("E_THUMBNAIL_FAILED", error.localizedDescription, error)
                }
            }
        }
    }

    // MARK: - Reverse geocode (기기 지오코더, 디스크 캐시)

    @objc
    func reverseGeocode(_ options: NSDictionary,
                        resolve: @escaping RCTPromiseResolveBlock,
                        reject: @escaping RCTPromiseRejectBlock) -> Void {
        let lat = (options["latitude"] as? NSNumber)?.doubleValue ?? .nan
        let lng = (options["longitude"] as? NSNumber)?.doubleValue ?? .nan
        let lang = (options["languageCode"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        ReverseGeocoder.shared.reverseGeocode(latitude: lat, longitude: lng, languageCode: lang) { result in
            switch result {
            case .success(let r): resolve(r.dictionary)
            case .failure(let e): reject(e.code, e.message, nil)
            }
        }
    }

    /// AI 기능 설정·잔액 (넘긴 값만 바뀜). 사용·충전 요청은 onAIUsage / onAIChargeRequired 이벤트로 알림
    @objc
    func setAIConfig(_ config: NSDictionary,
                     resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) -> Void {
        let dict = config as? [String: Any] ?? [:]
        DispatchQueue.main.async {
            AIBilling.apply(dict)
            AIBilling.onUsage = { [weak self] body in self?.sendEvent(withName: "onAIUsage", body: body) }
            AIBilling.onChargeRequired = { [weak self] body in self?.sendEvent(withName: "onAIChargeRequired", body: body) }
            resolve(nil)
        }
    }

    @objc
    func clearReverseGeocodeCache(_ resolve: @escaping RCTPromiseResolveBlock,
                                  reject: @escaping RCTPromiseRejectBlock) -> Void {
        ReverseGeocoder.shared.clearCache { resolve(nil) }
    }

    @objc
    func clearLocationThumbnailCache(_ resolve: @escaping RCTPromiseResolveBlock,
                                     reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.global(qos: .utility).async {
            LocationThumbnailRenderer.clearCache()
            resolve(nil)
        }
    }

    @objc
    func openViewer(_ options: NSDictionary,
                    resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let images = options["images"] as? [String] else {
            reject("ERROR", "images array is required", nil)
            return
        }
        
        let initialIndex = options["initialIndex"] as? Int ?? 0
        let placeholderImages = options["placeholderImages"] as? [String]
        // cacheFiles: images 와 같은 순서의 로컬 캐시 파일 경로 (null 항목은 NSNull 로 옴 → 빈 문자열)
        let cacheFiles: [String]? = (options["cacheFiles"] as? [Any])?.map { ($0 as? String) ?? "" }
        // videos: images 와 같은 순서. 항목이 있으면 그 페이지는 동영상 (images[i] 는 포스터)
        let viewerVideos: [ViewerVideoItem?] = (options["videos"] as? [Any])?.map { ViewerVideoItem(dictionary: $0) } ?? []
        let themeColorHex = options["themeColor"] as? String
        let languageCode = options["languageCode"] as? String ?? "en"
        let viewerTitle = options["title"] as? String
        let animationType = options["animationType"] as? String ?? (options["sourceRect"] != nil ? "zoom" : "slide")
        let closeAnimationType = options["closeAnimationType"] as? String
        // 저장/공유/삭제 상단바 버튼 - 사용자가 준 스크린샷(전체 저장/이 사진만 저장 등)에
        // 맞춘 기본 한국어 문구가 있으므로, JS에서 안 넘기면 그 기본값을 그대로 씁니다.
        let showActionButtons = (options["showActionButtons"] as? Bool) ?? true
        let saveAllText = options["saveAllText"] as? String
        let saveOneText = options["saveOneText"] as? String
        let shareAllText = options["shareAllText"] as? String
        let shareOneText = options["shareOneText"] as? String
        let actionCancelText = options["actionCancelText"] as? String
        let deleteConfirmTitle = options["deleteConfirmTitle"] as? String
        let deleteConfirmMessage = options["deleteConfirmMessage"] as? String
        let deleteConfirmGroupMessage = options["deleteConfirmGroupMessage"] as? String
        let deleteButtonText = options["deleteButtonText"] as? String
        // patch405: 삭제 방식 선택지 [{ key, label, destructive }]
        let deleteOptions: [RemoteImageViewerViewController.DeleteOption] =
            ((options["deleteOptions"] as? [Any]) ?? []).compactMap { raw in
                guard let d = raw as? [String: Any],
                      let key = d["key"] as? String, !key.isEmpty,
                      let label = d["label"] as? String, !label.isEmpty else { return nil }
                let destructive = (d["destructive"] as? Bool) ?? ((d["destructive"] as? NSNumber)?.boolValue ?? false)
                return RemoteImageViewerViewController.DeleteOption(key: key, label: label, destructive: destructive)
            }
        
        var sourceBackgroundColor: UIColor = .clear
        if let bgString = options["sourceBackgroundColorString"] as? String {
            let comps = bgString.split(separator: ",")
            if comps.count >= 3,
               let r = Double(comps[0].trimmingCharacters(in: .whitespaces)),
               let g = Double(comps[1].trimmingCharacters(in: .whitespaces)),
               let b = Double(comps[2].trimmingCharacters(in: .whitespaces)) {
                sourceBackgroundColor = UIColor(red: CGFloat(r/255.0), green: CGFloat(g/255.0), blue: CGFloat(b/255.0), alpha: 1.0)
            }
        } else if let bgHex = options["sourceBackgroundColor"] as? String, let color = UIColor(hexString: bgHex) {
            sourceBackgroundColor = color
        }
        
        var parsedRect: CGRect?
        if let sourceRectDict = options["sourceRect"] as? NSDictionary {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var w: CGFloat = 0
            var h: CGFloat = 0
            if let xNum = sourceRectDict["x"] as? NSNumber { x = CGFloat(truncating: xNum) } else if let xDbl = sourceRectDict["x"] as? Double { x = CGFloat(xDbl) }
            if let yNum = sourceRectDict["y"] as? NSNumber { y = CGFloat(truncating: yNum) } else if let yDbl = sourceRectDict["y"] as? Double { y = CGFloat(yDbl) }
            if let wNum = sourceRectDict["width"] as? NSNumber { w = CGFloat(truncating: wNum) } else if let wDbl = sourceRectDict["width"] as? Double { w = CGFloat(wDbl) }
            if let hNum = sourceRectDict["height"] as? NSNumber { h = CGFloat(truncating: hNum) } else if let hDbl = sourceRectDict["height"] as? Double { h = CGFloat(hDbl) }
            parsedRect = CGRect(x: x, y: y, width: w, height: h)
        }
        
        var sourceBorderRadius: CGFloat = 0
        if let radiusNum = options["sourceBorderRadius"] as? NSNumber {
            sourceBorderRadius = CGFloat(truncating: radiusNum)
        } else if let radiusDbl = options["sourceBorderRadius"] as? Double {
            sourceBorderRadius = CGFloat(radiusDbl)
        }
        
        var mask: CACornerMask = []
        if let corners = options["sourceBorderCorners"] as? [String] {
            if corners.contains("topLeft") { mask.insert(.layerMinXMinYCorner) }
            if corners.contains("topRight") { mask.insert(.layerMaxXMinYCorner) }
            if corners.contains("bottomLeft") { mask.insert(.layerMinXMaxYCorner) }
            if corners.contains("bottomRight") { mask.insert(.layerMaxXMaxYCorner) }
            // Empty array means no rounded corners (e.g. interior group image cell)
        } else {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                let error = NSError(domain: "RNAttachmentKit", code: 0, userInfo: nil)
                reject("ERROR", "Unable to get root view controller", error)
                return
            }
            
            let viewerVC = RemoteImageViewerViewController(imageUrls: images, initialIndex: initialIndex)
            viewerVC.languageCode = languageCode
            viewerVC.viewerTitle = viewerTitle
            viewerVC.placeholderImages = placeholderImages
            viewerVC.cacheFiles = cacheFiles
            viewerVC.videos = viewerVideos
            if let hex = themeColorHex, let color = UIColor(hexString: hex) {
                viewerVC.themeColor = color
            }
            viewerVC.showActionButtons = showActionButtons
            if let saveAllText = saveAllText { viewerVC.saveAllText = saveAllText }
            if let saveOneText = saveOneText { viewerVC.saveOneText = saveOneText }
            if let shareAllText = shareAllText { viewerVC.shareAllText = shareAllText }
            if let shareOneText = shareOneText { viewerVC.shareOneText = shareOneText }
            if let actionCancelText = actionCancelText { viewerVC.actionCancelText = actionCancelText }
            if let deleteConfirmTitle = deleteConfirmTitle { viewerVC.deleteConfirmTitle = deleteConfirmTitle }
            viewerVC.deleteConfirmMessage = deleteConfirmMessage
            viewerVC.deleteConfirmGroupMessage = deleteConfirmGroupMessage
            if let deleteButtonText = deleteButtonText { viewerVC.deleteButtonText = deleteButtonText }
            viewerVC.deleteOptions = deleteOptions
            
            self.zoomAnimator.animationType = animationType
            self.zoomAnimator.closeAnimationType = closeAnimationType
            if let rect = parsedRect {
                self.zoomAnimator.sourceRect = rect
            }
            self.zoomAnimator.sourceBorderRadius = sourceBorderRadius
            self.zoomAnimator.sourceBorderCorners = mask
            self.zoomAnimator.sourceBackgroundColor = sourceBackgroundColor
            // Reset any sourceImage left over from a previous openViewer() call - it's only
            // meant to carry this call's local placeholder (see below), and must not leak
            // into a later call that has no placeholder of its own.
            self.zoomAnimator.sourceImage = nil
            
            viewerVC.modalPresentationStyle = .custom
            viewerVC.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
            viewerVC.transitioningDelegate = self
            
            self.activeViewerVC = viewerVC
            viewerVC.onPageChanged = { [weak self] (index: Int) -> Void in
                guard let self = self else { return }
                let eventBody: [String: Any] = ["index": index]
                self.sendEvent(withName: "onPageSelected", body: eventBody)
            }
            // ⚠️ 이전에는 이 클로저를 전혀 연결하지 않아서 "onViewerWillClose" 네이티브 이벤트가
            // iOS에서는 절대 발생하지 않았습니다. JS 쪽(src/index.ts)은 정확히 이 이벤트가 와야만
            // "onPageSelected" 구독을 정리(subscriptionPageSelected.remove())하기 때문에, 뷰어를
            // 열 때마다 그 구독이 영구히 누수됐습니다. onPageSelected는 뷰어별로 구분되지 않는
            // 전역 이벤트라서, 그룹 이미지를 여러 번 열면 예전 메시지의 리스너까지 전부 같이
            // 반응해서 서로 다른 메시지의 measureMap 기준으로 updateSourceRect를 호출해
            // 공유된 zoomAnimator.sourceRect를 덮어써버렸습니다 - "스와이프 후 닫으면 전혀
            // 다른 그룹 이미지 위치로 애니메이션되는" 버그의 근본 원인이었습니다. 이제 실제로
            // 뷰어가 닫히기 시작할 때 이벤트를 보내서 JS가 제때 구독을 정리하도록 합니다.
            viewerVC.onViewerWillClose = { [weak self] () -> Void in
                self?.sendEvent(withName: "onViewerWillClose", body: nil)
            }
            viewerVC.onImageDeleted = { [weak self] (index: Int, url: String, option: String?) -> Void in
                guard let self = self else { return }
                var eventBody: [String: Any] = ["index": index, "url": url]
                if let option = option { eventBody["option"] = option } // patch405
                self.sendEvent(withName: "onImageDeleted", body: eventBody)
            }
            viewerVC.onWillDismissForDelete = { [weak self] () -> Void in
                self?.zoomAnimator.fadeOutOnDismiss = true
            }
            
            let resolveResult: [String: Any] = ["success": true]
            
            // Cache-first, then local placeholder, then wait-for-download - in that priority
            // order. If the full-resolution image is ALREADY cached (memory or disk), we must
            // animate with THAT, not with a lower-quality local thumbnail placeholder: using the
            // placeholder here would show a needless blurry-then-sharp flash for an image that's
            // already available in full quality. The placeholder is only a stand-in for when the
            // full image genuinely isn't available yet (mirrors Android's onlyRetrieveFromCache
            // gating - "use the real image if it's already cached, otherwise the local thumbnail").
            // NOTE: only the memory cache is checked here (not the disk cache) - this bridge
            // file is compiled directly as a pod source file, a SEPARATE module from the
            // ViewerImageCache class (which ships compiled inside RNAttachmentKit.xcframework).
            // Cross-module Swift visibility requires `public`, and getDiskImageSynchronously()
            // wasn't public until this same fix - until the xcframework is rebuilt (deploy.rb /
            // build_xcframework.sh) and re-synced to Dist, calling it here would fail to compile.
            // Memory-cache is the common case anyway (an image just viewed/downloaded this
            // session); a disk-only cache hit will fall through to the placeholder path below,
            // which is still correct (just not maximally optimal) until that rebuild happens.
            var cachedFullImage: UIImage? = nil
            if images.indices.contains(initialIndex) {
                let urlString = images[initialIndex]
                cachedFullImage = ViewerImageCache.shared.getMemoryImage(for: urlString)
            }

            var initialPlaceholderImage: UIImage? = nil
            if cachedFullImage == nil, let placeholderImages = placeholderImages, placeholderImages.indices.contains(initialIndex) {
                let placeholderUrlString = placeholderImages[initialIndex]
                if placeholderUrlString.hasPrefix("file://"), let url = URL(string: placeholderUrlString) {
                    initialPlaceholderImage = UIImage(contentsOfFile: url.path)
                }
            }

            if let cachedImage = cachedFullImage {
                self.zoomAnimator.sourceImage = cachedImage
                rootViewController.present(viewerVC, animated: true, completion: {
                    resolve(resolveResult)
                })
            } else if let placeholderImage = initialPlaceholderImage {
                self.zoomAnimator.sourceImage = placeholderImage
                rootViewController.present(viewerVC, animated: true, completion: {
                    resolve(resolveResult)
                })
                if images.indices.contains(initialIndex) {
                    // Kick off/continue the full-resolution fetch in the background so it's
                    // ready (and cached) as soon as possible; the viewer's own page loading
                    // (ZoomableImageItemView.loadImage) will pick it up and swap it in.
                    RemoteImageViewerViewController.prefetchImage(from: images[initialIndex], completion: { _ in })
                }
            } else if images.indices.contains(initialIndex) {
                // No local placeholder available (exceptional case) - fall back to the previous
                // behavior: present immediately if already cached, otherwise wait for the
                // download to complete since there's nothing to animate with yet.
                let initialUrl = images[initialIndex]
                RemoteImageViewerViewController.prefetchImage(from: initialUrl) { _ in
                    DispatchQueue.main.async {
                        rootViewController.present(viewerVC, animated: true, completion: {
                            resolve(resolveResult)
                        })
                    }
                }
            } else {
                rootViewController.present(viewerVC, animated: true, completion: {
                    resolve(resolveResult)
                })
            }
        }
    }

    @objc
    func updateViewerSourceRect(_ rect: NSDictionary,
                                resolve: @escaping RCTPromiseResolveBlock,
                                reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            let x = (rect["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["x"] as? Double).map { CGFloat($0) } ?? 0
            let y = (rect["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["y"] as? Double).map { CGFloat($0) } ?? 0
            let w = (rect["width"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["width"] as? Double).map { CGFloat($0) } ?? 0
            let h = (rect["height"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["height"] as? Double).map { CGFloat($0) } ?? 0
            
            var mask: CACornerMask = []
            if let corners = rect["sourceBorderCorners"] as? [String] {
                if corners.contains("topLeft") { mask.insert(.layerMinXMinYCorner) }
                if corners.contains("topRight") { mask.insert(.layerMaxXMinYCorner) }
                if corners.contains("bottomLeft") { mask.insert(.layerMinXMaxYCorner) }
                if corners.contains("bottomRight") { mask.insert(.layerMaxXMaxYCorner) }
                if mask.isEmpty { mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
            } else {
                mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
            
            self.zoomAnimator.sourceRect = CGRect(x: x, y: y, width: w, height: h)
            self.zoomAnimator.sourceBorderCorners = mask
            self.zoomAnimator.updateMaskView()
            resolve(nil)
        }
    }

    @objc
    func openEditor(_ options: NSDictionary,
                    resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let uri = options["uri"] as? String else {
            reject("ERROR", "uri is required", nil)
            return
        }
        
        var themeColor: UIColor? = nil
        if let themeColorHex = options["themeColor"] as? String {
            themeColor = UIColor(hexString: themeColorHex)
        }
        
        var parsedMaxWidth: Int? = nil
        var parsedMaxHeight: Int? = nil
        if let maxW = options["maxWidth"] as? Int { parsedMaxWidth = maxW }
        if let maxH = options["maxHeight"] as? Int { parsedMaxHeight = maxH }
        
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                reject("ERROR", "Unable to get root view controller", nil)
                return
            }
            
            
            if uri.hasPrefix("ph://") {
                let localIdentifier = uri.replacingOccurrences(of: "ph://", with: "")
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
                
                guard let asset = fetchResult.firstObject else {
                    reject("ERROR", "Asset not found", nil)
                    return
                }
                
                let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                editorVC.allAssets = [asset]
                editorVC.currentIndex = 0
                editorVC.modalPresentationStyle = .fullScreen
                editorVC.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
                editorVC.singlePhotoMode = true
                if let color = themeColor {
                    editorVC.themeColor = color
                }
                
                if let editedUriStr = options["editedFileUri"] as? String,
                   let url = URL(string: editedUriStr) ?? URL(string: "file://" + editedUriStr.replacingOccurrences(of: "file://", with: "")),
                   let imgData = try? Data(contentsOf: url),
                   let img = UIImage(data: imgData) {
                    editorVC.croppedImages[0] = img
                }
                
                editorVC.onConfirm = { [weak self, weak editorVC] (editedAsset, editedImage, filterState, caption) in
                    editorVC?.dismiss(animated: true) {
                        self?.processEditorResult(asset: editedAsset, croppedImage: editedImage, filterState: filterState, caption: caption, galleryVC: nil, targetMaxWidth: parsedMaxWidth, targetMaxHeight: parsedMaxHeight, resolve: { resultArr in
                            if let arr = resultArr as? [[String: Any]], let first = arr.first {
                                resolve(first)
                            } else {
                                resolve(resultArr)
                            }
                        }, reject: reject)
                    }
                }
                
                editorVC.onCancel = { [weak editorVC] in
                    editorVC?.dismiss(animated: true) {
                        reject("CANCELLED", "User cancelled editor", nil)
                    }
                }
                
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                topController.present(editorVC, animated: true)
                
            } else {
                guard let url = URL(string: uri) ?? URL(string: "file://" + uri.replacingOccurrences(of: "file://", with: "")) else {
                    reject("ERROR", "Invalid URI format", nil)
                    return
                }
                
                DispatchQueue.global().async {
                    if let imgData = try? Data(contentsOf: url), let image = UIImage(data: imgData) {
                        DispatchQueue.main.async {
                            let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                            editorVC.standaloneImage = image
                            editorVC.currentIndex = 0
                            editorVC.modalPresentationStyle = .fullScreen
                            editorVC.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
                            editorVC.singlePhotoMode = true
                            if let color = themeColor {
                                editorVC.themeColor = color
                            }
                            
                            editorVC.onConfirm = { [weak self, weak editorVC] (editedAsset, editedImage, filterState, caption) in
                                editorVC?.dismiss(animated: true) {
                                    self?.processEditorResult(asset: editedAsset, croppedImage: editedImage, filterState: filterState, caption: caption, galleryVC: nil, targetMaxWidth: parsedMaxWidth, targetMaxHeight: parsedMaxHeight, resolve: { resultArr in
                                        var resultDict = (resultArr as? [[String: Any]])?.first ?? (resultArr as? [String: Any]) ?? [:]
                                        // For remote URLs, we preserve originalUri if editedFileUri isn't provided
                                        let originalRemoteUrl = (options["editedFileUri"] as? String) ?? uri
                                        resultDict["originalUri"] = originalRemoteUrl
                                        resolve(resultDict)
                                    }, reject: reject)
                                }
                            }
                            
                            editorVC.onCancel = { [weak editorVC] in
                                editorVC?.dismiss(animated: true) {
                                    reject("CANCELLED", "User cancelled editor", nil)
                                }
                            }
                            
                            var topController = rootViewController
                            while let presented = topController.presentedViewController {
                                topController = presented
                            }
                            topController.present(editorVC, animated: true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            reject("ERROR", "Failed to load image from URI", nil)
                        }
                    }
                }
            }

        }
    }

    @objc
    func openGallery(_ options: NSDictionary,
                     resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) -> Void {
        let startTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        print("✅ [DEBUG] received options: \(options)")
        print("🔵 [DEBUG] openGallery 시작 - 시간: \(startTime)")
        #endif

        // 예전에 파일/위치 탭에서 임시 폴더에 복사해 두고 24시간이 지난 것 정리 (백그라운드, UI 와 무관)
        DispatchQueue.global(qos: .utility).async {
            TempFileCleaner.cleanupStaleTempFiles()
        }

        // Main thread에서 실행
        DispatchQueue.main.async { [weak self] () -> Void in
            guard let self = self else {
                reject("ERROR", "Module deallocated", nil)
                return
            }

            #if DEBUG
            print("🔵 [DEBUG] workItem 실행 시작 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
            #endif

            let step1 = CFAbsoluteTimeGetCurrent()
            guard let rootViewController = self.getRootViewController() else {
                print("❌ [DEBUG] getRootViewController 실패")
                reject("ERROR", "Unable to get root view controller", nil)
                return
            }
            #if DEBUG
            print("🔵 [DEBUG] getRootViewController 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step1))초")
            #endif

            let step2 = CFAbsoluteTimeGetCurrent()
            let galleryVC = GalleryViewController()
            #if DEBUG
            print("🔵 [DEBUG] GalleryViewController 생성 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step2))초")
            #endif
            
            // 현재 갤러리 참조 저장
            self.currentGalleryVC = galleryVC
            
            // 선택 변경 이벤트 콜백 설정
            galleryVC.onSelectionChanged = { [weak self] selectedCount, maxSelection in
                self?.sendEvent(withName: "onSelectionChange", body: [
                    "selectedCount": selectedCount,
                    "maxSelection": maxSelection
                ])
            }
            
            // 선택 방식 (selectionMode: 'single' | 'multi', 생략 시 기존 규칙)
            //  - 'multi' : maxSelection 이 1 이어도 멀티와 똑같이 (autoCloseOnSelect 무시, 1 미만이면 1장)
            //  - 'single': 기존 단일 동작 (maxSelection 을 1로, autoCloseOnSelect 면 0)
            //  - 생략     : 기존 그대로 (autoCloseOnSelect → 0, 아니면 maxSelection)
            let selectionMode = (options["selectionMode"] as? String)?.lowercased()
            let autoCloseOnSelect = options["autoCloseOnSelect"] as? Bool ?? false
            galleryVC.forceMultiMode = (selectionMode == "multi")
            if selectionMode == "multi" {
                let requested = options["maxSelection"] as? Int ?? 1
                galleryVC.maxSelection = requested < 1 ? 1 : requested
            } else if autoCloseOnSelect {
                // maxSelection 설정 (autoCloseOnSelect가 true면 0으로 설정하여 단일 선택 자동 닫기 처리)
                galleryVC.maxSelection = 0
            } else if selectionMode == "single" {
                galleryVC.maxSelection = 1
            } else if let maxSelection = options["maxSelection"] as? Int {
                galleryVC.maxSelection = maxSelection
            }
            
            // maxWidth, maxHeight 옵션 (미설정 또는 0이면 원본 크기 유지)
            galleryVC.maxWidth = (options["maxWidth"] as? Int) ?? 0
            galleryVC.maxHeight = (options["maxHeight"] as? Int) ?? 0

            // outputFormat: "webp" | "jpg" | "png" (기본값: "webp")
            let fmt = (options["outputFormat"] as? String)?.lowercased() ?? "webp"
            galleryVC.outputFormat = ["webp", "jpg", "png"].contains(fmt) ? fmt : "webp"
            
            if let themeColorHex = options["themeColor"] as? String {
                galleryVC.themeColorHex = themeColorHex
            }
            
            // 언어 코드 설정 (기본값: "en") - 이것이 먼저 설정되어 텍스트 자동 적용
            galleryVC.languageCode = options["languageCode"] as? String ?? "en" 
            
            // 개별 텍스트 커스터마이징 (옵션, languageCode 오버라이드)
            if let allText = options["allItemsText"] as? String {
                galleryVC.allItemsText = allText
            }
            if let selectedText = options["selectedItemsText"] as? String {
                galleryVC.selectedItemsText = selectedText
            }
            if let doneText = options["doneButtonText"] as? String {
                galleryVC.doneButtonText = doneText
            }
            if let recentsText = options["recentsAlbumText"] as? String {
                galleryVC.recentsAlbumText = recentsText
            }
            
            let enableEditor = options["enableEditor"] as? Bool ?? false
            galleryVC.profileMode = options["profileMode"] as? Bool ?? false
            
            if galleryVC.profileMode {
                galleryVC.allowsEditing = enableEditor
                galleryVC.onProfileCropComplete = { [weak self, weak galleryVC] asset, croppedImage in
                    guard let self = self, let currentGallery = galleryVC else { return }
                    
                    if enableEditor {
                        let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                        editorVC.allAssets = [asset]
                        editorVC.currentIndex = 0
                        editorVC.singlePhotoMode = true
                        editorVC.disableCrop = true
                        editorVC.croppedImages = [0: croppedImage]
                        editorVC.modalPresentationStyle = .overFullScreen
                        editorVC.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
                        
                        if let hex = currentGallery.themeColorHex, let color = UIColor(hexString: hex) {
                            editorVC.themeColor = color
                        }
                        
                        editorVC.onConfirm = { [weak self] (editedAsset: PHAsset?, finalCroppedImage: UIImage?, filterState: FilterState, caption: String) in
                            guard let self = self else { return }
                            let navToDismiss = currentGallery.navigationController ?? currentGallery
                            let presenter = navToDismiss.presentingViewController ?? navToDismiss
                            presenter.dismiss(animated: true) {
                                self.processEditorResult(asset: editedAsset, croppedImage: finalCroppedImage ?? croppedImage, filterState: filterState, caption: caption, galleryVC: currentGallery, resolve: resolve, reject: reject)
                            }
                        }
                        
                        editorVC.onCancel = { [weak currentGallery] in
                            currentGallery?.selectedAssets.removeAll()
                            currentGallery?.refreshSelectionAfterEdit()
                            // 결과 전달 책임이 갤러리로 돌아옴 → 닫기가 다시 취소(reject)를 보낼 수 있게
                            currentGallery?.hasReturnedImages = false
                        }
                        
                        var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
                        if #available(iOS 15.0, *) {
                            savedDetent = currentGallery.navigationController?.sheetPresentationController?.selectedDetentIdentifier
                        }

                        let presenterVC = currentGallery.presentedViewController ?? currentGallery
                        presenterVC.present(editorVC, animated: true) {
                            if #available(iOS 15.0, *) {
                                if let saved = savedDetent {
                                    currentGallery.navigationController?.sheetPresentationController?.selectedDetentIdentifier = saved
                                }
                            }
                        }
                    } else {
                        // Edit is disabled, directly process the cropped image
                        let navToDismiss = currentGallery.navigationController ?? currentGallery
                        let presenter = navToDismiss.presentingViewController ?? navToDismiss
                        presenter.dismiss(animated: true) {
                            self.processEditorResult(asset: asset, croppedImage: croppedImage, filterState: FilterState(filterId: "original", intensity: 1.0), caption: "", galleryVC: currentGallery, resolve: resolve, reject: reject)
                        }
                    }
                }
            }

            if enableEditor {
                // allowsEditing 활성화: GalleryVC 내 탭 동작 변경
                galleryVC.allowsEditing = true

                galleryVC.onSingleImageTappedForEdit = { [weak self] (asset: PHAsset, sourceFrame: CGRect, sourceImage: UIImage?) -> Void in
                    self?._turbo_handleSingleImageTappedForEdit(asset: asset, sourceFrame: sourceFrame, sourceImage: sourceImage, options: options, resolve: resolve, reject: reject)
                }
            }

            // 첨부 메뉴(갤러리 / 위치 / 파일). 기본 false — 켜지 않으면 기존과 같음
            galleryVC.showsAttachMenu = options["showAttachMenu"] as? Bool ?? false
            // 위치 보내기 때 지도 캡처 이미지 (기본 true). false 면 위치 정보만 — 받는 쪽이 renderLocationThumbnail 로 그림
            galleryVC.capturesLocationImage = options["captureLocationImage"] as? Bool ?? true
            // 동영상: mediaType "photo"(기본) | "video" | "all" + video 옵션 (지시서 3-1)
            let mediaTypeOption = (options["mediaType"] as? String)?.lowercased() ?? "photo"
            galleryVC.mediaType = ["photo", "video", "all"].contains(mediaTypeOption) ? mediaTypeOption : "photo"
            let videoOptions = VideoExportOptions(dictionary: options["video"] as? [String: Any])
            let asyncProcessing = options["asyncProcessing"] as? Bool ?? false
            self.galleryShowsVideoHUD = ((options["video"] as? [String: Any])?["showProgressHUD"] as? Bool) ?? !asyncProcessing
            galleryVC.maxVideoDurationSec = videoOptions.maxDurationSec
            galleryVC.videoExportOptions = videoOptions
            // 위치 탭에서 보내기 → onLocationSelected 이벤트로 결과를 넘기고, openGallery 는 빈 배열로 끝냄
            galleryVC.onLocationSelected = { [weak self, weak galleryVC] location in
                self?.currentGalleryVC = nil
                self?.sendEvent(withName: "onLocationSelected", body: location.dictionary)
                resolve([])
                galleryVC?.releaseAfterReturn()
            }
            // 파일 탭에서 보내기 → onFilesSelected 이벤트 { files: [{uri, path, name, size, mimeType}] }, openGallery 는 빈 배열
            // 일부 파일만 복사에 실패하면 (추가 필드) failed: [{name, error}] 를 함께 보냄 (files 는 그대로)
            galleryVC.onFilesSelectedWithFailures = { [weak self, weak galleryVC] files, failures in
                self?.currentGalleryVC = nil
                var body: [String: Any] = ["files": files.map { $0.dictionary }]
                if !failures.isEmpty { body["failed"] = failures.map { $0.dictionary } }
                self?.sendEvent(withName: "onFilesSelected", body: body)
                resolve([])
                galleryVC?.releaseAfterReturn()
            }

            // ⚠️ 클로저 안에서 galleryVC 를 강하게 잡으면 galleryVC → onImagesSelected → galleryVC 순환 참조가 되어
            // (성공 경로는 viewDidDisappear 가 정리를 deinit 으로 미루므로) 갤러리가 영영 해제되지 않았습니다.
            // 필요한 값은 미리 상수로 꺼내고, galleryVC 는 weak 로만 씁니다.
            let galleryMaxWidth  = galleryVC.maxWidth
            let galleryMaxHeight = galleryVC.maxHeight
            let galleryFormat    = galleryVC.outputFormat   // "webp" | "jpg" | "png"
            let galleryAccent    = galleryVC.parsedThemeColor
            let galleryLanguage  = galleryVC.languageCode
            galleryVC.onImagesSelected = { [weak self, weak galleryVC] selectedImages in
                guard let self = self else { resolve([]); return }

                guard !selectedImages.isEmpty else {
                    self.currentGalleryVC = nil
                    reject("CANCELLED", "User cancelled the image picker", nil)
                    return
                }

                var results: [[String: Any]] = []
                let tempDir    = self.prepareCacheDirectory()
                let maxWidth   = galleryMaxWidth
                let maxHeight  = galleryMaxHeight
                let format     = galleryFormat
                let mimeType   = self.mimeType(for: format)
                let needResize = (maxWidth > 0 || maxHeight > 0)
                let total      = selectedImages.count

                let resultsLock = NSLock()
                // 처리한 이미지는 바로 놓아 주도록 (전체 UIImage 배열을 끝까지 들고 있지 않게) 옵셔널 배열로 옮김
                var pending: [(PHAsset?, UIImage)?] = selectedImages.map { $0 }

                // 동영상이 섞여 있으면 변환 진행 표시 (갤러리가 닫힌 뒤에도 보이게 키 윈도우에) + 취소
                let hasVideo = selectedImages.contains { $0.0?.mediaType == .video }
                // 편집 화면에서 고른 품질·음소거 (없으면 기본 품질)
                let videoStates = galleryVC?.videoEditStates ?? [:]
                var hud: VideoExportHUD?
                var currentExporter: VideoExporter?
                var cancelledAll = false
                let exporterLock = NSLock()
                // 앱이 동영상 하나(또는 전부)를 취소할 수 있게 (cancelVideoProcessing)
                let job = MediaProcessingJob()
                let processingId = UUID().uuidString
                self.processingJobs[processingId] = job
                self.lastProcessingId = processingId
                // 처리 시작 이벤트용 — 고른 순서의 원본(사진은 편집 결과) 크기·포스터
                let startItems = selectedImages.map { ($0.0, $0.1) }
                if hasVideo && self.galleryShowsVideoHUD {
                    hud = VideoExportHUD.show(accent: galleryAccent, languageCode: galleryLanguage)
                    hud?.onCancel = {
                        exporterLock.lock(); cancelledAll = true; currentExporter?.cancel(); exporterLock.unlock()
                    }
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    // ✅ 처리 시작: 모든 자리(사진·동영상)를 먼저 알림 → 앱이 말풍선을 바로 만들고 진행률을 그림
                    self.sendEvent(withName: "onProcessingStart", body: [
                        "processingId": processingId,
                        "total": total,
                        "items": startItems.enumerated().map { i, pair in
                            self.processingStartItem(index: i, asset: pair.0, image: pair.1, videoStates: videoStates,
                                                     videoOptions: videoOptions, maxWidth: maxWidth, maxHeight: maxHeight,
                                                     tempDir: tempDir)
                        },
                    ])
                    for index in 0..<total {
                        guard let pair = pending[index] else { continue }
                        pending[index] = nil
                        exporterLock.lock(); let stop = cancelledAll; exporterLock.unlock()
                        if stop { break }
                        autoreleasepool {
                            let (asset, image) = pair
                            let timestamp    = Int(Date().timeIntervalSince1970 * 1000)
                            let originalSize = image.size

                            if let phAsset = asset, phAsset.mediaType == .video {
                                // ✅ 동영상: VideoExporter 로 전송용 mp4 (+ 썸네일·메타). image 는 포스터(목록용)
                                let exporter = VideoExporter()
                                exporterLock.lock(); currentExporter = exporter; exporterLock.unlock()
                                let base = "turbo_video_\(timestamp)_\(index)"
                                var result: [String: Any] = [
                                    "originalUri":    "ph://\(phAsset.localIdentifier)",
                                    "originalWidth":  phAsset.pixelWidth,
                                    "originalHeight": phAsset.pixelHeight,
                                    "mediaType":      "video",
                                    "type":           "video/mp4",
                                    "duration":       phAsset.duration,
                                ]
                                do {
                                    // 앱이 이미 취소한 동영상은 건너뜀 (결과에 cancelled 로)
                                    if job.isCancelled(index) { throw VideoExporter.ExportError.cancelled }
                                    job.begin(index: index, exporter: exporter)
                                    let state = videoStates[phAsset.localIdentifier] ?? VideoEditState.defaultState(for: phAsset, options: videoOptions)
                                    let throttle = ProgressThrottle()
                                    let onProgress: (Double) -> Void = { p in
                                        // 프레임마다 메인으로 보내지 않고 1%·0.1초 단위로만 (HUD 표시는 정수 % 라 같음)
                                        guard throttle.shouldSend(p) else { return }
                                        DispatchQueue.main.async { hud?.update(progress: p, index: index, total: total) }
                                        self.sendEvent(withName: "onVideoProgress", body: ["index": index, "total": total, "progress": p, "processingId": processingId])
                                    }
                                    // 편집 화면에서 미리 만들어 둔 파일이 있으면(또는 만드는 중이면 끝나고) 그대로 씀
                                    let r: VideoExportResult
                                    // 기다리는 동안 앱(X)이나 HUD 가 취소하면 바로 멈춤 (전엔 미리 만들기가 끝날 때까지 못 빠져나왔음)
                                    let stop = { () -> Bool in
                                        exporterLock.lock(); let all = cancelledAll; exporterLock.unlock()
                                        return all || job.isCancelled(index)
                                    }
                                    if let ready = VideoPrepareManager.shared.takeReady(asset: phAsset, state: state, progress: onProgress, isCancelled: stop) {
                                        r = ready; onProgress(1)
                                    } else {
                                        if stop() { throw VideoExporter.ExportError.cancelled }
                                        r = try exporter.export(asset: phAsset, state: state,
                                                                options: videoOptions, outputDir: URL(fileURLWithPath: tempDir), baseName: base, progress: onProgress)
                                    }
                                    // 미리 만든 파일을 기다리는 동안 취소됐으면 결과를 쓰지 않음
                                    if job.isCancelled(index) { throw VideoExporter.ExportError.cancelled }
                                    result["uri"]           = "file://" + r.url.path
                                    result["width"]         = r.width
                                    result["height"]        = r.height
                                    result["duration"]      = r.duration
                                    result["fileSize"]      = r.fileSize
                                    result["fileName"]      = r.url.lastPathComponent
                                    result["fileExtension"] = "mp4"
                                    result["videoCodec"]    = r.codec
                                    result["videoBitrate"]  = r.bitrate
                                    result["edited"]        = !r.passthrough
                                    if let t = r.thumbnailURL {
                                        result["thumbnailUri"]    = "file://" + t.path
                                        result["thumbnailWidth"]  = r.thumbnailWidth
                                        result["thumbnailHeight"] = r.thumbnailHeight
                                    }
                                } catch VideoExporter.ExportError.cancelled where job.isCancelled(index) {
                                    // 앱이 이 동영상만 취소 → 나머지는 계속
                                    result["error"] = "CANCELLED"
                                    result["cancelled"] = true
                                } catch VideoExporter.ExportError.cancelled {
                                    // HUD 의 취소 → 전체 취소 (Promise reject)
                                    job.end()
                                    exporterLock.lock(); cancelledAll = true; exporterLock.unlock()
                                    return
                                } catch {
                                    result["error"] = error.localizedDescription
                                }
                                job.end()
                                exporterLock.lock(); currentExporter = nil; exporterLock.unlock()

                                resultsLock.lock()
                                results.append(result)
                                let currentResult = result
                                resultsLock.unlock()
                                self.sendEvent(withName: "onImageProcessed", body: ["index": index, "total": total, "image": currentResult, "processingId": processingId])
                            } else if let phAsset = asset {
                                // ✅ 1순위: PHAsset
                                let originalUri = "ph://\(phAsset.localIdentifier)"

                                var targetImage: UIImage
                                if needResize, let resized = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) {
                                    targetImage = resized
                                } else {
                                    targetImage = image
                                }
                                targetImage = ImageProcessor.shared.applyWatermarkIfNeeded(targetImage)

                                var result: [String: Any] = [
                                    "originalUri":    originalUri,
                                    "originalWidth":  Int(originalSize.width),
                                    "originalHeight": Int(originalSize.height),
                                    "type": mimeType
                                ]

                                if let savedUri = self.saveImage(targetImage, format: format,
                                                                 prefix: "resized",
                                                                 index: index, timestamp: timestamp,
                                                                 tempDir: tempDir) {
                                    result["uri"]           = savedUri
                                    result["width"]         = Int(targetImage.size.width)
                                    result["height"]        = Int(targetImage.size.height)
                                    let meta = self.fileMetadata(fromPath: savedUri)
                                    result["fileName"]      = meta.fileName
                                    result["fileExtension"] = meta.fileExtension
                                    result["fileSize"]      = meta.fileSize
                                }

                                resultsLock.lock()
                                results.append(result)
                                let currentResult = result
                                resultsLock.unlock()
                                
                                self.sendEvent(withName: "onImageProcessed", body: [
                                    "index": index,
                                    "total": total,
                                    "image": currentResult,
                                    "processingId": processingId
                                ])
                            } else {
                                // ✅ 2순위: 카메라 촬영본
                                guard let originalFilePath = self.saveOriginalImageAsJPEG(
                                        image, index: index, timestamp: timestamp, tempDir: tempDir) else {
                                    return
                                }

                                var targetImage: UIImage
                                if needResize, let resized = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) {
                                    targetImage = resized
                                } else {
                                    targetImage = image
                                }
                                targetImage = ImageProcessor.shared.applyWatermarkIfNeeded(targetImage)

                                var result: [String: Any] = [
                                    "originalUri":     originalFilePath,
                                    "originalFileUri": originalFilePath,
                                    "originalWidth":   Int(originalSize.width),
                                    "originalHeight":  Int(originalSize.height),
                                    "type": mimeType
                                ]
                                let origMeta = self.fileMetadata(fromPath: originalFilePath)
                                result["fileName"]      = origMeta.fileName
                                result["fileExtension"] = origMeta.fileExtension
                                result["fileSize"]      = origMeta.fileSize

                                if let savedUri = self.saveImage(targetImage, format: format,
                                                                 prefix: "resized",
                                                                 index: index, timestamp: timestamp,
                                                                 tempDir: tempDir) {
                                    result["uri"]           = savedUri
                                    result["width"]         = Int(targetImage.size.width)
                                    result["height"]        = Int(targetImage.size.height)
                                    let meta = self.fileMetadata(fromPath: savedUri)
                                    result["fileName"]      = meta.fileName
                                    result["fileExtension"] = meta.fileExtension
                                    result["fileSize"]      = meta.fileSize
                                }

                                resultsLock.lock()
                                results.append(result)
                                let currentResult = result
                                resultsLock.unlock()
                                
                                self.sendEvent(withName: "onImageProcessed", body: [
                                    "index": index,
                                    "total": total,
                                    "image": currentResult,
                                    "processingId": processingId
                                ])
                            }
                        } // end autoreleasepool
                    } // end for

                    DispatchQueue.main.async {
                        hud?.dismiss()
                        // 처리하는 동안 새 갤러리가 열렸을 수 있음 → 내 갤러리일 때만 비움
                        if self.currentGalleryVC == nil || self.currentGalleryVC === galleryVC { self.currentGalleryVC = nil }
                        self.processingJobs[processingId] = nil
                        exporterLock.lock(); let wasCancelled = cancelledAll; exporterLock.unlock()
                        if wasCancelled {
                            // 변환 취소: 이미 만든 파일은 버림
                            results.compactMap { ($0["uri"] as? String)?.replacingOccurrences(of: "file://", with: "") }
                                .forEach { try? FileManager.default.removeItem(atPath: $0) }
                            reject("CANCELLED", "User cancelled video conversion", nil)
                        } else {
                            resolve(results)
                        }
                        // 결과를 넘긴 뒤: 갤러리의 PHCachingImageManager 캐시·콜백 해제 (닫힘 애니메이션에는 영향 없음).
                        // 새 갤러리가 열려 있으면 그 화면이 미리 인코딩 중인 파일은 건드리지 않음
                        galleryVC?.releaseAfterReturn(discardPreparedVideos: self.currentGalleryVC == nil)
                    }
                }
            }

            let navigationController = UINavigationController(rootViewController: galleryVC)
            navigationController.modalPresentationStyle = .custom
            navigationController.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
            navigationController.transitioningDelegate = galleryVC.customTransitioningDelegate
            
            // navigationController.view.backgroundColor 설정 제거 (투명한 탑바 지원을 위함)
            
            let step3 = CFAbsoluteTimeGetCurrent()
            // Configure sheet presentation - 최소 설정만 사용 (기본 iOS 동작 보장)
            if #available(iOS 15.0, *) {
                if let sheet = navigationController.sheetPresentationController {
                    if #available(iOS 16.0, *) {
                        // iOS 16+: Use custom 60% detent
                        let customDetent = UISheetPresentationController.Detent.custom { context in
                            return context.maximumDetentValue * 0.6
                        }
                        
                        sheet.detents = [customDetent, .large()]
                    } else {
                        // iOS 15: Use medium and large detents
                        sheet.detents = [.medium(), .large()]
                    }
                    
                    sheet.prefersGrabberVisible = false
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    
                    if #available(iOS 16.0, *) {
                        sheet.preferredCornerRadius = 20
                    }
                    sheet.largestUndimmedDetentIdentifier = nil
                    
                    if #available(iOS 16.0, *) {
                        sheet.preferredCornerRadius = 20
                    }
                }
            }
            #if DEBUG
            print("🔵 [DEBUG] Sheet 설정 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step3))초")
            #endif
            
            let step4 = CFAbsoluteTimeGetCurrent()
            rootViewController.present(navigationController, animated: true)
            #if DEBUG
            print("🔵 [DEBUG] present 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step4))초")
            print("✅ [DEBUG] openGallery 전체 완료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
            #endif
        }
    }
    
    /// 동영상 변환 취소 (HUD 없이 앱이 말풍선에서 취소할 때). index 생략(-1) = 남은 동영상 전부.
    /// 취소된 동영상은 onImageProcessed / 결과에 { error: "CANCELLED", cancelled: true } 로 오고, 나머지는 계속 처리
    /// processingId 생략("") = 가장 최근 처리
    @objc(cancelVideoProcessing:processingId:resolve:reject:)
    func cancelVideoProcessing(_ index: NSNumber, processingId: NSString, resolve: @escaping RCTPromiseResolveBlock,
                               reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            let id = processingId.length > 0 ? processingId as String : self.lastProcessingId
            guard let id = id, let job = self.processingJobs[id] else { resolve(false); return }
            let i = index.intValue
            job.cancel(index: i >= 0 ? i : nil)
            resolve(true)
        }
    }

    /// onProcessingStart 의 한 자리: 사진은 예상 결과 크기, 동영상은 예상 결과 크기·길이(구간 반영)·포스터(크롭·그리기 반영 jpg)
    private func processingStartItem(index: Int, asset: PHAsset?, image: UIImage?, videoStates: [String: VideoEditState],
                                     videoOptions: VideoExportOptions, maxWidth: Int, maxHeight: Int, tempDir: String) -> [String: Any] {
        if let a = asset, a.mediaType == .video {
            let state = videoStates[a.localIdentifier] ?? VideoEditState.defaultState(for: a, options: videoOptions)
            let d = CGSize(width: a.pixelWidth, height: a.pixelHeight)
            let size = VideoExporter.predictedOutputSize(displaySize: d, state: state, options: videoOptions, sourceDuration: a.duration)
            var item: [String: Any] = [
                "index": index, "mediaType": "video", "originalUri": "ph://\(a.localIdentifier)",
                "width": Int(size.width), "height": Int(size.height),
                "duration": state.outputDuration(sourceDuration: a.duration),
            ]
            if let poster = image {
                let edited = state.applyEdits(to: poster)
                if let encoded = VideoExporter.encodePoster(edited, format: videoOptions.posterFormat, quality: 0.8) {
                    let path = (tempDir as NSString).appendingPathComponent("turbo_video_poster_\(Int(Date().timeIntervalSince1970 * 1000))_\(index).\(encoded.fileExtension)")
                    if (try? encoded.data.write(to: URL(fileURLWithPath: path))) != nil {
                        item["thumbnailUri"] = "file://" + path
                        item["thumbnailWidth"] = Int(edited.size.width * edited.scale)
                        item["thumbnailHeight"] = Int(edited.size.height * edited.scale)
                    }
                }
            }
            return item
        }
        // 사진: 리사이즈 규칙(resizeImage)과 같은 예상 크기 (resizeImage 처럼 image.size 기준)
        var w = image?.size.width ?? CGFloat(asset?.pixelWidth ?? 0)
        var h = image?.size.height ?? CGFloat(asset?.pixelHeight ?? 0)
        if w > 0, h > 0 {
            var ratio: CGFloat = 1
            if maxWidth > 0 && maxHeight > 0 { ratio = min(CGFloat(maxWidth) / w, CGFloat(maxHeight) / h, 1) }
            else if maxWidth > 0 { ratio = min(CGFloat(maxWidth) / w, 1) }
            else if maxHeight > 0 { ratio = min(CGFloat(maxHeight) / h, 1) }
            w *= ratio; h *= ratio
        }
        var item: [String: Any] = ["index": index, "mediaType": "image", "width": Int(w.rounded()), "height": Int(h.rounded())]
        if let a = asset { item["originalUri"] = "ph://\(a.localIdentifier)" }
        return item
    }

    /// 동영상 포스터 (긴 변 512, 동기) — 처리 시작 이벤트용
    private static func requestPoster(_ asset: PHAsset) -> UIImage? {
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        var out: UIImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFit, options: o) { img, _ in
            out = img
        }
        return out
    }

    @objc
    func closeGallery(_ resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) -> Void {
        
        DispatchQueue.main.async { [weak self] () -> Void in
            guard let self = self else {
                reject("ERROR", "Module deallocated", nil)
                return
            }
            
            guard let galleryVC = self.currentGalleryVC else {
                reject("ERROR", "Gallery is not open", nil)
                return
            }
            
            // openGallery 약속이 아직 안 풀렸으면 (닫기 버튼과 같은 경로로) 취소를 먼저 전달 → reject("CANCELLED")
            // 안 그러면 아래 cleanupMemory 가 콜백을 지워 버려 JS 약속이 영영 안 풀렸습니다.
            if !galleryVC.hasReturnedImages {
                galleryVC.hasReturnedImages = true
                galleryVC.onImagesSelected?([])
            }

            // 갤러리 닫기 전 강제 정리
            galleryVC.forceCleanupBeforeDismiss()
            
            // 갤러리 닫기
            galleryVC.dismiss(animated: true) { [weak self] in
                // dismiss 완료 후 참조 정리
                self?.currentGalleryVC = nil
                resolve(true)
            }
        }
    }
    
    // MARK: - Private Methods

    /// iOS가 저장 공간 부족 시 자동으로 정리하는 캐시 디렉토리
    /// picker 결과물은 일시적으로만 필요하므로 cache 사용
    private var cacheDirectory: String {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("RNAttachmentKit").path
            ?? NSTemporaryDirectory()
    }

    /// 캐시 디렉토리 준비 (없으면 생성)
    private func prepareCacheDirectory() -> String {
        let dir = cacheDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // 이미지 리사이징 (비율 유지)
    private func resizeImage(_ image: UIImage, maxWidth: Int, maxHeight: Int) -> UIImage? {
        let originalSize = image.size
        var targetSize = originalSize
        
        // maxWidth와 maxHeight 둘 다 사용 (기본값 500이므로 항상 리사이징)
        if maxWidth > 0 && maxHeight > 0 {
            // 둘 다 설정된 경우: 더 작은 비율로 리사이징
            let widthRatio = CGFloat(maxWidth) / originalSize.width
            let heightRatio = CGFloat(maxHeight) / originalSize.height
            let ratio = min(widthRatio, heightRatio, 1.0) // 1.0 이상이면 리사이징 안 함
            
            if ratio < 1.0 {
                targetSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
            }
        } else if maxWidth > 0 && originalSize.width > CGFloat(maxWidth) {
            // maxWidth만 설정된 경우
            let ratio = CGFloat(maxWidth) / originalSize.width
            targetSize = CGSize(width: CGFloat(maxWidth), height: originalSize.height * ratio)
        } else if maxHeight > 0 && originalSize.height > CGFloat(maxHeight) {
            // maxHeight만 설정된 경우
            let ratio = CGFloat(maxHeight) / originalSize.height
            targetSize = CGSize(width: originalSize.width * ratio, height: CGFloat(maxHeight))
        } else {
            // 리사이징 불필요
            return nil
        }
        
        // 같은 크기면 리사이징 안 함
        if targetSize.width >= originalSize.width && targetSize.height >= originalSize.height {
            return nil
        }
        
        // 이미지 리사이징 (UIGraphicsImageRenderer 방식 - 메모리 최적화)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 실제 픽셀 크기로 저장하기 위함
        format.opaque = false
        if #available(iOS 12.0, *) {
            format.preferredRange = .standard // 광색역 대신 표준 색역 사용으로 메모리 절약
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    // ✅ 2순위: 원본 이미지를 JPEG으로 저장 (WebP 인코딩 없음 → 빠름)
    // 카메라 촬영본 및 에디터 결과물에 사용
    private func saveOriginalImageAsJPEG(_ image: UIImage, index: Int, timestamp: Int, tempDir: String) -> String? {
        let fileName = "turbo_picker_original_\(timestamp)_\(index).jpg"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)

        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            do {
                try jpegData.write(to: fileURL, options: [.atomic])
                return fileURL.absoluteString
            } catch {
                print("❌ [TurboImagePicker] JPEG 원본 이미지 저장 실패: \(error)")
            }
        }
        return nil
    }
    
    // 리사이즈된 이미지 저장 (WebP 포맷)
    private func saveResizedImage(_ image: UIImage, index: Int, timestamp: Int, tempDir: String) -> String? {
        let fileName = "turbo_picker_resized_\(timestamp)_\(index).webp"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)
        
        if let data = encodeWebP(image: image, quality: 0.85) {
            do {
                try data.write(to: fileURL, options: [.atomic])
                return fileURL.absoluteString
            } catch {
                print("❌ [TurboImagePicker] WebP 리사이즈 이미지 저장 실패: \(error)")
            }
        }
        // Fallback to JPEG
        if let jpegData = image.jpegData(compressionQuality: 0.85) {
            let fallbackPath = (tempDir as NSString).appendingPathComponent("turbo_picker_resized_\(timestamp)_\(index).jpg")
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            do {
                try jpegData.write(to: fallbackURL, options: [.atomic])
                return fallbackURL.absoluteString
            } catch {}
        }
        return nil
    }
    // WebP 인코딩 - iOS 16+ 네이티브 CGImageDestination 사용 또는 런타임 Fallback
    private func encodeWebP(image: UIImage, quality: CGFloat) -> Data? {
        if #available(iOS 16.0, *) {
            if let cgImage = image.cgImage {
                let data = NSMutableData()
                if let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.webp" as CFString, 1, nil) {
                    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
                    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                    if CGImageDestinationFinalize(destination) {
                        #if DEBUG
                        NSLog("✅ [encodeWebP] iOS 16 네이티브 WebP 인코딩 성공 - %d bytes", data.length)
                        #endif
                        return data as Data
                    }
                }
            }
        }
        
        #if DEBUG
        NSLog("🟣 [encodeWebP] SDImageWebPCoder 런타임 폴백 시도")
        #endif
        // iOS 14, 15이거나 네이티브 실패 시 SDImageWebPCoder 런타임 호출
        if let coderClass = NSClassFromString("SDImageWebPCoder") as? NSObject.Type {
            if coderClass.responds(to: NSSelectorFromString("sharedCoder")) {
                let sharedCoder = coderClass.perform(NSSelectorFromString("sharedCoder")).takeUnretainedValue()
                let encodeSel = NSSelectorFromString("encodedDataWithImage:format:options:")
                
                if sharedCoder.responds(to: encodeSel),
                   let method = class_getInstanceMethod(type(of: sharedCoder), encodeSel) {
                    
                    // ObjC method signature: - (NSData *)encodedDataWithImage:(UIImage *)image format:(NSInteger)format options:(NSDictionary *)options
                    typealias EncodeFunc = @convention(c) (AnyObject, Selector, UIImage?, Int, [String: Any]?) -> Data?
                    let implementation = method_getImplementation(method)
                    let encode = unsafeBitCast(implementation, to: EncodeFunc.self)
                    
                    // format: 3 (SDImageFormatWebP)
                    let options: [String: Any] = ["encodeCompressionQuality": quality]
                    if let data = encode(sharedCoder, encodeSel, image, 3, options) {
                        #if DEBUG
                        NSLog("✅ [encodeWebP] SDImageWebPCoder 런타임 인코딩 성공 - %d bytes", data.count)
                        #endif
                        return data
                    } else {
                        NSLog("❌ [encodeWebP] SDImageWebPCoder 런타임 인코딩 실패 (nil 반환)")
                    }
                } else {
                    NSLog("❌ [encodeWebP] SDImageWebPCoder에 encodedDataWithImage:format:options: 메서드가 없습니다.")
                }
            } else {
                NSLog("❌ [encodeWebP] SDImageWebPCoder에 sharedCoder가 없습니다.")
            }
        } else {
            NSLog("❌ [encodeWebP] SDImageWebPCoder 클래스를 찾을 수 없습니다.")
        }

        NSLog("❌ [encodeWebP] 모든 WebP 인코딩 실패 → nil 반환")
        return nil
    }


    // MARK: - Format-aware save helpers

    /// outputFormat("webp"|"jpg"|"png")에 맞는 MIME 타입 반환
    private func mimeType(for format: String) -> String {
        switch format {
        case "png":  return "image/png"
        case "jpg":  return "image/jpeg"
        default:     return "image/webp"
        }
    }

    /// 이미지를 지정 포맷으로 저장하고 file:// URI 반환
    /// - Parameters:
    ///   - image: 저장할 UIImage
    ///   - format: "webp" | "jpg" | "png"
    ///   - prefix: 파일명 prefix (e.g. "resized", "original")
    ///   - index: 배치 내 인덱스
    ///   - timestamp: 타임스탬프(ms)
    ///   - tempDir: 저장 디렉토리 경로
    private func saveImage(_ image: UIImage, format: String,
                           prefix: String, index: Int,
                           timestamp: Int, tempDir: String, forceJPEG: Bool = false) -> String? {
        let ext: String
        let data: Data?

        let actualFormat = forceJPEG ? "jpg" : format

        switch actualFormat {
        case "png":
            ext = "png"
            data = image.pngData()
        case "jpg":
            ext = "jpg"
            data = image.jpegData(compressionQuality: 0.9)
        default: // "webp"
            ext = "webp"
            data = encodeWebP(image: image, quality: 0.85)
        }

        guard let imageData = data else {
            // WebP 인코딩 실패 시 JPEG fallback
            if format == "webp", let fallbackData = image.jpegData(compressionQuality: 0.85) {
                let path = (tempDir as NSString).appendingPathComponent(
                    "turbo_picker_\(prefix)_\(timestamp)_\(index).jpg")
                let url = URL(fileURLWithPath: path)
                try? fallbackData.write(to: url)
                return url.absoluteString
            }
            return nil
        }

        let fileName = "turbo_picker_\(prefix)_\(timestamp)_\(index).\(ext)"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL  = URL(fileURLWithPath: filePath)

        do {
            try imageData.write(to: fileURL)
            return fileURL.absoluteString
        } catch {
            print("❌ [TurboImagePicker] \(format.uppercased()) 저장 실패: \(error)")
            return nil
        }
    }

    
    /// 저장된 파일 경로에서 fileName, fileExtension, fileSize 반환
    private func fileMetadata(fromPath filePath: String) -> (fileName: String, fileExtension: String, fileSize: Int64) {
        let url = URL(fileURLWithPath: filePath.hasPrefix("file://")
            ? String(filePath.dropFirst(7))
            : filePath)
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return (fileName, fileExtension, fileSize)
    }
    
    private func getRootViewController() -> UIViewController? {
        var rootViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                rootViewController = window.rootViewController
            }
        }
        
        if rootViewController == nil {
            rootViewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
        
        if rootViewController == nil {
            rootViewController = UIApplication.shared.keyWindow?.rootViewController
        }
        
        // Handle presented view controllers
        while let presented = rootViewController?.presentedViewController {
            rootViewController = presented
        }
        
        return rootViewController
    }
    
    // MARK: - Editor Result Processing

    /// 동영상 1장을 전송용 mp4 로 만들어 resolve (갤러리 다중 전송 경로의 동영상 분기와 같은 필드)
    private func exportSingleVideo(_ phAsset: PHAsset, galleryVC: GalleryViewController?, tempDir: String,
                                   resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let videoOptions = galleryVC?.videoExportOptions ?? VideoExportOptions()
        let state = galleryVC?.videoEditStates[phAsset.localIdentifier] ?? VideoEditState.defaultState(for: phAsset, options: videoOptions)
        let hud: VideoExportHUD? = galleryShowsVideoHUD ? VideoExportHUD.show(accent: galleryVC?.parsedThemeColor ?? UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1), languageCode: galleryVC?.languageCode ?? "en") : nil
        let exporter = VideoExporter()
        let hudCancelled = AtomicFlag()
        hud?.onCancel = { hudCancelled.value = true; exporter.cancel() }
        let job = MediaProcessingJob()
        let processingId = UUID().uuidString
        processingJobs[processingId] = job
        lastProcessingId = processingId
        DispatchQueue.global(qos: .userInitiated).async {
            let poster = Self.requestPoster(phAsset)
            self.sendEvent(withName: "onProcessingStart", body: [
                "processingId": processingId,
                "total": 1,
                "items": [self.processingStartItem(index: 0, asset: phAsset, image: poster, videoStates: [phAsset.localIdentifier: state],
                                                   videoOptions: videoOptions, maxWidth: 0, maxHeight: 0, tempDir: tempDir)],
            ])
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            var result: [String: Any] = [
                "originalUri":    "ph://\(phAsset.localIdentifier)",
                "originalWidth":  phAsset.pixelWidth,
                "originalHeight": phAsset.pixelHeight,
                "mediaType":      "video",
                "type":           "video/mp4",
                "duration":       phAsset.duration,
            ]
            do {
                job.begin(index: 0, exporter: exporter)
                let throttle = ProgressThrottle()
                let onProgress: (Double) -> Void = { p in
                    guard throttle.shouldSend(p) else { return }
                    DispatchQueue.main.async { hud?.update(progress: p, index: 0, total: 1) }
                    self.sendEvent(withName: "onVideoProgress", body: ["index": 0, "total": 1, "progress": p, "processingId": processingId])
                }
                let r: VideoExportResult
                // HUD 취소는 exporter.cancel() — 기다리는 동안엔 job 으로 알 수 없으므로 HUD 취소도 job 에 기록
                if let ready = VideoPrepareManager.shared.takeReady(asset: phAsset, state: state, progress: onProgress,
                                                                     isCancelled: { job.isCancelled(0) || hudCancelled.value }) {
                    r = ready; onProgress(1)
                } else {
                    if job.isCancelled(0) || hudCancelled.value { throw VideoExporter.ExportError.cancelled }
                    r = try exporter.export(asset: phAsset, state: state, options: videoOptions,
                                            outputDir: URL(fileURLWithPath: tempDir), baseName: "turbo_video_\(timestamp)_0", progress: onProgress)
                }
                result["uri"]           = "file://" + r.url.path
                result["width"]         = r.width
                result["height"]        = r.height
                result["duration"]      = r.duration
                result["fileSize"]      = r.fileSize
                result["fileName"]      = r.url.lastPathComponent
                result["fileExtension"] = "mp4"
                result["videoCodec"]    = r.codec
                result["videoBitrate"]  = r.bitrate
                result["edited"]        = !r.passthrough
                if let t = r.thumbnailURL {
                    result["thumbnailUri"]    = "file://" + t.path
                    result["thumbnailWidth"]  = r.thumbnailWidth
                    result["thumbnailHeight"] = r.thumbnailHeight
                }
                if job.isCancelled(0) { throw VideoExporter.ExportError.cancelled }
            } catch VideoExporter.ExportError.cancelled where job.isCancelled(0) {
                // 앱이 취소 (cancelVideoProcessing) — 이벤트·결과에 cancelled 로
                result["error"] = "CANCELLED"
                result["cancelled"] = true
            } catch VideoExporter.ExportError.cancelled {
                job.end()
                DispatchQueue.main.async {
                    self.processingJobs[processingId] = nil
                    hud?.dismiss(); reject("CANCELLED", "Video export cancelled", nil)
                }
                return
            } catch {
                result["error"] = error.localizedDescription
            }
            job.end()
            self.sendEvent(withName: "onImageProcessed", body: ["index": 0, "total": 1, "image": result, "processingId": processingId])
            DispatchQueue.main.async {
                hud?.dismiss()
                if self.currentGalleryVC == nil || self.currentGalleryVC === galleryVC { self.currentGalleryVC = nil }
                self.processingJobs[processingId] = nil
                galleryVC?.releaseAfterReturn(discardPreparedVideos: self.currentGalleryVC == nil)
                resolve([result])
            }
        }
    }

    
    private func processEditorResult(asset: PHAsset?, croppedImage: UIImage?, filterState: FilterState, caption: String, galleryVC: GalleryViewController?, targetMaxWidth: Int? = nil, targetMaxHeight: Int? = nil, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let tempDir = prepareCacheDirectory()
        // 동영상 1장 편집 → 전송: 편집 화면에서 고른 품질·음소거로 VideoExporter (사진 경로와 같은 결과 형태)
        if let phAsset = asset, phAsset.mediaType == .video {
            exportSingleVideo(phAsset, galleryVC: galleryVC, tempDir: tempDir, resolve: resolve, reject: reject)
            return
        }
        let maxWidth = targetMaxWidth ?? galleryVC?.maxWidth ?? 1024
        let maxHeight = targetMaxHeight ?? galleryVC?.maxHeight ?? 1024
        let format = galleryVC?.outputFormat ?? "webp"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let photoManager = PhotoManager.shared
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            
            let originalUri = asset != nil ? "ph://\(asset!.localIdentifier)" : ""
            var originalFilePath: String? = nil
            var resultImage: UIImage? = nil
            
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            
            let handleBaseImage = { (baseImage: UIImage) in
                var finalImage = baseImage
                
                if filterState.filterId != "original", let filter = FilterManager.shared.filters.first(where: { $0.id == filterState.filterId }) {
                    if let ciImage = CIImage(image: baseImage),
                       let out = filter.apply(ciImage, filterState.intensity),
                       let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                        finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                    }
                }
                
                finalImage = ImageProcessor.shared.applyWatermarkIfNeeded(finalImage)
                resultImage = finalImage
                // ✅ 2순위: 에디터 결과 원본 저장 (WebP 소프트웨어 인코딩 방지를 위해 하드웨어 가속되는 JPG 강제 사용)
                originalFilePath = self.saveImage(finalImage, format: format, prefix: "original", index: 0, timestamp: timestamp, tempDir: tempDir, forceJPEG: true)
                dispatchGroup.leave()
            }
            
            let targetSize = (maxWidth > 0 && maxHeight > 0) ? CGSize(width: maxWidth, height: maxHeight) : PHImageManagerMaximumSize
            
            if let cropped = croppedImage {
                handleBaseImage(cropped)
            } else {
                _ = photoManager.requestFullImage(for: asset!, targetSize: targetSize, progressHandler: nil) { fullImage in
                    if let fullImage = fullImage {
                        handleBaseImage(fullImage)
                    } else {
                        dispatchGroup.leave()
                    }
                }
            }
            
            dispatchGroup.wait()
            
            guard let image = resultImage else {
                DispatchQueue.main.async {
                    self.currentGalleryVC = nil
                    reject("ERROR", "Failed to load image from editor", nil)
                    galleryVC?.releaseAfterReturn()
                }
                return
            }
            
            let originalSize = image.size
            
            var result: [String: Any] = [
                "originalUri": originalUri,
                "originalWidth": Int(originalSize.width),
                "originalHeight": Int(originalSize.height),
                "type": self.mimeType(for: format),
                "caption": caption
            ]
            
            if let originalFilePath = originalFilePath {
                result["originalFileUri"] = originalFilePath
                result["uri"] = originalFilePath // 기본적으로 uri에도 파일 경로 저장
                let meta = self.fileMetadata(fromPath: originalFilePath)
                result["fileName"] = meta.fileName
                result["fileExtension"] = meta.fileExtension
                result["fileSize"] = meta.fileSize
            }
            
            let finalImageForFormat = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) ?? image
            
            if let finalUri = self.saveImage(finalImageForFormat, format: format, prefix: "final", index: 0, timestamp: timestamp, tempDir: tempDir) {
                result["uri"] = finalUri
                result["width"] = Int(finalImageForFormat.size.width)
                result["height"] = Int(finalImageForFormat.size.height)
                let finalMeta = self.fileMetadata(fromPath: finalUri)
                result["fileName"] = finalMeta.fileName
                result["fileExtension"] = finalMeta.fileExtension
                result["fileSize"] = finalMeta.fileSize
            }
            
            DispatchQueue.main.async {
                self.currentGalleryVC = nil
                resolve([result])
                galleryVC?.releaseAfterReturn()
            }
        }
    }


    private func processEditorResultMulti(assets: [PHAsset], croppedImages: [PHAsset: UIImage], filterStates: [PHAsset: FilterState], galleryVC: GalleryViewController, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let tempDir = prepareCacheDirectory()
        let maxWidth = galleryVC.maxWidth
        let maxHeight = galleryVC.maxHeight
        let format = galleryVC.outputFormat
        
        DispatchQueue.global(qos: .userInitiated).async {
            let photoManager = PhotoManager.shared
            var results: [[String: Any]] = []
            let resultsLock = NSLock()
            
            // 한 장씩 순서대로 처리 (동시에 전부 디코딩하면 메모리가 치솟음). 해상도는 줄이지 않음
            for (index, asset) in assets.enumerated() {
              autoreleasepool {
                let dispatchGroup = DispatchGroup()
                dispatchGroup.enter()
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                let originalUri = "ph://\(asset.localIdentifier)"
                let filterState = filterStates[asset] ?? FilterState(filterId: "original", intensity: 1.0)
                let croppedImage = croppedImages[asset]
                
                let handleBaseImage = { (baseImage: UIImage) in
                    var finalImage = baseImage
                    
                    if filterState.filterId != "original", let filter = FilterManager.shared.filters.first(where: { $0.id == filterState.filterId }) {
                        if let ciImage = CIImage(image: baseImage),
                           let out = filter.apply(ciImage, filterState.intensity),
                           let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                            finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                        }
                    }
                    
                    finalImage = ImageProcessor.shared.applyWatermarkIfNeeded(finalImage)
                    
                    var result: [String: Any] = [
                        "originalUri": originalUri,
                        "originalWidth": Int(finalImage.size.width),
                        "originalHeight": Int(finalImage.size.height),
                        "type": self.mimeType(for: format)
                    ]
                    
                    // ✅ 2순위: 에디터 다중 결과 원본 저장 (JPG 강제 사용으로 속도 최적화)
                    if let originalFilePath = self.saveImage(finalImage, format: format, prefix: "original", index: index, timestamp: timestamp, tempDir: tempDir, forceJPEG: true) {
                        result["originalFileUri"] = originalFilePath
                        result["uri"] = originalFilePath // 기본적으로 uri에도 파일 경로 저장
                        let meta = self.fileMetadata(fromPath: originalFilePath)
                        result["fileName"] = meta.fileName
                        result["fileExtension"] = meta.fileExtension
                        result["fileSize"] = meta.fileSize
                    }
                    
                    if (maxWidth > 0 || maxHeight > 0), let resizedImage = self.resizeImage(finalImage, maxWidth: maxWidth, maxHeight: maxHeight) {
                        if let resizedUri = self.saveImage(resizedImage, format: format, prefix: "resized", index: index, timestamp: timestamp, tempDir: tempDir) {
                            result["uri"] = resizedUri
                            result["width"] = Int(resizedImage.size.width)
                            result["height"] = Int(resizedImage.size.height)
                            let resizedMeta = self.fileMetadata(fromPath: resizedUri)
                            result["fileName"] = resizedMeta.fileName
                            result["fileExtension"] = resizedMeta.fileExtension
                            result["fileSize"] = resizedMeta.fileSize
                        }
                    }
                    
                    resultsLock.lock()
                    results.append(result)
                    let currentResult = result
                    resultsLock.unlock()
                    
                    self.sendEvent(withName: "onImageProcessed", body: [
                        "index": index,
                        "total": assets.count,
                        "image": currentResult
                    ])
                    dispatchGroup.leave()
                }
                
                let targetSize = (maxWidth > 0 && maxHeight > 0) ? CGSize(width: maxWidth, height: maxHeight) : PHImageManagerMaximumSize
                
                if let cropped = croppedImage {
                    handleBaseImage(cropped)
                } else {
                    _ = photoManager.requestFullImage(for: asset, targetSize: targetSize, progressHandler: nil) { fullImage in
                        if let fullImage = fullImage {
                            handleBaseImage(fullImage)
                        } else {
                            dispatchGroup.leave()
                        }
                    }
                }
                dispatchGroup.wait()
              } // end autoreleasepool
            }
            
            DispatchQueue.main.async {
                self.currentGalleryVC = nil
                if results.isEmpty {
                    reject("ERROR", "Failed to load images from editor", nil)
                } else {
                    // 순서를 유지하기 위해
                    resolve(results)
                }
                galleryVC.releaseAfterReturn()
            }
        }
    }
}

// MARK: - UIColor Extension for Hex Support
extension UIColor {
    convenience init?(hexString: String) {
        var cString: String = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.remove(at: cString.startIndex) }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        if cString.count == 6 {
            self.init(
                red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if cString.count == 8 {
            self.init(
                red: CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgbValue & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}

// MARK: - Media Gallery (사진 모아보기)

extension RNAttachmentKit {

    /// openMediaGallery(options) → { galleryId }
    /// - dataSource: 등록된 네이티브 데이터 소스 이름 (MediaGalleryRegistry) — 페이지 요청이 JS 를 거치지 않음
    /// - initialItems / nextCursor / hasMore: JS 공급 방식 (끝에 가까우면 onGalleryNeedPage → appendGalleryItems)
    @objc
    func openMediaGallery(_ options: NSDictionary,
                          resolve: @escaping RCTPromiseResolveBlock,
                          reject: @escaping RCTPromiseRejectBlock) -> Void {
        let o = options as? [String: Any] ?? [:]
        DispatchQueue.main.async {
            let config = MediaGalleryConfig(dictionary: o)
            let galleryId = config.galleryId
            if self.mediaGalleries[galleryId] != nil {
                reject("E_GALLERY_OPEN", "Media gallery '\(galleryId)' is already open", nil)
                return
            }
            let store: MediaGalleryStore
            if let name = o["dataSource"] as? String, !name.isEmpty {
                guard let dataSource = MediaGalleryRegistry.source(named: name) else {
                    reject("E_NO_DATA_SOURCE", "Media gallery data source '\(name)' is not registered", nil)
                    return
                }
                let params = o["dataSourceParams"] as? [String: Any] ?? [:]
                store = MediaGalleryStore(galleryId: galleryId, source: .native(dataSource, params: params))
            } else {
                let raw = o["initialItems"] as? [[String: Any]] ?? []
                let items = raw.compactMap { MediaGalleryItem(dictionary: $0) }
                let hasMore = (o["hasMore"] as? NSNumber)?.boolValue ?? false
                store = MediaGalleryStore(galleryId: galleryId, source: .javascript, initialItems: items,
                                          nextCursor: o["nextCursor"] as? String, hasMore: hasMore)
                store.onNeedPage = { [weak self] cursor in
                    let body: [String: Any] = ["galleryId": galleryId, "cursor": cursor.map { $0 as Any } ?? NSNull()]
                    self?.sendEvent(withName: "onGalleryNeedPage", body: body)
                }
            }
            guard let root = self.getRootViewController() else {
                reject("E_NO_ROOT", "No root view controller", nil)
                return
            }
            let vc = MediaGalleryViewController(store: store, config: config)
            vc.onClosed = { [weak self] in
                guard let self = self else { return }
                self.mediaGalleries.removeValue(forKey: galleryId)
                self.sendEvent(withName: "onGalleryClosed", body: ["galleryId": galleryId])
            }
            // 뷰어에서 삭제를 고르면: 모듈은 그 묶음을 그리드·뷰어에서 지우고, 실제 삭제는 앱이 하도록 이벤트만 보냄
            vc.onItemDeleted = { [weak self] item, option in
                var body: [String: Any] = ["galleryId": galleryId, "id": item.id, "groupId": item.groupId]
                body["option"] = option.map { $0 as Any } ?? NSNull()
                self?.sendEvent(withName: "onGalleryItemDeleted", body: body)
            }
            // 상단 바 메뉴에서 그리드 크기를 바꾸면 (모듈이 기기에 저장, 앱에도 알림)
            vc.onGridSizeChanged = { [weak self] columns in
                self?.sendEvent(withName: "onGalleryGridSizeChanged",
                                body: ["galleryId": galleryId, "gridSize": MediaGalleryGridPreference.gridSizeString(columns)])
            }
            self.mediaGalleries[galleryId] = vc
            // 피커 갤러리와 같은 바텀시트로 표시
            root.present(vc.makePresentableController(), animated: true)
            resolve(["galleryId": galleryId])
        }
    }

    @objc
    func closeMediaGallery(_ galleryId: String,
                           resolve: @escaping RCTPromiseResolveBlock,
                           reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            guard let vc = self.mediaGalleries[galleryId] else {
                resolve(nil)
                return
            }
            // 갤러리 위에 띄운 화면(뷰어 등)까지 함께 닫음
            if let presenting = vc.navigationController?.presentingViewController ?? vc.presentingViewController {
                presenting.dismiss(animated: true) { resolve(nil) }
            } else {
                resolve(nil)
            }
        }
    }

    /// JS 공급 방식: { galleryId, items, nextCursor?, hasMore }
    @objc
    func appendGalleryItems(_ payload: NSDictionary,
                            resolve: @escaping RCTPromiseResolveBlock,
                            reject: @escaping RCTPromiseRejectBlock) -> Void {
        let p = payload as? [String: Any] ?? [:]
        let galleryId = p["galleryId"] as? String ?? ""
        let raw = p["items"] as? [[String: Any]] ?? []
        let items = raw.compactMap { MediaGalleryItem(dictionary: $0) }
        let page = MediaGalleryPage(items: items, nextCursor: p["nextCursor"] as? String,
                                    hasMore: (p["hasMore"] as? NSNumber)?.boolValue ?? false)
        DispatchQueue.main.async {
            self.mediaGalleries[galleryId]?.store.appendExternal(page)
            resolve(nil)
        }
    }

    /// 앱이 다른 경로로 지운 묶음 반영: { galleryId, groupIds }
    @objc
    func removeGalleryItems(_ payload: NSDictionary,
                            resolve: @escaping RCTPromiseResolveBlock,
                            reject: @escaping RCTPromiseRejectBlock) -> Void {
        let p = payload as? [String: Any] ?? [:]
        let galleryId = p["galleryId"] as? String ?? ""
        let groupIds = (p["groupIds"] as? [Any] ?? []).compactMap { v -> String? in
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        DispatchQueue.main.async {
            self.mediaGalleries[galleryId]?.store.removeGroups(Set(groupIds))
            resolve(nil)
        }
    }
}

#if RCT_NEW_ARCH_ENABLED
// MARK: - Turbo Module Protocol Conformance (New Architecture)
// extension RNAttachmentKit: RCTTurboModule {
//    // Turbo Module specific implementation if needed
// }
#endif
import Foundation
import UIKit


fileprivate func _turbo_handleConfirmMulti(assets: [PHAsset], croppedImages: [PHAsset: UIImage], filterStates: [PHAsset: FilterState], currentGallery: GalleryViewController) {
    DispatchQueue.global(qos: .userInitiated).async {
        var newlyEditedAssets: [PHAsset] = []
        for asset in assets {
            if let baseImage = croppedImages[asset] {
                var finalImage = baseImage
                if let state = filterStates[asset], state.filterId != "original" {
                    if let filter = FilterManager.shared.filters.first(where: { (f: ImageFilter) -> Bool in return f.id == state.filterId }) {
                        if let ciImage = CIImage(image: baseImage) {
                            if let out = filter.apply(ciImage, state.intensity) {
                                if let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                                    finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    currentGallery.editedImages[asset.localIdentifier] = finalImage
                }
                newlyEditedAssets.append(asset)
            }
        }
        DispatchQueue.main.async {
            for asset in newlyEditedAssets {
                if !currentGallery.selectedAssetsSet.contains(asset.localIdentifier) {
                    if currentGallery.maxSelection == 0 || currentGallery.selectedAssets.count < currentGallery.maxSelection {
                        currentGallery.selectedAssets.append(asset)
                        currentGallery.selectedAssetsSet.insert(asset.localIdentifier)
                    }
                }
            }
            currentGallery.refreshSelectionAfterEdit()
            
            // These updates are required per the original code
            currentGallery.updateSelectedCellNumbers()
            currentGallery.notifySelectionChanged()
            currentGallery.updateNavigationBarForSelection()
        }
    }
}

fileprivate extension RNAttachmentKit {
    func _turbo_handleSingleImageTappedForEdit(asset: PHAsset, sourceFrame: CGRect, sourceImage: UIImage?, options: NSDictionary, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let currentGallery = self.currentGalleryVC else { return }
        let galleryNav = currentGallery.navigationController
        let isMultiSelect = currentGallery.forceMultiMode || (currentGallery.maxSelection != 1 && currentGallery.maxSelection != 0)

        let editorVC = ImageEditorViewController()
        editorVC.languageCode = options["languageCode"] as? String ?? "en"
        var editorAssets = currentGallery.allAssets
        var targetIndex = 0
        if let idx = editorAssets.firstIndex(of: asset) {
            targetIndex = idx
        } else {
            editorAssets.insert(asset, at: 0)
            targetIndex = 0
        }
        
        editorVC.allAssets = editorAssets
        editorVC.currentIndex = targetIndex
        editorVC.selectedAssets = currentGallery.selectedAssets
        
        editorVC.onSelectionToggled = { [weak currentGallery] (toggledAsset, isSelected) in
            guard let currentGallery = currentGallery else { return }
            if isSelected {
                if !currentGallery.selectedAssets.contains(toggledAsset) {
                    currentGallery.selectedAssets.append(toggledAsset)
                    currentGallery.selectedAssetsSet.insert(toggledAsset.localIdentifier)
                }
            } else {
                currentGallery.selectedAssetsSet.remove(toggledAsset.localIdentifier)
                currentGallery.selectedAssets.removeAll(where: { $0.localIdentifier == toggledAsset.localIdentifier })
            }
            currentGallery.refreshSelectionAfterEdit()
            currentGallery.updateSelectedCellNumbers()
            currentGallery.notifySelectionChanged()
            currentGallery.updateNavigationBarForSelection()
        }
        
        editorVC.onEditDeleted = { [weak currentGallery] asset in
            currentGallery?.editedImages.removeValue(forKey: asset.localIdentifier)
            currentGallery?.videoEditStates.removeValue(forKey: asset.localIdentifier)  // 동영상 편집도 기본으로 돌아간 것
        }
        
        editorVC.modalPresentationStyle = .overFullScreen
        editorVC.overrideUserInterfaceStyle = RNAttachmentKit.interfaceStyle(options)
        editorVC.singlePhotoMode = !isMultiSelect
        // selectionMode 'multi' + 최대 1장: 편집 화면에서 다른 사진을 선택하면 기존 선택과 교체
        editorVC.replaceSelectionWhenFull = currentGallery.forceMultiMode && currentGallery.maxSelection == 1
        
        var initialCroppedImages: [Int: UIImage] = [:]
        for (i, a) in editorAssets.enumerated() {
            if let editedImg = currentGallery.editedImages[a.localIdentifier] {
                initialCroppedImages[i] = editedImg
            }
        }
        editorVC.croppedImages = initialCroppedImages
        // 동영상 페이지: 품질 단계·용량 상한 + 갤러리가 들고 있는 상태. 바뀌면 바로 갤러리에 반영 (전송 때 VideoExporter 가 읽음)
        editorVC.videoOptions = VideoExportOptions(dictionary: options["video"] as? [String: Any])
        var initialVideoStates: [Int: VideoEditState] = [:]
        for (i, a) in editorAssets.enumerated() {
            if let st = currentGallery.videoEditStates[a.localIdentifier] { initialVideoStates[i] = st }
        }
        editorVC.videoEditStates = initialVideoStates
        editorVC.onVideoStateChanged = { [weak currentGallery] asset, state in
            currentGallery?.videoEditStates[asset.localIdentifier] = state
        }
        
        if sourceFrame == .zero {
            // 기준 칸이 없을 때(칸이 화면 밖 등): 기본 전환(아래로 미끄러짐)은 끌어내려 닫을 때 위로 치워 둔 상단 바가
            // 화면과 함께 내려오며 보이므로 페이드로
            editorVC.modalTransitionStyle = .crossDissolve
        }
        if sourceFrame != .zero {
            self.editorTransitionDelegate = ImageEditorTransitionDelegate()
            self.editorTransitionDelegate?.sourceFrame = sourceFrame
            self.editorTransitionDelegate?.sourceImage = sourceImage
            
            if let editedImg = currentGallery.editedImages[asset.localIdentifier] {
                self.editorTransitionDelegate?.uncroppedImage = editedImg
                self.editorTransitionDelegate?.asset = nil
            } else {
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isSynchronous = true
                options.resizeMode = .fast
                var fastUncropped: UIImage? = nil
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFit, options: options) { img, _ in
                    fastUncropped = img
                }
                self.editorTransitionDelegate?.uncroppedImage = fastUncropped ?? sourceImage
                self.editorTransitionDelegate?.asset = asset
            }
            
            var ratio = CGFloat(asset.pixelWidth) / CGFloat(max(1, asset.pixelHeight))
            if let editedImg = currentGallery.editedImages[asset.localIdentifier] {
                ratio = editedImg.size.width / max(1.0, editedImg.size.height)
            }
            self.editorTransitionDelegate?.assetAspectRatio = ratio
            self.editorTransitionDelegate?.frameProvider = { [weak currentGallery] currentAsset in
                return currentGallery?.frameForAsset(currentAsset)
            }
            // sticky: 편집 화면이 열려 있는 동안 지금 사진의 갤러리 칸을 비워 두고(넘기면 따라감), 닫히면 다시 보이게
            self.editorTransitionDelegate?.onCurrentAssetChanged = { [weak currentGallery] currentAsset in
                currentGallery?.setHiddenAsset(currentAsset, scrollIntoView: true)
            }
            self.editorTransitionDelegate?.onEditorClosed = { [weak self, weak currentGallery] in
                currentGallery?.setHiddenAsset(nil)
                // 편집 화면이 닫혔으니 sourceImage/uncroppedImage 를 들고 있는 전환 델리게이트를 놓아 줌
                // (호출 중인 객체이므로 다음 런루프에서)
                DispatchQueue.main.async { self?.editorTransitionDelegate = nil }
            }
            // 칸은 열기 애니메이션의 첫 프레임에 비움 (누르자마자 비우면 편집 화면이 준비되는 동안 빈 칸이 번쩍임)
            self.editorTransitionDelegate?.onPresentationStarted = { [weak currentGallery] in
                currentGallery?.setHiddenAsset(asset)
            }
            
            editorVC.transitioningDelegate = self.editorTransitionDelegate
        }

        if let hex = currentGallery.themeColorHex, let color = UIColor(hexString: hex) {
            editorVC.themeColor = color
        }

        editorVC.onConfirmMulti = { [weak currentGallery, weak editorVC] (assets, croppedImages, filterStates) in
            guard let currentGallery = currentGallery else { return }
            
            editorVC?.dismiss(animated: true) {
                DispatchQueue.global(qos: .userInitiated).async {
                    var newlyEditedAssets: [PHAsset] = []
                    
                    for asset in assets {
                        if let baseImage = croppedImages[asset] {
                            var finalImage = baseImage
                            if let state = filterStates[asset],
                               state.filterId != "original",
                               let filter = FilterManager.shared.filters.first(where: { $0.id == state.filterId }),
                               let ciImage = CIImage(image: baseImage),
                               let out = filter.apply(ciImage, state.intensity),
                               let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                                finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                            }
                            
                            DispatchQueue.main.async {
                                currentGallery.editedImages[asset.localIdentifier] = finalImage
                            }
                            newlyEditedAssets.append(asset)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        for asset in newlyEditedAssets {
                            if !currentGallery.selectedAssetsSet.contains(asset.localIdentifier) {
                                if currentGallery.maxSelection == 0 || currentGallery.selectedAssets.count < currentGallery.maxSelection {
                                    currentGallery.selectedAssets.append(asset)
                                    currentGallery.selectedAssetsSet.insert(asset.localIdentifier)
                                }
                            }
                        }
                        currentGallery.updateSelectedCellNumbers()
                        currentGallery.notifySelectionChanged()
                        currentGallery.updateNavigationBarForSelection()
                        currentGallery.collectionView.reloadData()
                    }
                }
            }
        }

        // patch398: 편집 화면의 전송 버튼 — 편집본을 갤러리에 반영하고 선택한 사진을 바로 전송(편집 화면/갤러리 모두 닫힘)
        editorVC.onSendMulti = { [weak currentGallery, weak editorVC] (assets, croppedImages, filterStates) in
            guard let currentGallery = currentGallery else { return }
            for asset in assets {
                guard var img = croppedImages[asset] else { continue }
                if let state = filterStates[asset],
                   state.filterId != "original",
                   let filter = FilterManager.shared.filters.first(where: { $0.id == state.filterId }),
                   let ciImage = CIImage(image: img),
                   let out = filter.apply(ciImage, state.intensity),
                   let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                    img = UIImage(cgImage: cgImg, scale: img.scale, orientation: img.imageOrientation)
                }
                currentGallery.editedImages[asset.localIdentifier] = img
            }
            // patch399: 편집 화면의 이미지가 갤러리 자리로 돌아가는 애니메이션이 끝난 뒤에 전송합니다.
            currentGallery.refreshThumbnails(for: assets)
            currentGallery.updateSelectedCellNumbers()
            editorVC?.dismiss(animated: true) { [weak currentGallery] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    currentGallery?.sendSelectionFromEditor()
                }
            }
        }

        editorVC.onConfirm = { [weak self, weak galleryNav, weak currentGallery] (editedAsset: PHAsset?, croppedImage: UIImage?, filterState: FilterState, caption: String) in
            guard let self = self else { return }
            // 단일 편집 → 전송: 결과 전달 책임이 processEditorResult 로 넘어가므로, 갤러리를 닫기 "전에"
            // 가드를 세웁니다. 안 그러면 갤러리 viewDidDisappear 의 "스와이프로 닫힘" 안전장치가
            // 먼저 onImagesSelected([]) → reject("CANCELLED") 를 보내서, 편집된 사진이 JS 로 오지
            // 않았습니다 (autoCloseOnSelect + enableEditor 조합에서 사진이 안 들어오던 버그).
            currentGallery?.hasReturnedImages = true
            let navToDismiss = galleryNav ?? currentGallery
            let presenter = navToDismiss?.presentingViewController ?? navToDismiss
            presenter?.dismiss(animated: true) {
                self.processEditorResult(asset: editedAsset, croppedImage: croppedImage, filterState: filterState, caption: caption, galleryVC: currentGallery, resolve: resolve, reject: reject)
            }
        }

        editorVC.onCancel = { [weak editorVC] in
            // 에디터만 닫고 갤러리의 선택 상태는 유지합니다.
            editorVC?.dismiss(animated: true, completion: nil)
        }

        var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
        if #available(iOS 15.0, *) {
            savedDetent = galleryNav?.sheetPresentationController?.selectedDetentIdentifier
        }

        let presenterVC = currentGallery.presentedViewController ?? currentGallery
        presenterVC.present(editorVC, animated: true) {
            if #available(iOS 15.0, *) {
                if let saved = savedDetent {
                    galleryNav?.sheetPresentationController?.selectedDetentIdentifier = saved
                }
            }
        }
    }
}

extension RNAttachmentKit: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        zoomAnimator.isPresenting = true
        return zoomAnimator
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        zoomAnimator.isPresenting = false
        return zoomAnimator
    }
}

// MARK: - 전송 처리 상태 (앱에서 동영상 취소)

/// openGallery 결과 처리 한 번. cancelVideoProcessing(index) → 그 동영상만(또는 전부) 취소
private final class MediaProcessingJob {
    private let lock = NSLock()
    private var cancelAll = false
    private var cancelled = Set<Int>()
    private var currentIndex: Int?
    private var currentExporter: VideoExporter?

    func cancel(index: Int?) {
        lock.lock(); defer { lock.unlock() }
        if let i = index {
            cancelled.insert(i)
            if currentIndex == i { currentExporter?.cancel() }
        } else {
            cancelAll = true
            currentExporter?.cancel()
        }
    }

    func isCancelled(_ i: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelAll || cancelled.contains(i)
    }

    func begin(index: Int, exporter: VideoExporter) {
        lock.lock(); defer { lock.unlock() }
        currentIndex = index
        currentExporter = exporter
    }

    func end() {
        lock.lock(); defer { lock.unlock() }
        currentIndex = nil
        currentExporter = nil
    }
}

/// onVideoProgress 를 1% 이상 바뀌고 0.1초 지났을 때만 (브릿지가 넘치지 않게). 0 과 1 은 항상
private final class ProgressThrottle {
    private let lock = NSLock()
    private var last: Double = -1
    private var lastTime: CFTimeInterval = 0

    func shouldSend(_ p: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = CACurrentMediaTime()
        guard p >= 1 || last < 0 || (p - last >= 0.01 && now - lastTime >= 0.1) else { return false }
        if p >= 1 && last >= 1 { return false }
        last = p
        lastTime = now
        return true
    }
}

/// 스레드 사이에서 읽고 쓰는 Bool
private final class AtomicFlag {
    private let lock = NSLock()
    private var v = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}
