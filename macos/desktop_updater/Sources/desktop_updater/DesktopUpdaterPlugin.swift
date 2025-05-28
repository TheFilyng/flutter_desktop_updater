import Cocoa
import FlutterMacOS
import Foundation

public class DesktopUpdaterPlugin: NSObject, FlutterPlugin {
    func getCurrentVersion() -> String {
        let infoDictionary = Bundle.main.infoDictionary!
        let version = infoDictionary["CFBundleVersion"] as! String
        return version
    }
    
    func restartApp() {
        let fileManager = FileManager.default

        // Get the .app bundle path
        guard let bundlePath = Bundle.main.bundlePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let decodedBundlePath = bundlePath.removingPercentEncoding else {
            print("Unable to determine bundle path.")
            return
        }

        // Define all paths
        let appPath = decodedBundlePath                        // e.g., /Applications/MyApp.app
        let updateDir = "\(appPath)/Contents/Resources/update" // Where updated files are placed
        let destDir = "\(appPath)/Contents/MacOS"              // Where main app executable lives
        let tempDir = NSTemporaryDirectory()
        let scriptPath = "\(tempDir)/desktop_update.sh"
        let logPath = "/tmp/desktop_updater_log.txt"
        let appName = (appPath as NSString).lastPathComponent

        // Create shell script
        let script = """
        #!/bin/bash

        LOG_FILE="\(logPath)"
        exec > "$LOG_FILE" 2>&1

        echo "---- $(date) ----"
        echo "Starting update script..."

        UPDATE_DIR="\(updateDir)"
        DEST_DIR="\(destDir)"
        APP_PATH="\(appPath)"
        APP_NAME="\(appName)"

        echo "Update dir: $UPDATE_DIR"
        echo "Dest dir: $DEST_DIR"
        echo "App name: $APP_NAME"

        echo "Waiting for app to fully exit..."
        while pgrep -x "$APP_NAME" > /dev/null; do
        echo "App still running..."
        sleep 0.5
        done

        if [ -d "$UPDATE_DIR" ]; then
        echo "Copying update files..."
        cp -Rv "$UPDATE_DIR/"* "$DEST_DIR/"
        COPY_EXIT=$?
        echo "cp exit code: $COPY_EXIT"

        echo "Removing update directory..."
        rm -rf "$UPDATE_DIR"
        RM_EXIT=$?
        echo "rm exit code: $RM_EXIT"
        else
        echo "Update directory not found: $UPDATE_DIR"
        fi

        echo "Relaunching app..."
        open "$APP_PATH"

        echo "Cleaning up update script..."
        rm -- "$0"

        echo "Update script finished."
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = [scriptPath]
            try task.run()

            exit(0) // Terminate app so update can happen
        } catch {
            print("Error writing or executing update script: \(error)")
        }
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
