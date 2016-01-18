//
//  PersistenceManager.swift
//
//  Created by BJ on 1/18/16.
//  Copyright (c) 2015 Six Five Software, LLC. All rights reserved.
//

import Foundation
import CoreData


public enum CoreDataStoreType {
	case SQLite, InMemory, Binary
	
	public var storeTypeString: String {
		switch self {
		case .SQLite:
			return NSSQLiteStoreType
		case .InMemory:
			return NSInMemoryStoreType
		case .Binary:
			return NSBinaryStoreType
		}
	}
}

public struct PersistenceManager {
	
	public let mainContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
	private let privateContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
	
	private let callback: (PersistenceManager -> Void)?
	
	public init(modelName: String, storeType: CoreDataStoreType = .SQLite, callback: (PersistenceManager -> Void)? = nil) {
		self.callback = callback
		
		let modelURL = NSBundle.mainBundle().URLForResource(modelName, withExtension: "momd")!
		let mom = NSManagedObjectModel(contentsOfURL: modelURL)!
		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
		
		privateContext.persistentStoreCoordinator = coordinator
		mainContext.parentContext = privateContext
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
			let psc = self.privateContext.persistentStoreCoordinator!
			let options = [NSMigratePersistentStoresAutomaticallyOption : true, NSInferMappingModelAutomaticallyOption : true, NSSQLitePragmasOption : ["journal_mode" : "DELETE"]] as [NSObject : AnyObject]
			
			let fileManager = NSFileManager.defaultManager()
			let documentsURL = fileManager.URLsForDirectory(NSSearchPathDirectory.DocumentDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).last!
			let storeURL = documentsURL.URLByAppendingPathComponent("\(modelName).sqlite")
			
			try! psc.addPersistentStoreWithType(storeType.storeTypeString, configuration: nil, URL: storeURL, options: options)
			
			dispatch_async(dispatch_get_main_queue()) {
				callback?(self)
			}
		}
	}
	
	public func save() {
		guard privateContext.hasChanges && mainContext.hasChanges else { return }
		
		mainContext.performBlockAndWait {
			do {
				try self.mainContext.save()
			} catch {
				print("Error saving main context")
			}
		}
		
		privateContext.performBlock {
			do {
				try self.privateContext.save()
			} catch {
				print("Error saving private context")
			}
		}
		
	}
	
	public func fetchAll(entity entity: String, withPredicate predicate: NSPredicate? = nil) -> [AnyObject] {
		let fetchRequest = NSFetchRequest(entityName: entity)
		if let predicate = predicate {
			fetchRequest.predicate = predicate
		}
		do {
			let result = try mainContext.executeFetchRequest(fetchRequest)
			return result
		} catch {
			print("error fetching")
		}
		return []
	}
}

public struct WorkerContext {
	let context = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
	var parentContext: NSManagedObjectContext? {
		return context.parentContext
	}
	
	public init(parent: NSManagedObjectContext) {
		context.parentContext = parent
	}
	
	public func insert(entityName: String) -> NSManagedObject {
		let entity = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: context)
		return entity
	}
	
	public func delete(object object: NSManagedObject) {
		context.deleteObject(object)
	}
	
	public func save(completion: (Void -> Void)? = nil) {
		guard context.hasChanges else { return }
		
		context.performBlock {
			do {
				try self.context.save()
				completion?()
			} catch {
				print("Error saving worker context.")
			}
		}
	}
}
