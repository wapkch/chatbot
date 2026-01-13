//
//  Message.swift
//  chatme
//
//  Created by wangchao on 2026/1/9.
//

import Foundation
import CoreData

@objc(Message)
public class Message: NSManagedObject {

}

extension Message {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Message> {
        return NSFetchRequest<Message>(entityName: "Message")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var content: String?
    @NSManaged public var imageAttachments: String?
    @NSManaged public var isFromUser: Bool
    @NSManaged public var timestamp: Date?
    @NSManaged public var conversation: Conversation?

}

extension Message : Identifiable {

}