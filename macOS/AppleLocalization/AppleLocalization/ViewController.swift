import Cocoa
import TSCBasic

class ViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        try! AppleLocalization().run()
    }
}

class AppleLocalization {
  func run() throws {
    var counter = 1

    let fileManager = FileManager()

    let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let outputDirectory = documentDirectory.appendingPathComponent("\(Date().timeIntervalSince1970)")
    try fileManager.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    print(outputDirectory)

    var localizables = OrderedSet<Localizable>()
    try collectLocalizables(root: AbsolutePath(validating: "/Applications")).forEach {
      localizables.append($0)
    }
    try collectLocalizables(root: AbsolutePath(validating: "/Library")).forEach {
      localizables.append($0)
    }
    try collectLocalizables(root: AbsolutePath(validating: "/System")).forEach {
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
                if var localizations = localizable.localizations[key] {
                  localizations.append(Localization(language: localization, target: "\(target)", filename: fileUrl.lastPathComponent))
                  localizable.localizations[key] = localizations
                } else {
                  var localizations = [Localization]()
                  localizations.append(Localization(language: localization, target: "\(target)", filename: fileUrl.lastPathComponent))
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
      print(outFile)
      counter += 1
      try data.write(to: outFile.appendingPathExtension("json"))
    }

    print("finished!")
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
      } else if file.pathString == "/System/Library/LASecureIO/Strings/ApplePayWarsaw.loctable" {
        bundlePath = file.parentDirectory.parentDirectory
      } else if file.pathString == "/System/Library/Displays/Contents/Resources/Localizable.loctable" {
        bundlePath = file.parentDirectory.parentDirectory.parentDirectory
      } else {
        print(file)
        fatalError()
      }

      guard let _ = Bundle(url: bundlePath.asURL) else {
        print(bundlePath)
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
