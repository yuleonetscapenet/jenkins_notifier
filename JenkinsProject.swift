//
//  JenkinsProject.swift
//  JenkinsNotifier
//
//  Created by Josh Outwater.
//
//

import CoreData
import Foundation

/**
    This class contains the credentials needed to get job information.
 */
public final class JenkinsProject : NSManagedObject, Comparable
{
    @NSManaged public var urlString: String
    @NSManaged public var title: String
    @NSManaged public var username: String
    @NSManaged public var token: String
    @NSManaged public var deletionDate: Date?
    @NSManaged public var projectId: String
    @NSManaged public var createdDate: Date
    @NSManaged public var ignoreForSummary: Bool
    @NSManaged public var listOrder: NSNumber
    @NSManaged public fileprivate(set) var modifiedDate: Date
    
    @NSManaged public fileprivate(set) var status: JenkinsProjectStatus
    
    /**
        Create a new JenkinsProjectStatus in the passed in CoreData context.
     */
    static func newJenkinsProject(_ manageObjectContext: NSManagedObjectContext) -> JenkinsProject
    {
        // create
        let project = NSEntityDescription.insertNewObject(forEntityName: "JenkinsProject", into: manageObjectContext) as! JenkinsProject
        
        // set defaults
        project.urlString = ""
        project.title = ""
        project.username = ""
        project.token = ""
        project.ignoreForSummary = false
        
        project.projectId = UUID().uuidString
        
        project.createdDate = Date()
        project.modifiedDate = Date()
        
        project.listOrder = NSNumber(value:INT32_MAX)
        
        // create and assign an associated status object
        let projectStatus = JenkinsProjectStatus.newJenkinsProjectStatus(manageObjectContext, parent: project)
        project.status = projectStatus
        
        return project
    }
}

/**
    Equality for projects.
 */
public func ==(x: JenkinsProject, y: JenkinsProject) -> Bool
{
    return (x.projectId == y.projectId) && (x.title == y.title) && (x.modifiedDate == y.modifiedDate)
}

/**
    We order the same project based on the listOrder.
 */
public func <(x: JenkinsProject, y: JenkinsProject) -> Bool
{
    return x.listOrder.int32Value < y.listOrder.int32Value
}
