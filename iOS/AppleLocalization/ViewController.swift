import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let fm = FileManager()

        let documentDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDirectory = documentDirectory.appendingPathComponent("\(Date().timeIntervalSince1970)")
        try! fm.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let rootPaths = ["/System/Library/Frameworks", "/System/Library/PrivateFrameworks"]
        for rootPath in rootPaths {
            guard let frameworks = try? fm.contentsOfDirectory(atPath: rootPath) else {
                return
            }
            for framework in frameworks {
                guard let bundle = Bundle(path: "\(rootPath)/\(framework)") else {
                    continue
                }
                guard !bundle.localizations.isEmpty else {
                    continue
                }
                print("\(framework)")

                let localizable = Localizable(framework: framework, bundlePath: bundle.bundlePath)

                for localization in bundle.localizations {
                    guard let localizedFiles = try? fm.contentsOfDirectory(atPath: "\(bundle.bundlePath)/\(localization).lproj") else {
                        continue
                    }
                    print("\(localization)")

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
                            if var lns = localizable.localizations[key] {
                                lns.append(Localization(language: localization, target: value, filename: fileUrl.lastPathComponent))
                                localizable.localizations[key] = lns
                            } else {
                                var lns = [Localization]()
                                lns.append(Localization(language: localization, target: value, filename: fileUrl.lastPathComponent))
                                localizable.localizations[key] = lns
                            }
                        }
                    }
                }

                guard !localizable.localizations.isEmpty else {
                    continue
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try! encoder.encode(localizable)
                try! data.write(to: outputDirectory.appendingPathComponent(localizable.framework).appendingPathExtension("json"))
            }
        }

        print("finished")
    }
}

class Localizable: Codable {
    let framework: String
    let bundlePath: String
    var localizations = [String: [Localization]]()

    init(framework: String, bundlePath: String) {
        self.framework = framework
        self.bundlePath = bundlePath
    }
}

struct Localization: Codable {
    let language: String
    let target: String
    let filename: String
}
