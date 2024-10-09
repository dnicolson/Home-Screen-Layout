import Foundation

struct Plist {
    static func binaryToXml(binaryData: Data) -> String? {
        guard let plistDict = try? PropertyListSerialization.propertyList(from: binaryData, options: [], format: nil) else {
            return nil
        }
        
        let xmlData = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        
        return xmlData.flatMap { String(data: $0, encoding: .utf8) }
    }
    
    static func xmlToBinary(xmlString: String) -> Data? {
        guard let xmlData = xmlString.data(using: .utf8) else {
            return nil
        }
        
        guard let plistDict = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) else {
            return nil
        }
        
        return try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .binary, options: 0)
    }
}
