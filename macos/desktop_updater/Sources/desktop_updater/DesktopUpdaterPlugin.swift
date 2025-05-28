import Cocoa
import FlutterMacOS

public class DesktopUpdaterPlugin: NSObject, FlutterPlugin {
    func getCurrentVersion() -> String {
        let infoDictionary = Bundle.main.infoDictionary!
        let version = infoDictionary["CFBundleVersion"] as! String
        return version
    }
    
    func restartApp() {
        let debug = true
        let fileManager = FileManager.default
        let updateDir = fileManager.currentDirectoryPath + "/update"
        let destDir = fileManager.currentDirectoryPath
        let executablePath = Bundle.main.executablePath ?? ""
        let appPath = executablePath.components(separatedBy: "/Contents/").first ?? ""

        let script = """
        #!/bin/bash
        exec > /tmp/desktop_updater_log.txt 2>&1
        echo "Update script started"
        echo "Copying files from: \(updateDir)"
        cp -R "\(updateDir)/"* "\(destDir)/"
        echo "Removing update directory"
        rm -rf "\(updateDir)"
        echo "Relaunching app: \(appPath)"
        open "\(appPath)"
        echo "Cleaning up script"
        rm -- "$0"
        """

        let scriptPath = fileManager.temporaryDirectory.appendingPathComponent("desktop_update.sh").path

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            print("Failed to create update script: \(error)")
            return
        }

        let process = Process()

        if debug {
            // Launch script with visible Terminal for debugging
            process.launchPath = "/usr/bin/open"
            process.arguments = ["-a", "Terminal", scriptPath]
        } else {
            // Silent background execution
            process.launchPath = "/bin/bash"
            process.arguments = [scriptPath]
        }

        do {
            try process.run()
        } catch {
            print("Failed to run update script: \(error)")
        }

        // Terminate the app
        exit(0)
    }


    
    func copyAndReplaceFiles(from sourcePath: String, to destinationPath: String) throws {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: sourcePath)
        
        while let element = enumerator?.nextObject() as? String {
            let sourceItemPath = (sourcePath as NSString).appendingPathComponent(element)
            let destinationItemPath = (destinationPath as NSString).appendingPathComponent(element)
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: sourceItemPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Ensure the directory exists at destination
                    if !fileManager.fileExists(atPath: destinationItemPath) {
                        try fileManager.createDirectory(atPath: destinationItemPath, withIntermediateDirectories: true, attributes: nil)
                    }
                } else {
                    // Handle file or symbolic link
                    let attributes = try fileManager.attributesOfItem(atPath: sourceItemPath)
                    if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                        // Handle symbolic link
                        if fileManager.fileExists(atPath: destinationItemPath) {
                            try fileManager.removeItem(atPath: destinationItemPath)
                        }
                        let target = try fileManager.destinationOfSymbolicLink(atPath: sourceItemPath)
                        try fileManager.createSymbolicLink(atPath: destinationItemPath, withDestinationPath: target)
                    } else {
                        // Handle regular file
                        if fileManager.fileExists(atPath: destinationItemPath) {
                            // Replace existing file
                            try fileManager.replaceItem(at: URL(fileURLWithPath: destinationItemPath), withItemAt: URL(fileURLWithPath: sourceItemPath), backupItemName: nil, options: [], resultingItemURL: nil)
                        } else {
                            // Copy new file
                            try fileManager.copyItem(atPath: sourceItemPath, toPath: destinationItemPath)
                        }
                    }
                }
            }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "desktop_updater", binaryMessenger: registrar.messenger)
        let instance = DesktopUpdaterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "restartApp":
            restartApp()
            result(nil)
        case "getExecutablePath":
            result(Bundle.main.executablePath)
        case "getCurrentVersion":
            result(getCurrentVersion())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
