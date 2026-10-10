import type { TurboModule } from "react-native"
import { TurboModuleRegistry } from "react-native"

export interface Spec extends TurboModule {
  init(licenseKey: string): Promise<boolean>;
  openGallery(options: Object): Promise<Object[]>;
  openEditor(options: Object): Promise<Object>;
  openViewer(options: Object): Promise<void>;
  closeGallery(): Promise<boolean>;
  
  // RCTEventEmitter 필수 규격 (Turbo Module에서 이벤트 방출 시 필수)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
  
  updateSourceRect(options: Object): Promise<void>;
  
  getDefaultAnimationConfig(): Promise<Object>;

  // 지도 뷰어 (위치 메시지)
  openMapViewer(options: Object): Promise<void>;
  updateMapViewerSourceRect(rect: Object): Promise<void>;
  // 위치 메시지 지도 썸네일 (이 기기에서 그려 캐시)
  renderLocationThumbnail(options: Object): Promise<Object>;
  clearLocationThumbnailCache(): Promise<void>;
  // 좌표 → 주소 (기기 지오코더, 디스크 캐시)
  reverseGeocode(options: Object): Promise<Object>;
  clearReverseGeocodeCache(): Promise<void>;

  // 미디어 갤러리 (사진 모아보기)
  openMediaGallery(options: Object): Promise<Object>;
  closeMediaGallery(galleryId: string): Promise<void>;
  appendGalleryItems(payload: Object): Promise<void>;
  removeGalleryItems(payload: Object): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNAttachmentKit");
