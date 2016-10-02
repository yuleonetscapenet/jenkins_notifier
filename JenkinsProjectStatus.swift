//
//  JenkinsProjectStatus.swift
//  JenkinsNotifier
//
//  Created by Josh Outwater.
//
//

import CoreData
import Foundation


/**
    The various possible Jenkins job statuses.  The info on these statuses can be found [here](http://jenkins-ci.361315.n4.nabble.com/jenkins-API-Where-can-I-find-a-definition-of-all-the-possible-values-for-the-quot-color-quot-variabl-td3457993.html) and [here](
        https://github.com/jenkinsci/jenkins/blob/master/core/src/main/java/hudson/model/BallColor.java).
 */
@objc enum BuildResult : Int16
{
    case success = 0
    case failure = 1
    case aborted = 2
    case unstable = 3
    case not_built = 4
}

/**
    This class provides the status for a JenkinsProject.  The status attributes are not made 
    part of the JenkinsProject so we can update the status on a thread separate than the one 
    which may be updating the JenkinsProject attributes .
 
    If we follow the convention of updating the status only on status update threads then we 
    can always modify the JenkinsProject on the main thread without any conflicts.  This 
    requires having a managed object context (MOC) on the status update thread which we can 
    save to.  The main thread will have another MOC that we can signal so that the main thread 
    can get the updates when it wants them.
 
    NOTES: A separate MOC is not being created for this version of the application.  We simply
           dispatch back to the main thread and handle the bookkeeping there.
 */
public final class JenkinsProjectStatus : NSManagedObject
{
    @NSManaged public fileprivate(set) var lastKnownStatusNumber: NSNumber
    @NSManaged public var hadResponse: Bool
    @NSManaged public var lastBuildNumber: NSNumber?
    @NSManaged public var failedBuildNumber: NSNumber?
    @NSManaged public var culpritsString: String?
    @NSManaged public var buildDescription: String?
    @NSManaged public var building: Bool
    @NSManaged public var name: String?
    @NSManaged public var updateDate: Date?
    @NSManaged public var responseStatusCode: NSNumber?
    @NSManaged public var requestError: NSNumber?
    @NSManaged public var requestErrorDescription: String?
    @NSManaged public var parseError: NSNumber?
    @NSManaged public var parseErrorDescription: String?
    
    @NSManaged public var project: JenkinsProject
    
    /**
        CoreData can't save an enum so this computed var will translate between the number stored and the enum we want.
     */
    var lastKnownStatus: BuildResult {
        get {
            return BuildResult(rawValue: lastKnownStatusNumber.int16Value) ?? .not_built
        }
        
        set {
            lastKnownStatusNumber = NSNumber(value: newValue.rawValue as Int16)
        }
    }
    
    /**
        Create a new JenkinsProjectStatus in the passed in CoreData context.
     */
    static func newJenkinsProjectStatus(_ manageObjectContext: NSManagedObjectContext, parent: JenkinsProject) -> JenkinsProjectStatus
    {
        // create
        let projectStatus = NSEntityDescription.insertNewObject(forEntityName: "JenkinsProjectStatus", into: manageObjectContext) as! JenkinsProjectStatus
        
        // set our default values
        projectStatus.lastKnownStatus = BuildResult.not_built
        projectStatus.building = false
        projectStatus.project = parent
        projectStatus.hadResponse = false
        
        return projectStatus
    }
    
    /**
        Get the job status for our parent JenkinsProject.
     
        When we have all the information from Jenkins we call back on the completionHandler to
        do some non-bookeeping tasks.
     */
    func updateStatus(_ completionHandler: @escaping () -> Void)
    {
        let statusCheckDate = Date()
        
        let request = NSMutableURLRequest()
        let jsonUrl: URL? = URL.init(string: "lastBuild/api/json", relativeTo: URL(string: self.project.urlString))
        request.url = jsonUrl
        guard let authString: String = NSString.init(format: "%@:%@", self.project.username, self.project.token).data(using: String.Encoding.utf8.rawValue)?.base64EncodedString(options: NSData.Base64EncodingOptions.lineLength64Characters) else { return }
        let valueBasic = String.init(format: "Basic %@", authString)
        request.setValue(valueBasic, forHTTPHeaderField:"Authorization")
        request.httpMethod = "GET"
        
        let session = URLSession.shared
        
        // Spawn off a task to get status of project.
        let task = session.dataTask(with:request as URLRequest, completionHandler: { (data: Data?, requestResponse: URLResponse?, error: Error?) -> Void in
            
            // We'll handle the bookeeping of status information on main thread.
            DispatchQueue.main.async { () -> Void in
                
                do
                {                    
                    // Is this a delayed update response just coming in after another for the same project?
                    if (self.updateDate as NSDate?)?.isGreaterThan(statusCheckDate) ?? false
                    {
                        return
                    }
                    
                    // If we at some point deleted the project then we don't need the results.
                    if self.project.deletionDate != nil
                    {
                        return
                    }
                    
                    self.updateDate = statusCheckDate
                    
                    if let anError = error
                    {
                        self.requestError = NSNumber(value:anError._code)
                        self.requestErrorDescription = anError.localizedDescription
                    }
                    else
                    {
                        self.requestError = 0
                        self.requestErrorDescription = nil
                    }
                    
                    self.parseError = 0
                    self.parseErrorDescription = ""
                    
                    self.hadResponse = requestResponse != nil
                    
                    if let responseCode = (requestResponse as? HTTPURLResponse)?.statusCode
                    {
                        self.responseStatusCode = NSNumber(value: responseCode as Int)
                    }
                    
                    var requestReply: NSDictionary = NSDictionary()
                    if data != nil
                    {
                        if let dictionaryResults = try JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.allowFragments) as? NSDictionary
                        {
                            requestReply = dictionaryResults
                        }
                    }
                    
                    let buildResult = requestReply["result"] as? String ?? ""
                    
                    self.building = requestReply["building"] as? Bool ?? false
                    self.lastBuildNumber = requestReply["number"] as? Int as NSNumber?
                    
                    let culpritsArray: [String] = requestReply["culprits"] as? [String] ?? []
                    if culpritsArray.count > 0
                    {
                        self.culpritsString = "Culprits: " + NSArray(array: culpritsArray).componentsJoined(by: ", ")
                    }
                    else
                    {
                        self.culpritsString = nil
                    }
                    
                    self.buildDescription = requestReply["description"] as? String
                    
                    self.name = requestReply["fullDisplayName"] as? String ?? ""
                    if let displayName = requestReply["displayName"] as? String , self.name?.hasSuffix(" " + displayName) ?? false
                    {
                        if let endIndex = self.name?.characters.index((self.name?.endIndex)!, offsetBy: -displayName.characters.count - 1)
                        {
                            self.name = self.name?.substring(to: endIndex)
                        }
                    }
                    
                    // http://jenkins-ci.361315.n4.nabble.com/jenkins-API-Where-can-I-find-a-definition-of-all-the-possible-values-for-the-quot-color-quot-variabl-td3457993.html
                    // https://github.com/jenkinsci/jenkins/blob/master/core/src/main/java/hudson/model/Result.java
                    switch buildResult
                    {
                        case "SUCCESS":
                            self.lastKnownStatus = .success
                            self.failedBuildNumber = nil
                        case "FAILURE":
                            self.lastKnownStatus = .failure
                            self.failedBuildNumber = self.lastBuildNumber
                        case "UNSTABLE":
                            self.lastKnownStatus = .unstable
                            self.failedBuildNumber = nil
                        case "ABORTED":
                            self.lastKnownStatus = .aborted
                            self.failedBuildNumber = nil
                        case "NOT_BUILT":
                            self.lastKnownStatus = .not_built
                            self.failedBuildNumber = nil
                        default:
                            self.lastKnownStatus = .not_built
                            self.failedBuildNumber = nil
                    }
                }
                catch
                {
                    self.parseError = 3840
                    self.parseErrorDescription = "Error parsing JSON"
                }
                
                guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
                      let manageObjectContext = appDelegate.managedObjectContext else { return }
                do
                {
                    try manageObjectContext.save()
                }
                catch
                {
                    
                }
                
                completionHandler()
            }
        })
        
        task.resume()
    }
    
    
    func build()
    {
        // Testing how to use a token to trigger the build.
        //    NSURLQueryItem *token = [[NSURLQueryItem alloc] initWithName:@"token" value:@"bab3270ae46823d5e0fae81892c42c49"];
        //    NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithString:@"http://test.com"];
        //    NSArray *queryItems = [[NSArray alloc] initWithObjects:token, nil];
        //    [urlComponents setQueryItems:queryItems];
        
        // Post to the URL.
    }
}






