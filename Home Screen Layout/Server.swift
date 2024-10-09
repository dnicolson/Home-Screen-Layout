import SwiftUI
import Swifter

let APP_ORDER_PLIST = URL(fileURLWithPath: "/private/var/mobile/Library/com.apple.HeadBoard/AppOrder.plist")

class Server: ObservableObject {
    private var server: HttpServer?
    @Published var hostname = ""
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    init() {
        if isAppOrderPlistReadable() {
            hostname = getIPAddress()
            startServer()
        }
    }
    
    private func isAppOrderPlistReadable() -> Bool {
        let fileManager = FileManager.default
        if !fileManager.isReadableFile(atPath: APP_ORDER_PLIST.path) {
            self.alertTitle = "Error"
            self.alertMessage = "The AppOrder.plist file is not readable.\n\n A rootful jailbreak is required."
            self.showAlert = true
            
            return false
        }
        
        return true
    }
    
    private func startServer() {
        server = HttpServer()
        
        if let appBundlePath = Bundle.main.resourcePath {
            server?["/"] = shareFile(appBundlePath + "/Web/index.html")
            server?["/app/:path"] = shareFilesFromDirectory(appBundlePath + "/Web")
        }
        
        #if !targetEnvironment(simulator)
        server?["/app-info/:bundleID"] = { request in
            let bundleID = request.params[":bundleID"]!
            
            guard let appImage = ApplicationsHelper.shared.getAppImage(from: bundleID),
                  let appName = ApplicationsHelper.shared.getAppName(from: bundleID) else {
                return .notFound
            }
            
            let base64Image = appImage.base64EncodedString()
            let responseObject: [String: Any] = [
                "name": appName,
                "image": "data:image/png;base64,\(base64Image)"
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: responseObject, options: [])
                return .ok(.data(jsonData, contentType: "application/json"))
            } catch {
                return .internalServerError
            }
        }
        
        server?["/app-icon/:bundleID"] = { request in
            let appImage = ApplicationsHelper.shared.getAppImage(from: request.params[":bundleID"]!)

            if let image = appImage {
                return .ok(.data(image, contentType: "image/png"))
            } else {
                return .notFound
            }
        }
        
        server?["/app-name/:bundleID"] = { request in
            print(getIPAddress())
            let appName = ApplicationsHelper.shared.getAppName(from: request.params[":bundleID"]!)
            
            if let name = appName {
                return .ok(.data(name.data(using: .utf8)!, contentType: "text/plain"))
            } else {
                return .notFound
            }
        }
        #endif
        
        server?["/app-order"] = { request in
            do {
                let appOrderPlist = try Data(contentsOf: APP_ORDER_PLIST)
                let appOrderPlistXml = (Plist.binaryToXml(binaryData: appOrderPlist)?.data(using: .utf8)!)!
                return .ok(.data(appOrderPlistXml, contentType: "application/x-plist"))
            } catch {
                print("Error reading plist file: \(error)")
                return .internalServerError
            }
        }
        
        server?.POST["/app-order"] = { request in
            guard !request.body.isEmpty else {
                return HttpResponse.badRequest(.htmlBody("No body found"))
            }

            let appOrderPlist = Data(request.body)
            let appOrderPlistBinary = Plist.xmlToBinary(xmlString: String(data: appOrderPlist, encoding: .utf8)!)!
            
            do {
                try appOrderPlistBinary.write(to: APP_ORDER_PLIST)
                
                let semaphore = DispatchSemaphore(value: 0)
                var responseMessage = "App order saved successfully."

                Task {
                    let restartMessage: String
                    if await restartPineBoard() {
                        print("Opening Palera1n…")
                        restartMessage = "PineBoard successfully restarted."
                    } else {
                        print("Failed to restart PineBoard")
                        restartMessage = "PineBoard was not able to be automatically restarted.\n\nThis command should be run as soon as possible manually:\n/cores/binpack/bin/launchctl kickstart -k system/com.apple.backboardd"
                        DispatchQueue.main.async {
                            self.alertTitle = "Save Successful"
                            self.alertMessage = restartMessage
                            self.showAlert = true
                        }
                    }
                    responseMessage = responseMessage + "\n\n\(restartMessage)"
                    
                    semaphore.signal()
                }

                semaphore.wait()
                
                return HttpResponse.ok(.text(responseMessage))
            } catch {
                print("Failed to save file: \(error)")
                return HttpResponse.internalServerError
            }
        }
        
        do {
            try server?.start(8080)
            print("Server started on port 8080")
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    func stopServer() {
        server?.stop()
    }
}

func restartPineBoard() async -> Bool {
    return await withCheckedContinuation { continuation in
        Task {
            await MainActor.run {
                UIApplication.shared.open(URL(string: "loader://restart-pineboard")!, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

func getIPAddress() -> String {
    var address = "error"
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            if let interface = ptr?.pointee {
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        let addr = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            inet_ntoa($0.pointee.sin_addr)
                        }
                        if let addr = addr {
                            address = String(cString: addr)
                        }
                    }
                }
            }
            ptr = ptr?.pointee.ifa_next
        }
    }
    
    freeifaddrs(ifaddr)
    return address
}
