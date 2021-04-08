//
//  PHAsset+Extension.swift
//  multi_image_picker
//
//  Created by johnson_zhong on 2020/5/17.
//

import Foundation
import Photos
import AssetsLibrary

extension PHAsset {
    var fileSize: Double {
        get {
            if #available(iOS 9, *) {
                let resource = PHAssetResource.assetResources(for: self)
                let imageSizeByte = resource.first?.value(forKey: "fileSize") as? Double ?? 0
                return imageSizeByte
            } else {
                // Fallback on earlier versions
                return 5.0
            }
        }
    }
    
    var originalFilename: String? {
        var fname:String?
        if #available(iOS 9.0, *) {
            let resources = PHAssetResource.assetResources(for: self)
            if let resource = resources.first {
                fname = resource.originalFilename
            }
        }
        if fname == nil {
            fname = self.value(forKey: "filename") as? String
        }
        
        return fname
    }
    
    func compressAsset(_ thumb : Bool, saveDir : String, process: ((NSDictionary) -> Void)?, failed: ((NSError) -> Void)?, finish: ((NSDictionary) -> Void)?) {
        let manager = PHImageManager.default()
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = PHImageRequestOptionsDeliveryMode.highQualityFormat
        thumbOptions.resizeMode = PHImageRequestOptionsResizeMode.exact
        thumbOptions.isSynchronous = false
        thumbOptions.isNetworkAccessAllowed = true
        thumbOptions.version = .current
        
        var uuid = "\(self.localIdentifier)-\(self.modificationDate?.timeIntervalSince1970 ?? 0)"
        uuid = uuid.replacingOccurrences(of: "/", with: "")
        let tmpSuffix = UUID().uuidString;
        
        if self.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            manager.requestAVAsset(forVideo: self, options: options) { (avAsset, audioMix, info) in
                guard let avAsset = avAsset else {
                    failed?(NSError(domain: "视频请求失败", code: 2, userInfo: [
                        "identifier": self.localIdentifier,
                        "errorCode": "2"
                    ]))
                    return
                }
                let dictionary : NSMutableDictionary = NSMutableDictionary()
                let thumbName = "\(uuid).jpg"
                let videoName = "\(uuid).mp4"
                let thumbPath = saveDir + thumbName
                let thumbTmpPath = saveDir + thumbName + "." + tmpSuffix
                let videoPath = saveDir + videoName
                let videoTmpPath = saveDir + videoName + "." + tmpSuffix
                let duration = CMTimeGetSeconds(avAsset.duration)
                if FileManager.default.fileExists(atPath: thumbPath), let thumbImg = UIImage(contentsOfFile: thumbPath) {
                    dictionary.setValue(thumbPath, forKey: "thumbPath")
                    dictionary.setValue(thumbName, forKey: "thumbName")
                    dictionary.setValue(thumbImg.size.height * thumbImg.scale, forKey: "thumbHeight")
                    dictionary.setValue(thumbImg.size.width * thumbImg.scale, forKey: "thumbWidth")
                }else {
                    let gen = AVAssetImageGenerator(asset: avAsset)
                    gen.appliesPreferredTrackTransform = true
                    let time = CMTimeMake(value: 0, timescale: 60);
                    var actualTime  = CMTimeMake(value: 0, timescale: 60)
                    if let image = try? gen.copyCGImage(at: time, actualTime: &actualTime) {
                        let thumbImg = UIImage(cgImage: image)
                        do {
                            try thumbImg.jpegData(compressionQuality: 0.6)?.write(to: URL(fileURLWithPath: thumbTmpPath))
                        } catch let error as NSError {
                            failed?(NSError(domain: error.domain, code: error.code, userInfo: [
                                "identifier": self.localIdentifier,
                                "errorCode": "1",
                            ]))
                            return
                        }
                        do {
                            try FileManager.default.moveItem(atPath: thumbTmpPath, toPath: thumbPath)
                        } catch let err as NSError {
                            print(err)
                        }
                        dictionary.setValue(thumbPath, forKey: "thumbPath")
                        dictionary.setValue(thumbName, forKey: "thumbName")
                        dictionary.setValue(thumbImg.size.height * thumbImg.scale, forKey: "thumbHeight")
                        dictionary.setValue(thumbImg.size.width * thumbImg.scale, forKey: "thumbWidth")
                    }else {
                        failed?(NSError(domain: "缩略图图片拷贝失败", code: 1, userInfo: [
                            "identifier": self.localIdentifier,
                            "errorCode": "1",
                        ]))
                        return
                    }
                }

                var thumbVideoSize = CGSize.zero
                if FileManager.default.fileExists(atPath: videoPath) {
                    let thumbVideo = AVURLAsset(url: URL(fileURLWithPath: videoPath))
                    for track in thumbVideo.tracks {
                        if track.mediaType == AVMediaType.video {
                            thumbVideoSize = track.naturalSize
                        }
                    }
                }
                
                if thumbVideoSize != CGSize.zero {
                    dictionary.setValue(self.localIdentifier, forKey: "identifier")
                    dictionary.setValue(videoPath, forKey: "filePath")
                    dictionary.setValue(thumbVideoSize.width, forKey: "width")
                    dictionary.setValue(thumbVideoSize.height, forKey: "height")
                    dictionary.setValue(videoName, forKey: "name")
                    dictionary.setValue(duration, forKey: "duration")
                    dictionary.setValue("video", forKey: "fileType")
                    finish?(dictionary)
                }else {
                    _ = LightCompressor().compressVideo(
                        source: avAsset,
                        destination: URL(fileURLWithPath: videoTmpPath),
                        quality: .low,
                        keepOriginalResolution: false,
                        completion: {[weak self] result in
                            guard let `self` = self else { return }
                            switch (result) {
                            case .onCancelled:
                                failed?(NSError(domain: "视频压缩已被取消", code: 2, userInfo: [
                                    "identifier": self.localIdentifier,
                                    "errorCode": "2"
                                ]))
                                print("compress canceled")
                            case .onFailure(let error):
                                failed?(NSError(domain: error.localizedDescription, code: 2, userInfo: [
                                    "identifier": self.localIdentifier,
                                    "errorCode": "2"
                                ]))
                                print("compress failure \(error)")
                            case .onStart:
                                print("start compress")
                            case .onSuccess(let path, let size):
                                if FileManager.default.fileExists(atPath: path.path) {
                                    do {
                                        try FileManager.default.moveItem(atPath: path.path, toPath: videoPath)
                                    } catch let error as NSError{
                                        print(error)
                                    }
                                    dictionary.setValue(self.localIdentifier, forKey: "identifier")
                                    dictionary.setValue(videoPath, forKey: "filePath")
                                    dictionary.setValue(size.width, forKey: "width")
                                    dictionary.setValue(size.height, forKey: "height")
                                    dictionary.setValue(videoName, forKey: "name")
                                    dictionary.setValue(duration, forKey: "duration")
                                    dictionary.setValue("video", forKey: "fileType")
                                    finish?(dictionary)
                                    print("compress success")
                                }else {
                                    failed?(NSError(domain: "视频请求失败", code: 2, userInfo: [
                                        "identifier": self.localIdentifier,
                                        "errorCode": "2"
                                    ]))
                                    print("compress finish but not found file")
                                }
                            }
                       }
                    )
                }
            }
        }else {
            let targetHeight : CGFloat = CGFloat(self.pixelHeight)
            let targetWidth : CGFloat = CGFloat(self.pixelWidth)
            if let uti = self.value(forKey: "filename") as? String, uti.uppercased().hasSuffix("GIF") {
                let fileName = "\(uuid).gif"
                let filePath = saveDir + fileName
                let checkFileName = "\(uuid)-check.gif"
                let checkPath = saveDir + checkFileName
                let fileTmpPath = saveDir + fileName + "." + tmpSuffix
                if FileManager.default.fileExists(atPath: filePath), FileManager.default.fileExists(atPath: checkPath) {
                    finish?([
                        "identifier": self.localIdentifier,
                        "filePath":filePath,
                        "checkPath":checkPath,
                        "width": targetWidth,
                        "height": targetHeight,
                        "name": fileName,
                        "fileType":"image/gif"
                    ])
                }else {
                    manager.requestImageData(for: self, options: thumbOptions) { (data, uti, ori, info) in
                        do {
                            guard let imageData = data else {
                                failed?(NSError(domain: "图片请求失败", code: 2, userInfo: [
                                    "identifier": self.localIdentifier,
                                    "errorCode": "2"
                                ]))
                                return
                            }
                            let resultData = try ImageCompress.compressImageData(imageData as Data, sampleCount: 1)
                            try resultData.write(to: URL(fileURLWithPath: fileTmpPath))
                            let checkData = try ImageCompress.compressImageData(imageData as Data, sampleCount: 24)
                            try checkData.write(to: URL(fileURLWithPath: checkPath))
                            do {
                                try FileManager.default.moveItem(atPath: fileTmpPath, toPath: filePath)
                            }catch let err as NSError {
                                print(err)
                            }
                            if FileManager.default.fileExists(atPath: filePath) {
                                finish?([
                                    "identifier": self.localIdentifier,
                                    "filePath": filePath,
                                    "checkPath": FileManager.default.fileExists(atPath: checkPath) ? checkPath : filePath,
                                    "width": targetWidth,
                                    "height": targetHeight,
                                    "name": fileName,
                                    "fileType":"image/gif"
                                ])
                            }else {
                                failed?(NSError(domain: "图片保存失败", code: 3, userInfo: [
                                    "identifier": self.localIdentifier,
                                    "errorCode": "3"
                                ]))
                            }
                        }catch _ as NSError {
                            failed?(NSError(domain: "图片请求失败", code: 2, userInfo: [
                                "identifier": self.localIdentifier,
                                "errorCode": "2"
                            ]))
                        }
                    }
                }
            }else {
                let fileName = "\(uuid)-\(thumb ? "thumb" : "origin").jpg"
                let filePath = saveDir + fileName
                let checkPath = saveDir + fileName + ".check"
                let fileTmpPath = saveDir + fileName + "." + tmpSuffix
                if FileManager.default.fileExists(atPath: filePath), FileManager.default.fileExists(atPath: checkPath) {
                    finish?([
                        "identifier": self.localIdentifier,
                        "filePath": filePath,
                        "checkPath": checkPath,
                        "width": targetWidth,
                        "height": targetHeight,
                        "name": fileName,
                        "fileType":"image/jpeg"
                    ])
                }else {
                    manager.requestImageData(for: self, options: thumbOptions) { (data, uti, ori, info) in
                        guard let imageData = data,
                              let compressedData = thumb ? UIImage.lubanCompressImage(UIImage(data: imageData)) : UIImage.lubanOriginImage(UIImage(data: imageData)) else {
                            failed?(NSError(domain: "图片请求失败", code: 2, userInfo: [
                                "identifier": self.localIdentifier,
                                "errorCode": "2"
                            ]))
                            return
                        }
                        do {
                            try compressedData.write(to: URL(fileURLWithPath: fileTmpPath))
                        } catch let err as NSError {
                            print(err)
                        }
                        if FileManager.default.fileExists(atPath: fileTmpPath)  {
                            if targetWidth * targetHeight > 312 * 312,
                               let checkImage = UIImage.compressImage(UIImage(data: compressedData as Data), toTargetWidth: 312, toTargetWidth: 312),
                               let checkImageData = checkImage.jpegData(compressionQuality: 1.0) as NSData? {
                                checkImageData.write(toFile: checkPath, atomically: true)
                            }
                            do {
                                try FileManager.default.moveItem(atPath: fileTmpPath, toPath: filePath)
                            } catch let err as NSError {
                                print(err)
                            }
                            if FileManager.default.fileExists(atPath: filePath) {
                                finish?([
                                    "identifier": self.localIdentifier,
                                    "filePath":filePath,
                                    "width": targetWidth,
                                    "height": targetHeight,
                                    "checkPath": FileManager.default.fileExists(atPath: checkPath) ? checkPath : filePath,
                                    "name": fileName,
                                    "fileType":"image/jpeg"
                                ])
                            }else {
                                failed?(NSError(domain: "图片保存失败", code: 3, userInfo: [
                                    "identifier": self.localIdentifier,
                                    "errorCode": "3"
                                ]))
                            }
                        }else {
                            failed?(NSError(domain: "图片请求失败", code: 2, userInfo: [
                                "identifier": self.localIdentifier,
                                "errorCode": "2"
                            ]))
                        }
                    }
                }
            }
        }
    }
}

//func readMetadata(fromURL url:URL) -> NSDictionary? {
//    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
//        let metadata:NSDictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
//        return metadata
//    }
//    return nil
//}
//
//func isFanbookMarked(_ imageData : NSData, thumb isThumb : Bool) -> Bool {
//   if let source = CGImageSourceCreateWithData(imageData, nil),
//      let metadata:NSDictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil),
//      let exif = metadata.value(forKey: kCGImagePropertyExifDictionary as String) as? NSDictionary,
//      let mark = exif.value(forKey: kCGImagePropertyExifUserComment as String) as? String, mark.contains("-") {
//    let info = mark.split(separator: "-")
//    if info.count == 3 {
//        let version = info[1]
//        let thumb = info[2]
//        if version != "1.0.0" {
//            print("is Fanbook Marked: mark version illegal");
//            return false;
//        }
//        if isThumb, thumb.contains("origin") {
//            print("is Fanbook Marked: origin need thumb fasle");
//            return false;
//        }else {
//            print("is Fanbook Marked: true");
//            return true
//        }
//       }else {
//            print("is Fanbook Marked: false");
//           return false;
//       }
//   }else {
//    print("is Fanbook Marked: mark string illegal");
//    return false;
//   }
//}
//
//func fanbookMarkString(_ appName : String, thumb isThumb : Bool, appVersion version : String) -> String {
//    return "\(appName)-\(version)-\(isThumb ? "thumb" : "origin")"
//}
//
//func markFanbookPic(_ imageData : NSData, thumb isThumb : Bool, toPath destPath : String) -> Bool {
//    // Add metadata to imageData
//    let destUrl = URL(fileURLWithPath: destPath)
//    guard
//        let sourceImage = UIImage(data: imageData as Data)?.cgImage,
//        let source = CGImageSourceCreateWithData(imageData, nil),
//        let uniformTypeIdentifier = CGImageSourceGetType(source),
//        let destination = CGImageDestinationCreateWithURL(destUrl as CFURL, uniformTypeIdentifier, 1, nil),
//        let imageProperties = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
//        let mutableMetadata = CGImageMetadataCreateMutableCopy(imageProperties)
//    else { return false }
//
//    CGImageMetadataSetValueMatchingImageProperty(mutableMetadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment, fanbookMarkString("fanbook", thumb: isThumb, appVersion: "1.0.0") as CFTypeRef)
//
//    let finalMetadata:CGImageMetadata = mutableMetadata
//    CGImageDestinationAddImageAndMetadata(destination, sourceImage, finalMetadata, nil)
//
//    guard CGImageDestinationFinalize(destination) else {return false}
//    return true
//}
