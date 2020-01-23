/*
* Copyright (c) 2010-2019 Belledonne Communications SARL.
*
* This file is part of linphone-iphone
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

import UserNotifications
import linphonesw

var GROUP_ID = "group.org.linphone.phone.msgNotification"

struct MsgData: Codable {
    var from: String?
    var body: String?
    var subtitle: String?
    var callId: String?
    var localAddr: String?
    var peerAddr: String?
}

var msgData: MsgData?
var msgReceived: Bool = false
var log: LoggingService!

class NotificationService: UNNotificationServiceExtension {

    enum LinphoneCoreError: Error {
        case timeout
    }

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var lc: Core?
    var config: Config!
    var logDelegate: LinphoneLoggingServiceManager!
    var coreDelegate: LinphoneCoreManager!

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        NSLog("[msgNotificationService] start msgNotificationService extension")

        if let bestAttemptContent = bestAttemptContent {
            do {
                try startCore()

                if let badge = updateBadge() as NSNumber? {
                    bestAttemptContent.badge = badge
                }

                stopCore()

                bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "msg.caf"))
                bestAttemptContent.title = NSLocalizedString("Message received", comment: "") + " [extension]"
                if let subtitle = msgData?.subtitle {
                    bestAttemptContent.subtitle = subtitle
                }
                if let body = msgData?.body {
                    bestAttemptContent.body = body
                }

                bestAttemptContent.categoryIdentifier = "msg_cat"

                bestAttemptContent.userInfo.updateValue(msgData?.callId as Any, forKey: "CallId")
                bestAttemptContent.userInfo.updateValue(msgData?.from as Any, forKey: "from")
                bestAttemptContent.userInfo.updateValue(msgData?.peerAddr as Any, forKey: "peer_addr")
                bestAttemptContent.userInfo.updateValue(msgData?.localAddr as Any, forKey: "local_addr")

                contentHandler(bestAttemptContent)
            } catch {
                NSLog("[msgNotificationService] failed to start shared core")
                serviceExtensionTimeWillExpire()
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        stopCore()
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            NSLog("[msgNotificationService] serviceExtensionTimeWillExpire")
            bestAttemptContent.categoryIdentifier = "app_active"
            bestAttemptContent.title = NSLocalizedString("Message received", comment: "") + " [time out]" // TODO PAUL : a enlever
            bestAttemptContent.body = NSLocalizedString("You have received a message.", comment: "")          
            contentHandler(bestAttemptContent)
        }
    }

    func startCore() throws {
        msgReceived = false

        config = Config.newWithFactory(configFilename: FileManager.preferenceFile(file: "linphonerc").path, factoryConfigFilename: "")
        setCoreLogger(config: config)
        lc = try! Factory.Instance.createSharedCoreWithConfig(config: config, systemContext: nil, appGroup: GROUP_ID, mainCore: false)

        coreDelegate = LinphoneCoreManager(self)
        lc!.addDelegate(delegate: coreDelegate)

        try lc!.start()

        log.message(msg: "[msgNotificationService] core started")
        lc!.refreshRegisters()

        for i in 0...100 where !msgReceived {
            lc!.iterate()
            log.debug(msg: "[msgNotificationService] \(i)")
            usleep(100000)
        }

        if (!msgReceived) {
            throw LinphoneCoreError.timeout
        }
    }

    func stopCore() {
        if let lc = lc {
            if let coreDelegate = coreDelegate {
                lc.removeDelegate(delegate: coreDelegate)
            }
            lc.networkReachable = false
            lc.stop()
        }
    }

    func setCoreLogger(config: Config) {
        let debugLevel = config.getInt(section: "app", key: "debugenable_preference", defaultValue: LogLevel.Debug.rawValue)
        let debugEnabled = (debugLevel >= LogLevel.Debug.rawValue && debugLevel < LogLevel.Error.rawValue)

        if (debugEnabled) {
            log = LoggingService.Instance /*enable liblinphone logs.*/
            logDelegate = LinphoneLoggingServiceManager()
            log.domain = "msgNotificationService"
            log.logLevel = LogLevel(rawValue: debugLevel)
            log.addDelegate(delegate: logDelegate)
        }
    }

    func updateBadge() -> Int {
        var count = 0
        count += lc!.unreadChatMessageCount
        count += lc!.missedCallsCount
        count += lc!.callsNb
        log.message(msg: "[msgNotificationService] badge: \(count)\n")

        return count
    }


    class LinphoneCoreManager: CoreDelegate {
        unowned let parent: NotificationService

        init(_ parent: NotificationService) {
            self.parent = parent
        }

        override func onGlobalStateChanged(lc: Core, gstate: GlobalState, message: String) {
            log.message(msg: "[msgNotificationService] onGlobalStateChanged \(gstate) : \(message) \n")
            if (gstate == .Shutdown) {
                parent.serviceExtensionTimeWillExpire()
            }
        }

        override func onRegistrationStateChanged(lc: Core, cfg: ProxyConfig, cstate: RegistrationState, message: String?) {
            log.message(msg: "[msgNotificationService] New registration state \(cstate) for user id \( String(describing: cfg.identityAddress?.asString()))\n")
        }

        override func onMessageReceived(lc: Core, room: ChatRoom, message: ChatMessage) {
            log.message(msg: "[msgNotificationService] Core received msg \(message.contentType) \n")
            // content.userInfo = @{@"from" : from, @"peer_addr" : peer_uri, @"local_addr" : local_uri, @"CallId" : callID, @"msgs" : msgs};

            if (message.contentType != "text/plain" && message.contentType != "image/jpeg") {
                return
            }

            let content = message.isText ? message.textContent : "🗻"
            let from = message.fromAddress?.username
            let callId = message.getCustomHeader(headerName: "Call-Id")
            let localUri = room.localAddress?.asStringUriOnly()
            let peerUri = room.peerAddress?.asStringUriOnly()

            msgData = MsgData(from: from, body: "", subtitle: "", callId:callId, localAddr: localUri, peerAddr:peerUri)

            if let showMsg = lc.config?.getBool(section: "app", key: "show_msg_in_notif", defaultValue: true), showMsg == true {
                if let subject = room.subject as String?, subject != "" {
                    msgData?.subtitle = subject
                    msgData?.body = from! + " : " + content
                } else {
                    msgData?.subtitle = from
                    msgData?.body = content
                }
            } else {
                if let subject = room.subject as String?, subject != "" {
                    msgData?.body = subject + " : " + from!
                } else {
                    msgData?.body = from
                }
            }

            log.message(msg: "[msgNotificationService] msg: \(content) \n")
            msgReceived = true
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
