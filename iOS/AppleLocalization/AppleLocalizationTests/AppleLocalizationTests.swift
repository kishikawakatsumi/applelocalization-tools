import XCTest
@testable import AppleLocalization
import TSCBasic
import AppleArchive
import System
import os

class AppleLocalizationTests: XCTestCase {
  func test() async throws {
    let logger = Logger(subsystem: "com.kishikawakatsumi.AppleLocalizationTool", category: "main")

    var counter = 1

    let fileManager = FileManager()

    let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let filename = "\(Date().timeIntervalSince1970)".replacingOccurrences(of: ".", with: "")
    let outputDirectory = documentDirectory.appendingPathComponent(filename)
    try fileManager.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    logger.log("\(outputDirectory)")

    var localizables = OrderedSet<Localizable>()
    try collectLocalizables(root: AbsolutePath(validating: "/System/Library")).forEach {
      localizables.append($0)
    }
    try collectLocalizables(root: AbsolutePath(validating: "/Developer")).forEach {
      localizables.append($0)
    }

    for localizable in localizables {
      guard let bundle = Bundle(path: localizable.bundlePath) else { fatalError() }

      if let loctablePath = localizable.loctablePath {
        let fileUrl = URL(fileURLWithPath: loctablePath)

        if let dictionary = NSMutableDictionary(contentsOf: fileUrl) {
          dictionary.removeObject(forKey: "LocProvenance")

          if let plist = dictionary as? [String: [String: Any]] {
            for (localization, value) in plist {
              for (key, target) in value {
                let localized: String
                if let target = target as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: target) {
                  localized = String(decoding: data, as: UTF8.self)
                } else {
                  localized = "\(target)"
                }
                if var localizations = localizable.localizations[key] {
                  localizations.append(Localization(language: localization, target: localized, filename: fileUrl.lastPathComponent))
                  localizable.localizations[key] = localizations
                } else {
                  var localizations = [Localization]()
                  localizations.append(Localization(language: localization, target: localized, filename: fileUrl.lastPathComponent))
                  localizable.localizations[key] = localizations
                }
              }
            }
          }
        }
      }

      for localization in bundle.localizations {
        guard let localizationDirectory = bundle.path(forResource: localization, ofType: "lproj") else {
          continue
        }
        guard let localizedFiles = try? localFileSystem.getDirectoryContents(try AbsolutePath(validating: localizationDirectory)) else {
          continue
        }

        for localizedFile in localizedFiles {
          guard localizedFile.hasSuffix("strings") else {
            continue
          }
          let fileUrl = bundle.url(
            forResource: localizedFile,
            withExtension: nil,
            subdirectory: nil,
            localization: localization
          )
          guard let fileUrl = fileUrl, let data = try? Data(contentsOf: fileUrl) else {
            continue
          }

          let decoder = PropertyListDecoder()
          guard let plist = try? decoder.decode(Dictionary<String, String>.self, from: data) else {
            continue
          }

          for (key, value) in plist {
            if var localizations = localizable.localizations[key] {
              localizations.append(Localization(language: localization, target: value, filename: fileUrl.lastPathComponent))
              localizable.localizations[key] = localizations
            } else {
              var localizations = [Localization]()
              localizations.append(Localization(language: localization, target: value, filename: fileUrl.lastPathComponent))
              localizable.localizations[key] = localizations
            }
          }
        }
      }

      guard !localizable.localizations.isEmpty else {
        continue
      }

      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      let data = try encoder.encode(localizable)
      let outFile: URL
      if let loctablePath = localizable.loctablePath {
        outFile = outputDirectory.appendingPathComponent("\(localizable.framework)_\(try AbsolutePath(validating: loctablePath).basename)_\(counter)")
      } else {
        outFile = outputDirectory.appendingPathComponent("\(localizable.framework)_\(counter)")
      }
      logger.log("\(outFile)")
      counter += 1
      try data.write(to: outFile.appendingPathExtension("json"))
    }

    let archiveDestination = documentDirectory.appendingPathComponent("\(filename).aar")
    let archiveFilePath = FilePath(archiveDestination.path)

    guard let writeFileStream = ArchiveByteStream.fileStream(
      path: archiveFilePath,
      mode: .writeOnly,
      options: [.create, .truncate],
      permissions: [.ownerReadWrite, .groupRead, .otherRead]) else {
      return
    }
    defer {
    }

    guard let compressStream = ArchiveByteStream.compressionStream(
      using: .lzfse,
      writingTo: writeFileStream) else {
      return
    }

    guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
      return
    }

    guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM") else {
      return
    }

    let sourcePath = outputDirectory.path
    let source = FilePath(sourcePath)

    do {
      try encodeStream.writeDirectoryContents(
        archiveFrom: source,
        keySet: keySet)
    } catch {
      fatalError("Write directory contents failed.")
    }

    try encodeStream.close()
    try compressStream.close()
    try writeFileStream.close()

    let url = URL(string: "https://content.dropboxapi.com/2/files/upload")!
    let headers = [
      "Authorization": "Bearer <ACCESS_TOKEN>",
      "Dropbox-API-Arg": "{\"autorename\":false,\"mode\":\"add\",\"mute\":false,\"path\":\"/\(filename).aar\",\"strict_conflict\":false}",
      "Content-Type": "application/octet-stream"
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    request.httpBody = try Data(contentsOf: archiveDestination)

    let (data, response) = try await URLSession.shared.data(for: request)
    let result = String(decoding: data, as: UTF8.self)
    logger.log("\(result)")
    guard let response = response as? HTTPURLResponse, response.statusCode >= 200 && response.statusCode < 300 else {
      throw result
    }

    logger.log("finished!")
  }
}

func collectLocalizables(root: AbsolutePath) throws -> OrderedSet<Localizable> {
  var bundles = OrderedSet<AbsolutePath>()
  var localizables = OrderedSet<Localizable>()

  let iterator = try walk(root)
  for file in iterator {
    if file.extension == "strings" || file.extension == "loctable" {
      let bundlePath: AbsolutePath
      if let ext = file.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory
      } else if let ext = file.parentDirectory.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory.parentDirectory
      } else if let ext = file.parentDirectory.parentDirectory.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory.parentDirectory.parentDirectory
      } else if let ext = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory
      } else if let ext = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory
      } else if let ext = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory.extension, ext != "lproj", ext != "pass", ext.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) == nil {
        bundlePath = file.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory.parentDirectory
      } else if file.parentDirectory.extension == "lproj" {
        if let _ = Bundle(url: file.parentDirectory.parentDirectory.asURL) {
          bundlePath = file.parentDirectory.parentDirectory
        } else if let _ = Bundle(url: file.parentDirectory.parentDirectory.parentDirectory.asURL) {
          bundlePath = file.parentDirectory.parentDirectory.parentDirectory
        } else {
          print(file)
          fatalError()
        }
      } else {
        print(file)
        fatalError()
      }

      guard let _ = Bundle(url: bundlePath.asURL) else {
        fatalError()
      }

      if file.extension == "loctable" {
        let localizable = Localizable(
          framework: bundlePath.basename,
          bundlePath: bundlePath.pathString,
          loctablePath: file.pathString
        )
        localizables.append(localizable)
      } else if bundles.append(bundlePath) {
        let localizable = Localizable(
          framework: bundlePath.basename,
          bundlePath: bundlePath.pathString,
          loctablePath: nil
        )
        localizables.append(localizable)
      }
    }
  }

  return localizables
}

class Localizable: Codable, Hashable {
  let framework: String
  let bundlePath: String
  let loctablePath: String?
  var localizations = [String: [Localization]]()

  init(framework: String, bundlePath: String, loctablePath: String?) {
    self.framework = framework
    self.bundlePath = bundlePath
    self.loctablePath = loctablePath
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundlePath)
  }

  static func == (lhs: Localizable, rhs: Localizable) -> Bool {
    lhs.bundlePath == rhs.bundlePath
  }
}

struct Localization: Codable {
  let language: String
  let target: String
  let filename: String
}

extension String: Error {}
