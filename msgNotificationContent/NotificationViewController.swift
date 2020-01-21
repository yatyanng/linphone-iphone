//
//  NotificationViewController.swift
//  msgNotificationContent
//
//  Created by Paul Cartier on 10/12/2019.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import linphonesw


var GROUP_ID = "group.org.linphone.phone.msgNotification"
var isReplySent: Bool = false
var needToStop: Bool = false
var coreStopped: Bool = false
var log: LoggingService!

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    enum LinphoneCoreError: Error {
        case timeout
    }

    var lc: Core?
    var config: Config!
    var logDelegate: LinphoneLoggingServiceManager!
    var msgDelegate: LinphoneChatMessageManager!
    var coreDelegate: LinphoneCoreManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
        NSLog("[msgNotificationContent] start msgNotificationContent extension")
        
        let replyAction = UNTextInputNotificationAction(identifier: "Reply",
                         title: NSLocalizedString("Reply", comment: ""),
                         options: [],
                         textInputButtonTitle: NSLocalizedString("Send", comment: ""), // TODO PAUL : non traduit ?
                         textInputPlaceholder: "")
        
        let seenAction = UNNotificationAction(identifier: "Seen", title: NSLocalizedString("Mark as seen", comment: ""), options: [])
        let category = UNNotificationCategory(identifier: "msg_cat", actions: [replyAction, seenAction], intentIdentifiers: [], options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        needToStop = false
        isReplySent = false
    }

    func didReceive(_ notification: UNNotification) {
        self.title = "test test test" // TODO PAUL : a enlever
    }

    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        do {
            let userInfo = response.notification.request.content.userInfo
            switch response.actionIdentifier {
            case "Reply":
                if let replyText = response as? UNTextInputNotificationResponse {
                    try replyAction(userInfo, text: replyText.userText)
                }
                break
            case "Seen":
                try markAsSeenAction(userInfo)
                break
            default:
                break
            }

            if (needToStop) {
                log.error(msg: "[msgNotificationContent] core stopped by app")
                throw LinphoneCoreError.timeout
            } else {
                completion(.dismiss)
                stopCore()
            }

        } catch {
            log.error(msg: "[msgNotificationContent] error: \(error)")
            completion(.dismissAndForwardAction)
        }
    }

    func markAsSeenAction(_ userInfo: [AnyHashable : Any]) throws {
        NSLog("[msgNotificationContent] markAsSeenAction")
        try startCore()

        let peerAddress = userInfo["peer_addr"] as! String
        let localAddress = userInfo["local_addr"] as! String
        let peer = try lc!.createAddress(address: peerAddress)
        let local = try lc!.createAddress(address: localAddress)
        let room = lc!.findChatRoom(peerAddr: peer, localAddr: local)
        if let room = room {
            room.markAsRead()
        }
        lc!.iterate()
    }

    func replyAction(_ userInfo: [AnyHashable : Any], text replyText: String) throws {
        NSLog("[msgNotificationContent] replyAction")
        try startCore()

        let peerAddress = userInfo["peer_addr"] as! String
        let localAddress = userInfo["local_addr"] as! String
        let peer = try lc!.createAddress(address: peerAddress)
        let local = try lc!.createAddress(address: localAddress)
        let room = lc!.findChatRoom(peerAddr: peer, localAddr: local)
        if let room = room {
            msgDelegate = LinphoneChatMessageManager()
            let chatMsg = try room.createMessage(message: replyText)
            chatMsg.addDelegate(delegate: msgDelegate)
            room.sendChatMessage(msg: chatMsg)
            room.markAsRead()
        }

        for i in 0...50 where !isReplySent && !needToStop {
            lc!.iterate()
            log.debug(msg: "[msgNotificationContent] reply \(i)")
            usleep(10000)
        }
    }

    func startCore() throws {
        config = Config.newWithFactory(configFilename: FileManager.preferenceFile(file: "linphonerc").path, factoryConfigFilename: "")
        setCoreLogger(config: config)
        lc = try! Factory.Instance.createSharedCoreWithConfig(config: config, systemContext: nil, appGroup: GROUP_ID, mainCore: false)

        coreDelegate = LinphoneCoreManager(self)
        lc!.addDelegate(delegate: coreDelegate)

        try lc!.start()
        log.message(msg: "[msgNotificationContent] core started")

        if (needToStop) {
            log.error(msg: "[msgNotificationContent] core stopped by app")
            throw LinphoneCoreError.timeout
        }
    }

    func stopCore() {
        lc!.stopAsync()
        // this iterate is needed: in case of reply there is no async task.
        // One iterate is needed to set the status of the shared core to Off
        lc!.iterate()
        for i in 0...100 where !coreStopped {
            lc!.iterate()
            log.debug(msg: "[msgNotificationContent] stop \(i)")
            usleep(10000)
        }
    }

    func setCoreLogger(config: Config) {
        let debugLevel = config.getInt(section: "app", key: "debugenable_preference", defaultValue: LogLevel.Debug.rawValue)
        let debugEnabled = (debugLevel >= LogLevel.Debug.rawValue && debugLevel < LogLevel.Error.rawValue)

        if (debugEnabled) {
            log = LoggingService.Instance /*enable liblinphone logs.*/
            logDelegate = LinphoneLoggingServiceManager()
            log.domain = "msgNotificationContent"
            log.logLevel = LogLevel(rawValue: debugLevel)
            log.addDelegate(delegate: logDelegate)
        }
    }

    class LinphoneCoreManager: CoreDelegate {
        unowned let parent: NotificationViewController

        init(_ parent: NotificationViewController) {
            self.parent = parent
        }

        override func onGlobalStateChanged(lc: Core, gstate: GlobalState, message: String) {
            log.message(msg: "[msgNotificationContent] global state changed: \(gstate) : \(message) \n")
            if (gstate == .Shutdown) {
                needToStop = true
            } else if (gstate == .Off) {
                coreStopped = true
            }
        }

        override func onRegistrationStateChanged(lc: Core, cfg: ProxyConfig, cstate: RegistrationState, message: String?) {
            log.message(msg: "[msgNotificationContent] registration state changed: \(cstate) for user id: \( String(describing: cfg.identityAddress?.asString()))\n")
        }
    }

    class LinphoneChatMessageManager: ChatMessageDelegate {
        override func onMsgStateChanged(msg: ChatMessage, state: ChatMessage.State) {
            log.message(msg: "[msgNotificationContent] msg state changed: \(state)\n")
            if (state == .Delivered) {
                isReplySent = true
            }
        }
    }
}

class LinphoneLoggingServiceManager: LoggingServiceDelegate {
    override func onLogMessageWritten(logService: LoggingService, domain: String, lev: LogLevel, message: String) {
        let level: String

        switch lev {
        case .Debug:
            level = "Debug"
        case .Trace:
            level = "Trace"
        case .Message:
            level = "Message"
        case .Warning:
            level = "Warning"
        case .Error:
            level = "Error"
        case .Fatal:
            level = "Fatal"
        default:
            level = "unknown"
        }

        NSLog("[\(level)] \(message)\n")
    }
}

extension FileManager {
    static func sharedContainerURL() -> URL {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUP_ID)!
    }

    static func exploreSharedContainer() {
        if let content = try? FileManager.default.contentsOfDirectory(atPath: FileManager.sharedContainerURL().path) {
            content.forEach { file in
                NSLog(file)
            }
        }
    }

    static func preferenceFile(file: String) -> URL {
        let fullPath = FileManager.sharedContainerURL().appendingPathComponent("Library/Preferences/linphone/")
        return fullPath.appendingPathComponent(file)
    }

    static func dataFile(file: String) -> URL {
        let fullPath = FileManager.sharedContainerURL().appendingPathComponent("Library/Application Support/linphone/")
        return fullPath.appendingPathComponent(file)
    }
}
