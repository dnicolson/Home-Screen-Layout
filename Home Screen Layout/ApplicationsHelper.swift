#if !targetEnvironment(simulator)
import Foundation
import AssetCatalogWrapper

let APP_PATH_SYSTEM = "/Applications"
let APP_PATH = "/var/containers/Bundle/Application"

class ApplicationsHelper {
    static let shared = ApplicationsHelper()
    
    private let fm: FileManager
    private var bundleIdToName: [String: String]
    private var bundleIdToPath: [String: String]
    
    private init() {
        fm = FileManager.default
        bundleIdToName = [:]
        bundleIdToPath = [:]
        loadApplications()
    }
    
    private func loadApplications() {
        let applicationPaths = [APP_PATH_SYSTEM, APP_PATH]
        
        for path in applicationPaths {
            do {
                let contents = try fm.contentsOfDirectory(atPath: path)
                for item in contents {
                    let fullPath = "\(path)/\(item)"
                    if fm.fileExists(atPath: fullPath, isDirectory: nil) {
                        if item.hasSuffix(".app") {
                            let appPath = fullPath
                            if let (bundleIdentifier, appName) = getBundleIdentifierAndName(from: appPath) {
                                bundleIdToName[bundleIdentifier] = appName
                                bundleIdToPath[bundleIdentifier] = appPath
                            }
                        } else {
                            if let appContents = try? fm.contentsOfDirectory(atPath: fullPath) {
                                for appItem in appContents {
                                    if appItem.hasSuffix(".app") {
                                        let appPath = "\(fullPath)/\(appItem)"
                                        if let (bundleIdentifier, appName) = getBundleIdentifierAndName(from: appPath) {
                                            bundleIdToName[bundleIdentifier] = appName
                                            bundleIdToPath[bundleIdentifier] = appPath
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Error reading contents of directory \(path): \(error)")
            }
        }
    }
    
    private func getBundleIdentifierAndName(from appPath: String) -> (String, String)? {
        let infoPlistPath = "\(appPath)/Info.plist"
        
        if let plistData = fm.contents(atPath: infoPlistPath) {
            do {
                if let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                    let bundleIdentifier = plist["CFBundleIdentifier"] as? String
                    
                    var displayName: String?
                    let stringsFilePath = "\(appPath)/en.lproj/InfoPlist.strings"
                    
                    let stringsURL = URL(fileURLWithPath: stringsFilePath)
                    if let stringsDict = NSDictionary(contentsOf: stringsURL) as? [String: String] {
                        displayName = stringsDict["CFBundleDisplayName"]
                    } else {
                        print("Failed to load strings dictionary from \(stringsFilePath)")
                    }
                    
                    displayName = displayName ??
                        (plist["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ??
                        plist["CFBundleName"] as? String
                    
                    if let bundleIdentifier = bundleIdentifier, let displayName = displayName {
                        return (bundleIdentifier, displayName)
                    }
                }
            } catch {
                print("Error reading Info.plist at \(infoPlistPath): \(error)")
            }
        }

        return nil
    }
    
//    private func getIconName(from appPath: String) -> String? {
//        let infoPlistPath = "\(appPath)/Info.plist"
//
//        guard fm.fileExists(atPath: infoPlistPath), let plistData = fm.contents(atPath: infoPlistPath) else {
//            print("Info.plist not found at path: \(infoPlistPath)")
//            return nil
//        }
//        
//        do {
//            if let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
//               let icons = plist["CFBundleIcons"] as? [String: Any],
//               let iconName = icons["CFBundlePrimaryIcon"] as? String {
//                 return iconName
//            }
//        } catch {
//            print("Error reading Info.plist at \(infoPlistPath): \(error)")
//        }
//        
//        return nil
//    }
    
    func getAppName(from bundleIdentifier: String) -> String? {
        return bundleIdToName[bundleIdentifier]
    }
    
    func getAppImage(from bundleIdentifier: String) -> Data? {
        if let bundlePath = bundleIdToPath[bundleIdentifier] {
            let archive = URL(fileURLWithPath: bundlePath + "/Assets.car")
            do {
                let (_, renditionsRoot) = try AssetCatalogWrapper.shared.renditions(forCarArchive: archive)
                for rendition in renditionsRoot {
                    let renditions = rendition.renditions
                    for rend in renditions {
                        if let cgImage = rend.image {
                            let image = UIImage(cgImage: cgImage)
                            // AssetCatalogWrapper doesn't support layer stacks, the icon name cannot be used
                            // getIconName(from: bundleIdToPath[bundleIdentifier])
                            if rend.namedLookup.name.hasPrefix("ZZZZFlattenedImage") {
                                if image.size.width == 400.0 && image.size.height == 240.0 {
                                    return image.pngData()
                                }
                            }
                        }
                    }
                }
            } catch {
                print("Failed to retrieve renditions: \(error)")
                return nil
            }
        }
        return nil
    }
}
#endif
