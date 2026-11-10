import Foundation
import AppKit

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = Bundle(url: bundleURL), let catalogueURL = bundle.url(forResource: "catalogue", withExtension: "json", subdirectory: "Showcase") else { fatalError("Missing bundled catalogue") }
let object = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogueURL)) as! [String: Any]
let entries = object["entries"] as! [[String: Any]]
precondition(entries.count == 13)
precondition(entries.filter { $0["mergedInto"] == nil }.count == 12)
let ids = Set(entries.map { $0["id"] as! String })
precondition(ids.count == 13)
for entry in entries {
    if let canonical = entry["mergedInto"] as? String { precondition(ids.contains(canonical)) }
    let path = entry["artwork"] as! String
    guard let url = bundle.url(forResource: (path as NSString).deletingPathExtension, withExtension: (path as NSString).pathExtension, subdirectory: "Showcase"), let image = NSImage(contentsOf: url), image.size.width > 0 else { fatalError("Missing cover: " + path) }
}
print("Bundled showcase verified: 13 unique originals, 12 active, valid merge link, 13 decodable covers.")
