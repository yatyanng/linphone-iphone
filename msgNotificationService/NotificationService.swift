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

class NotificationService: UNNotificationServiceExtension { // TODO PAUL : add logs

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var lc: Core?
    var logDelegate: LinphoneLoggingServiceManager!
	var log: LoggingService!

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        NSLog("[msgNotificationService] start msgNotificationService extension")

        if let bestAttemptContent = bestAttemptContent {
			let config = Config.newWithFactory(configFilename: FileManager.preferenceFile(file: "linphonerc").path, factoryConfigFilename: "")
			setCoreLogger(config: config!)
			lc = try! Factory.Instance.createSharedCoreWithConfig(config: config!, systemContext: nil, appGroup: GROUP_ID, mainCore: false)

			let message = lc!.pushNotificationMessage

			if let message = message, let chatRoom = message.chatRoom {
				let msgData = parseMessage(room: chatRoom, message: message)

                if let badge = updateBadge() as NSNumber? {
                    bestAttemptContent.badge = badge
                }

				lc!.stop()

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
			} else {
				serviceExtensionTimeWillExpire()
			}
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
		lc?.stop() // TODO PAUL : may not be needed
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            NSLog("[msgNotificationService] serviceExtensionTimeWillExpire")
            bestAttemptContent.categoryIdentifier = "app_active"
            bestAttemptContent.title = NSLocalizedString("Message received", comment: "") + " [time out]" // TODO PAUL : a enlever
            bestAttemptContent.body = NSLocalizedString("You have received a message.", comment: "")          
            contentHandler(bestAttemptContent)
        }
    }

	func parseMessage(room: ChatRoom, message: ChatMessage) -> MsgData? {
		log.message(msg: "[msgNotificationService] Core received msg \(message.contentType) \n")

		if (message.contentType != "text/plain" && message.contentType != "image/jpeg") {
			return nil
		}

		let content = message.isText ? message.textContent : "🗻"
		let from = message.fromAddress?.username
		let callId = message.getCustomHeader(headerName: "Call-Id")
		let localUri = room.localAddress?.asStringUriOnly()
		let peerUri = room.peerAddress?.asStringUriOnly()

		var msgData = MsgData(from: from, body: "", subtitle: "", callId:callId, localAddr: localUri, peerAddr:peerUri)

		if let showMsg = lc!.config?.getBool(section: "app", key: "show_msg_in_notif", defaultValue: true), showMsg == true {
			if let subject = room.subject as String?, subject != "" {
				msgData.subtitle = subject
				msgData.body = from! + " : " + content
			} else {
				msgData.subtitle = from
				msgData.body = content
			}
		} else {
			if let subject = room.subject as String?, subject != "" {
				msgData.body = subject + " : " + from!
			} else {
				msgData.body = from
			}
		}

		log.message(msg: "[msgNotificationService] msg: \(content) \n")
		return msgData;
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
