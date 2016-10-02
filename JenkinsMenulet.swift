//
//  JenkinsMenulet.swift
//  JenkinsNotifier
//
//  Created by Josh Outwater.
//
//

import AppKit
import CoreData
import Foundation

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


/**
    Application class.
 */
class JenkinsMenulet : NSObject, NSWindowDelegate
{
    static var nextAvailableDeliveryDate = Date()
    static let kUpdateScheduleTime = 20.0
    
    fileprivate var statusItem: NSStatusItem?
    
    @IBOutlet weak var prefsWindow: NSWindow!
    @IBOutlet weak var prefsTable: NSTableView!
    @IBOutlet weak var jenkinsURLTextField: NSTextField!
    @IBOutlet weak var usernameTextField: NSTextField!
    @IBOutlet weak var tokenTextField: NSTextField!
    @IBOutlet weak var ignoreForSummaryCheckbox: NSButton!
    @IBOutlet weak var currentStatusImageView: NSImageView!
    @IBOutlet weak var statusInfoLabel: NSTextField!
    @IBOutlet weak var dateLabel: NSTextField!
    @IBOutlet weak var statusCodeLabel: NSTextField!
    
    fileprivate var failureIcon: NSImage?
    fileprivate var successIcon: NSImage?
    fileprivate var unstableIcon: NSImage?
    fileprivate var notBuiltIcon: NSImage?
    
    fileprivate var projects: Set<JenkinsProject>
    
    fileprivate var menu: NSMenu?
    fileprivate var preferencesMenuItem: NSMenuItem?
    fileprivate var quitMenuItem: NSMenuItem?
    
    // Track which build number we sent a notification for a build failure for a particular project.
    fileprivate var notificationSet: Set<JenkinsProject>
    // Base URL for Jenkins where all the projects are under.
    fileprivate var shouldRun: Bool
    
    fileprivate let URL_KEY = "JenkinsURL"
    fileprivate let TOKEN_KEY = "JenkinsAPIToken"
    fileprivate let USERNAME_KEY = "JenkinsUsername"
    
    fileprivate var currentProject: JenkinsProject?
    fileprivate var removingAProject: Bool
    
    fileprivate var showPrefsOnStartup: Bool
    
    fileprivate var sheet: JenkinsProjectCreationController?
    
    fileprivate let SECONDS_BETWEEN_NOTIFICATIONS = 5.0
    
    fileprivate lazy fileprivate(set) var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return dateFormatter
    } ()
    
    /**
        Default initializer.
     */
    override init()
    {
        self.shouldRun = false
        self.notificationSet = Set()
        self.projects = []
        self.removingAProject = false
        self.showPrefsOnStartup = false
        
        super.init()
        
        self.failureIcon = NSImage(named:"failure_build_icon")
        self.successIcon = NSImage(named:"success_build_icon")
        self.unstableIcon = NSImage(named: "unstable_build_icon")
        self.notBuiltIcon = NSImage(named:"not_built_build_icon")
        
        self.statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)
        let menuIcon = NSImage(named: "Jenkins")
        self.statusItem?.image = menuIcon
        self.statusItem?.highlightMode = true
        self.statusItem?.isEnabled = true
        self.statusItem?.action = #selector(JenkinsMenulet.statusItemAction(_:))
        self.statusItem?.target = self
        
        let savedProjects = allProjects()
        self.projects = Set<JenkinsProject>(savedProjects)
        if self.projects.count > 0
        {
            self.currentProject = self.projectForPrefsRow(0)
            
            shouldRun = true
        }
        else
        {
            showPrefsOnStartup = true
        }
        
        // Create the menu we will pop up when clicked.
        self.menu = NSMenu()
        updateMenuIcon()
        updateMenuItems()
        
        removeDeletedProjects()
        
        let timer = Timer.init(fireAt: Date(), interval: JenkinsMenulet.kUpdateScheduleTime, target: self, selector: #selector(JenkinsMenulet.updateStatus(_:)), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
    }
    
    /**
        Handles user clicking on "Apply".
     */
    @IBAction func applyButtonAction(_ sender: NSButton?)
    {
        saveCurrentPrefs()
        if let project = self.currentProject
        {
            self.populateStatus(project)
            self.shouldRun = true
            
            updateMenuIcon()
            updateMenuItems()
        }
    }
    
    /**
        Overridden method of NSObject.
     */
    override func awakeFromNib()
    {
        // http://stackoverflow.com/questions/7545490/how-can-i-have-the-only-column-of-my-nstableview-take-all-the-width-of-the-table
        self.prefsTable.sizeLastColumnToFit()
        
        statusInfoLabel.stringValue = "The Jenkins project status is requested every \(JenkinsMenulet.kUpdateScheduleTime) seconds once either the Apply or Close buttons are clicked.  If the URL provided for the Jenkins project points to an inoperative server the project status will only be returned after the request has timed out."
        
        dateLabel.stringValue = ""
        statusCodeLabel.stringValue = ""
        
        // What are the projects we want to track?
        // Check to see if we have login information saved, if not show the preferences panel.
        // Otherwise go ahead and start running.
        if let project = self.currentProject
        {
            populateFields(project)
        }
        
        if showPrefsOnStartup
        {
            self.showPreferences(self)
            showPrefsOnStartup = false
        }
        
        self.prefsTable.register(forDraggedTypes:[JenkinsNotifierPrivateTableViewDataType])
    }
    
    /**
        Update the menu with all required items.
     */
    fileprivate func updateMenuItems()
    {
        if self.menu?.items.count > 0
        {
            self.menu?.removeAllItems()
        }
        
        let sortedProjects = projects.sorted { (obj1: JenkinsProject, obj2: JenkinsProject) -> Bool in
            return obj1 < obj2
        }
        
        var listOrder: Int32 = 0
        for aProject in sortedProjects {
            aProject.listOrder = NSNumber(value: listOrder)
            listOrder += 1
        }

        // Create the menu items in sorted order
        for aProject in sortedProjects
        {
            if let item = createJenkinsMenuItemFor(aProject)
            {
                menu?.addItem(item)
            }
        }
        
        menu?.addItem(NSMenuItem.separator())
        
        // Add the preferences menu item.
        preferencesMenuItem = menu?.addItem(withTitle: "Preferences...", action: #selector(JenkinsMenulet.showPreferences(_:)), keyEquivalent: "")
        preferencesMenuItem?.target = self
        
        // Add a quit menu item.
        quitMenuItem = menu?.addItem(withTitle: "Quit", action: #selector(JenkinsMenulet.quitAction(_:)), keyEquivalent: "")
        quitMenuItem?.target = self
    }
    
    /**
        Create a menu item for a JenkinsProject.
     */
    fileprivate func createJenkinsMenuItemFor(_ project: JenkinsProject) -> NSMenuItem?
    {
        let menuItem = NSMenuItem(title: project.title, action: #selector(JenkinsMenulet.openBrowser(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.isEnabled = true
        
        // Set the represented object, the project URL, to this menu item so we can retrieve it 
        // later and open a browser to the project web page.
        if project.urlString.characters.count > 0
        {
            // Create a new URL that points to the REST URL that returns JSON information for the last build.
            menuItem.representedObject = URL(string:project.urlString)
        }
        
        var image = menuImageForStatus(project.status.lastKnownStatus)
        if project.ignoreForSummary
        {
            image = annotateImage(baseImage: image)
        }
        menuItem.image = image
        
        return menuItem
    }
    
    /**
        Callback to popup the menu item list.
     */
    func statusItemAction(_ sender: AnyObject?)
    {
        guard let menu = self.menu else { return }
        self.statusItem?.popUpMenu(menu)
    }
    
    /**
        If the user selects a project open up the status in their browser.
     */
    func openBrowser(_ sender: NSMenuItem?)
    {
        guard let baseURL = sender?.representedObject as? URL else { return }
        guard let url = URL(string: "lastBuild/", relativeTo: baseURL) else { return }
        NSWorkspace.shared().open(url)
    }
    
    /**
        Based on the status of the builds, update the icon in the menu bar.
        Icons created from logos at https://wiki.jenkins-ci.org/display/JENKINS/Logo
     */
    fileprivate func updateMenuIcon()
    {
        let projects = self.allProjects()
        
        var finalStatus: BuildResult?
        
        // check for the worse
        for aProject in projects where !aProject.ignoreForSummary
        {
            if aProject.status.lastKnownStatus == .failure
            {
                finalStatus = .failure
                break
            }
        }
        
        // check for the best
        if finalStatus == nil
        {
            for aProject in projects where !aProject.ignoreForSummary
            {
                if aProject.status.lastKnownStatus == .success
                {
                    finalStatus = .success
                    break
                }
            }
        }
        
        // if there is no best or worse see if there's unstable
        if finalStatus == nil
        {
            for aProject in projects where !aProject.ignoreForSummary
            {
                if aProject.status.lastKnownStatus == .unstable
                {
                    finalStatus = .unstable
                    break
                }
            }
        }
        
        // if we haven't had any failures or successes then just go with default
        finalStatus = finalStatus ?? .not_built
        
        switch(finalStatus!)
        {
            case .success:
                self.statusItem?.image = NSImage(named: "success_summary_icon")
            case .failure:
                self.statusItem?.image = NSImage(named: "failure_summary_icon")
            case .unstable:
                self.statusItem?.image = NSImage(named: "unstable_summary_icon")
            case .aborted, .not_built:
                self.statusItem?.image = NSImage(named: "not_built_summary_icon")
        }
    }
    
    /**
        Update the status of all the projects.
     */
    func updateStatus(_ sender: AnyObject?)
    {
        if !self.shouldRun
        {
            return
        }
        
        // Get the statuses of each project on a separate thread and update the status on the main thread.
        objc_sync_enter(sender)
        defer { objc_sync_exit(sender) }
        do
        {
            for targetProject in projects
            {
                // Asynchronously get the status of the project.
                targetProject.status.updateStatus() {
                    
                    // Handle response from the server on the main thread.
                    
                    let lastKnownStatus = targetProject.status.lastKnownStatus
                    
                    let statusIconImage = self.menuImageForStatus(lastKnownStatus)
                    switch(lastKnownStatus)
                    {
                        case .success:
                            // We now have a successful build.  If the build had failed previously remove it from the notifications
                            // dictionary so we will send a notification next time it breaks.  Send a notification that the project
                            // is now successfully building.
                            if self.notificationSet.contains(targetProject)
                            {
                                self.scheduleFixedBuildNotification(targetProject, withDeliveryDate: self.nextAvailableNotificationDeliveryDate())
                                self.notificationSet.remove(targetProject)
                            }
                        case .failure:
                            // If we already have an entry for this project we sent a notification.  Don't send another one.  Otherwise
                            // add it to the list and
                            if !self.notificationSet.contains(targetProject)
                            {
                                self.notificationSet.insert(targetProject)
                                self.scheduleNotification(targetProject, withDeliveryDate: self.nextAvailableNotificationDeliveryDate())
                            }
                        case .aborted, .unstable, .not_built:
                            do
                            {
                                // Nothing to do
                            }
                    }
                    
                    // Update menu icon.
                    self.updateMenuIcon()
                    
                    // Update menu item icon for this project.
                    var annotatedImage = statusIconImage
                    if targetProject.ignoreForSummary
                    {
                        annotatedImage = self.annotateImage(baseImage: statusIconImage)
                    }
                    self.menu?.item(withTitle: targetProject.title)?.image = annotatedImage
                    
                    if let projectToUpdate = self.currentProject , targetProject == projectToUpdate
                    {
                        self.populateStatus(projectToUpdate)
                    }
                }
            }
        }
    }
    
    /**
        Notifications should be spaced out.  This method determines when the next time is that we can send out
        a notification.
     */
    fileprivate func nextAvailableNotificationDeliveryDate() -> Date
    {
        var deliveryDate = Date(timeInterval: self.SECONDS_BETWEEN_NOTIFICATIONS, since: Date())
        if (JenkinsMenulet.nextAvailableDeliveryDate as NSDate).isGreaterThan(deliveryDate)
        {
            deliveryDate = JenkinsMenulet.nextAvailableDeliveryDate
        }
        JenkinsMenulet.nextAvailableDeliveryDate = Date(timeInterval: self.SECONDS_BETWEEN_NOTIFICATIONS, since: deliveryDate)
        return deliveryDate
    }
    
    /**
        Image to use in menu for status.
     */
    fileprivate func menuImageForStatus(_ status: BuildResult) -> NSImage?
    {
        var backImage = successIcon
        switch(status)
        {
            case .success:
                backImage =  successIcon
            case .failure:
                backImage =  failureIcon
            case .unstable:
                backImage =  unstableIcon
            case .aborted, .not_built:
                backImage =  notBuiltIcon
        }
        
        return backImage
    }
    
    /**
        Annotate image for indicating a condition is met or not met.
        The meaning is based on it's utilization.
     
        - parameter baseImage: the annotation will be drawn on top of this image
        - return: baseImage with annotation on top of it
        - seealso: https://gist.github.com/randomsequence/b9f4462b005d0ced9a6c
     */
    fileprivate func annotateImage(baseImage: NSImage?) -> NSImage
    {
        guard let baseImage = baseImage else { return NSImage() }
        
        let size = CGSize(width: baseImage.size.width, height: baseImage.size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let aContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue)
        
        guard let context = aContext else { return NSImage() }
        
        let rect = NSMakeRect(0, 0, (baseImage.size.width), (baseImage.size.height))
        let aBaseCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        
        guard let baseCGImage = aBaseCGImage else { return NSImage() }
        
        context.draw(baseCGImage, in: rect)
        
        let position = (baseImage.size.width - baseImage.size.width/4.0)/2.0
        let rect2 = CGRect(x: position, y: position, width: baseImage.size.width/4.0, height: baseImage.size.height/4.0)
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: rect2);
        
        let anImage = context.makeImage()
        
        guard let image = anImage else { return NSImage() }
        
        return NSImage(cgImage: image, size: size)
    }
    
    /**
     
     */
    fileprivate func scheduleFixedBuildNotification(_ project: JenkinsProject, withDeliveryDate deliveryDate: Date)
    {
        // For each of the entries we have update the status.
        let notification = NSUserNotification()
        let notificationTitle = project.title
        notification.title = notificationTitle + " fixed"
        notification.deliveryDate = deliveryDate
        notification.hasActionButton = true
        NSUserNotificationCenter.default.scheduleNotification(notification)
    }
    
    /**
     
     */
    fileprivate func scheduleNotification(_ project: JenkinsProject, withDeliveryDate deliveryDate:Date)
    {
        // For each of the entries we have update the status.
        let notification = NSUserNotification()
        let notificationTitle = project.title
        notification.title = notificationTitle + " failed"
        notification.hasActionButton = true
        notification.informativeText = project.status.culpritsString ?? ""
        notification.deliveryDate = deliveryDate
        NSUserNotificationCenter.default.scheduleNotification(notification)
    }
    
    /**
        Show the preferences dialog.
     */
    func showPreferences(_ sender: AnyObject?)
    {
        // Center the preferences window and place at the top of the screen.
        let width = ((NSScreen.main()!.frame.size.width)/2) - (self.prefsWindow.frame.size.width/2)
        let height = (NSScreen.main()!.frame.size.height) - self.prefsWindow.frame.size.height - 30
        let location = NSPoint(x: width, y: height)
        self.prefsWindow.setFrameOrigin(location)
        NSApplication.shared().activate(ignoringOtherApps: true)
        
        if let project = self.currentProject
        {
            let row = self.prefsRowForProject(project)
            let aSet = IndexSet(integer: row)
            self.prefsTable.selectRowIndexes(aSet, byExtendingSelection: false)
            populateFields(project)
        }

        self.prefsWindow.makeKeyAndOrderFront(sender)
        
        if self.currentProject == nil
        {
            addProjectAction()
        }
    }
    
    /**
        Check if the project parameters make up a valid project in prefs window.
     */
    fileprivate func isValidProject() -> Bool
    {
        if jenkinsURLTextField.stringValue.characters.count <= 0
        {
            return false
        }
        
        return true
    }
    
    /**
        Fill in the status UI elements in the preferences dialog.
     */
    fileprivate func populateStatus(_ project: JenkinsProject)
    {
        self.dateLabel.stringValue = ""
        self.statusCodeLabel.stringValue = ""
        currentStatusImageView.image = menuImageForStatus(.not_built)
        
        if !self.isValidProject()
        {
            return
        }
        
        if let date = project.status.updateDate
        {
            self.dateLabel.stringValue = dateFormatter.string(from: date as Date)
        }
        
        currentStatusImageView.image = menuImageForStatus(project.status.lastKnownStatus)
        
        if project.status.parseError != 0
        {
            let errorCode = project.status.parseError ?? 0
            let errorDescription = project.status.parseErrorDescription ?? ""
            self.statusCodeLabel.stringValue = "\(errorDescription)\nJSON(\(errorCode))"
        }
        else if project.status.requestError != 0
        {
            let errorCode = project.status.requestError ?? 0
            let errorDescription = project.status.requestErrorDescription ?? ""
            self.statusCodeLabel.stringValue = "\(errorDescription)\nURLRequest(\(errorCode))"
        }
        else if let responseCode = project.status.responseStatusCode?.intValue
        {
            switch (responseCode)
            {
                case 200:
                    if !project.status.hadResponse
                    {
                        self.statusCodeLabel.stringValue = "Empty response\nHTTP(200)"
                    }
                case 400..<600:
                    self.statusCodeLabel.stringValue = "\(HTTPURLResponse.localizedString(forStatusCode: responseCode))\nHTTP(\(responseCode))"
                default:
                    break
            }
        }
    }
    
    /**
        Fill in text fields with project information.
     */
    fileprivate func populateFields(_ project: JenkinsProject)
    {
        self.jenkinsURLTextField.stringValue = project.urlString 
        self.usernameTextField.stringValue = project.username 
        self.tokenTextField.stringValue = project.token 
        self.ignoreForSummaryCheckbox.state = project.ignoreForSummary ? NSOnState : NSOffState
        
        self.populateStatus(project)
    }
    
    /**
        Add a project for information about another project we aren't currently monitoring.
     */
    fileprivate func addProjectAction()
    {
        self.sheet = JenkinsProjectCreationController(windowNibName: "JenkinsProjectCreationController")
        self.sheet?.defaultTitle = uniqueProjectName()
        let sheetWindow: NSWindow = self.sheet!.window!
        prefsWindow.beginSheet(sheetWindow) { (response: NSModalResponse) -> Void in
            switch (response) {
                case NSModalResponseOK:
                    var title = self.sheet?.projectNameTextField?.stringValue ?? ""
                    if title.characters.count == 0
                    {
                        title = self.sheet?.defaultTitle ?? self.uniqueProjectName()
                    }
                    self.createNewProject(title)
                case NSModalResponseCancel:
                    break
                default:
                    break
            }
            self.sheet = nil
        }
    }
    
    /**
        Create a new project with a given title.
     */
    fileprivate func createNewProject(_ title: String)
    {
        guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
            let manageObjectContext = appDelegate.managedObjectContext else { return }
        
        let project = JenkinsProject.newJenkinsProject(manageObjectContext)
        project.title = title
        let _ = try? manageObjectContext.save()
        
        let savedProjects = allProjects()
        self.projects = Set(savedProjects)
        
        self.prefsTable.reloadData()
        
        self.currentProject = project
        populateFields(project)
        let row = self.prefsRowForProject(project)
        let aSet = IndexSet(integer: row)
        self.prefsTable.selectRowIndexes(aSet, byExtendingSelection: false)
        
        updateMenuIcon()
        updateMenuItems()
    }
    
    /**
        Get a unique project name.
     */
    fileprivate func uniqueProjectName() -> String
    {
        var projectCount = 0
        repeat
        {
            let title = "Project \(projectCount)"
            var isDuplicate: Bool = false
            for aProject in self.projects
            {
                if aProject.title == title
                {
                    isDuplicate = true
                    break
                }
            }
            if !isDuplicate
            {
                return title
            }
            projectCount += 1
        
        } while true
    }
    
    /**
        Callback for when the chooser chooses to have the current project ignored or not
         in the summary of the project statuses.
     */
    @IBAction func ignoreForSummaryAction(_ sender: AnyObject?)
    {
        self.currentProject?.ignoreForSummary = self.ignoreForSummaryCheckbox.state == NSOnState
        
        updateMenuIcon()
    }
    
    /**
        Handle "+" and "-" actions below project table.
     */
    @IBAction func projectAction(_ sender: AnyObject?)
    {
        guard let segmentedControl = sender as? NSSegmentedControl else { return }
        if segmentedControl.selectedSegment == 0
        {
            self.addProjectAction()
        }
        else if segmentedControl.selectedSegment == 1
        {
            self.removeProjectAction()
        }
    }
    
    /**
        Remove a project from the ones we are monitoring.
     */
    fileprivate func removeProjectAction()
    {
        self.removingAProject = true
        defer { removingAProject = false }
        
        if allProjects().count <= 0
        {
            return
        }
        
        guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
              let manageObjectContext = appDelegate.managedObjectContext else { return }
        
        var row = self.prefsRowForProject(self.currentProject!)
        row -= 1
        
        self.projects.remove(self.currentProject!)
        
        self.currentProject!.deletionDate = Date()
        do
        {
            try manageObjectContext.save()
        }
        catch
        {
            NSLog("Error: Couldn't delete project.")
        }
        
        self.prefsTable.reloadData()
        
        self.currentProject = nil
        if row >= 0
        {
            self.currentProject = self.projectForPrefsRow(row)
            let aSet = IndexSet(integer: row)
            self.prefsTable.selectRowIndexes(aSet, byExtendingSelection: false)
        }
        
        updateMenuIcon()
        updateMenuItems()
    }
    
    /**
        Close the preferences dialog.
     */
    @IBAction func closePreferences(_ sender: AnyObject?)
    {
        if self.prefsWindow.isVisible
        {
            defer { prefsWindow.close() }
            
            let row = prefsTable.selectedRow
            
            if row < 0
            {
                return
            }
            
            self.saveCurrentPrefs()
            
            self.shouldRun = true
            
            updateMenuIcon()
            updateMenuItems()
        }
    }
    
    /**
        Save the preferences that we currently have input for a project.
     */
    fileprivate func saveCurrentPrefs()
    {
        if self.removingAProject || self.currentProject == nil
        {
            return
        }
        
        // Save changes if necessary
        let url = jenkinsURLTextField.stringValue 
        let username = usernameTextField.stringValue 
        let token = tokenTextField.stringValue 
        let ignoreForSummary = ignoreForSummaryCheckbox.state == NSOnState
        if currentProject?.urlString == url
            && currentProject?.username == username
            && currentProject?.token == token
            && currentProject?.ignoreForSummary == ignoreForSummary
        {
            return
        }
        
        // Since we may be getting the status on a separate thread for the previous configuration
        // of the project we'll just create a new project and later ignore the results of the previous 
        // version of the project.
        let updatedProject = JenkinsProject.newJenkinsProject(self.currentProject!.managedObjectContext!)
        updatedProject.title = self.currentProject!.title
        updatedProject.projectId = self.currentProject!.projectId
        updatedProject.createdDate = self.currentProject!.createdDate
        updatedProject.listOrder = self.currentProject!.listOrder
        
        updatedProject.urlString = url
        updatedProject.username = username
        updatedProject.token = token
        updatedProject.ignoreForSummary = ignoreForSummary
        
        do
        {
            self.currentProject?.deletionDate = Date()
            try self.currentProject?.managedObjectContext?.save()
            self.projects.remove(self.currentProject!)
            
            self.projects.insert(updatedProject)
            self.currentProject = updatedProject
            try self.currentProject?.managedObjectContext?.save()
        }
        catch
        {
            
        }
        
        self.updateMenuIcon()
        self.updateMenuItems()
    }
    
    /**
        Quit out of this application.
     */
    func quitAction(_ sender: AnyObject?)
    {
        NSApplication.shared().terminate(nil)
    }
    
    /**
        Get all the projects that CoreData knows about that haven't been deleted.
     */
    fileprivate func allProjects() -> [JenkinsProject]
    {
        let request: NSFetchRequest<JenkinsProject> = NSFetchRequest(entityName: "JenkinsProject")
        let sortDescriptor = NSSortDescriptor(key: "title", ascending: false)
        request.sortDescriptors = [sortDescriptor]
        let predicate = NSPredicate(format: "deletionDate == nil")
        request.predicate = predicate
        request.fetchBatchSize = 20
        
        guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
              let manageObjectContext = appDelegate.managedObjectContext
        else
        {
            return []
        }
        
        do
        {
            let projects = try manageObjectContext.fetch(request)
            
            return projects
        }
        catch
        {
            return []
        }
    }
    
    /**
        Delete projects that were slated for removal.
     */
    fileprivate func removeDeletedProjects()
    {
        let request: NSFetchRequest<JenkinsProject> = NSFetchRequest(entityName: "JenkinsProject")
        let predicate = NSPredicate(format: "deletionDate <= %@", Date(timeInterval:(60*60*24), since: Date()) as CVarArg)
        request.predicate = predicate
        request.fetchBatchSize = 20
        
        guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
              let manageObjectContext = appDelegate.managedObjectContext
            else
        {
            return
        }
        
        do
        {
            let projectsToDelete = try manageObjectContext.fetch(request)
            
            if projectsToDelete.count > 0
            {
                for aProjectToDelete in projectsToDelete
                {
                    manageObjectContext.delete(aProjectToDelete)
                }
                
                try manageObjectContext.save()
            }
        }
        catch
        {
            NSLog("Error removing project.")
        }
    }
    
    /**
        What is the the project associated with the rowth index in the preferences table of projects?
     */
    fileprivate func projectForPrefsRow(_ row: Int) -> JenkinsProject
    {
        let sortedProjects = self.projects.sorted() { (obj1: JenkinsProject, obj2: JenkinsProject) -> Bool in
            return obj1 < obj2
        }
        
        let project = sortedProjects[row]
        
        return project
    }
    
    /**
        What row is the "project" listed in the table?
     */
    fileprivate func prefsRowForProject(_ project: JenkinsProject) -> Int
    {
        let sortedProjects = self.projects.sorted() { (obj1: JenkinsProject, obj2: JenkinsProject) -> Bool in
            return obj1 < obj2
        }
        
        return sortedProjects.index(of: project)!
    }
}

extension JenkinsMenulet: NSTableViewDelegate
{
    /**
     Overriden method of NSTableViewDelegate
     */
    func tableViewSelectionDidChange(_ notification: Notification)
    {
        let row = prefsTable.selectedRow
        if row < 0
        {
            return
        }
        
        self.saveCurrentPrefs()
        
        self.currentProject = projectForPrefsRow(row)
        
        populateFields(self.currentProject!)
    }
}

fileprivate let JenkinsNotifierPrivateTableViewDataType = "JenkinsNotifierPrivateTableViewDataType"

extension JenkinsMenulet: NSTableViewDataSource
{
    /**
     Overriden method of NSTableViewDataSource
     */
    func numberOfRows(in tableView: NSTableView) -> Int
    {
        return self.projects.count
    }
    
    /**
     Overriden method of NSTableViewDataSource
     */
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any?
    {
        let project = projectForPrefsRow(row)
        
        return project.title
    }
    
    /**
     For drag and drop support.
     
     - seealso: http://stackoverflow.com/questions/33434434/how-to-reorder-rows-in-nstableview
     */
    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool
    {
        let zNSIndexSetData = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
        
        pboard.declareTypes([JenkinsNotifierPrivateTableViewDataType], owner: self)
        
        pboard.setData(zNSIndexSetData, forType:JenkinsNotifierPrivateTableViewDataType)
        
        return true
    }
    
    /**
     For drag and drop support.
     
     - seealso: http://stackoverflow.com/questions/33434434/how-to-reorder-rows-in-nstableview
     */
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation
    {
        return NSDragOperation.every
    }
    
    /**
     For drag and drop support.
     
     - seealso: http://stackoverflow.com/questions/33434434/how-to-reorder-rows-in-nstableview
     */
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool
    {
        let pboard = info.draggingPasteboard()
        let rowData = pboard.data(forType:JenkinsNotifierPrivateTableViewDataType)
        let rowIndexes: NSIndexSet? = NSKeyedUnarchiver.unarchiveObject(with:rowData!) as? NSIndexSet
        let dragRow = rowIndexes?.firstIndex
        
        if (dragRow < row)
        {
            // Re-order the model data
            do {
                var sortedProjects = projects.sorted { (obj1: JenkinsProject, obj2: JenkinsProject) -> Bool in
                    return obj1 < obj2
                }
                sortedProjects.insert(sortedProjects[dragRow!], at: row)
                sortedProjects.remove(at: dragRow!)
                
                var index: Int32 = 0
                for aProject: JenkinsProject in sortedProjects
                {
                    aProject.listOrder = NSNumber(value:index)
                    index += 1
                }
            }
            
            tableView.noteNumberOfRowsChanged()
            tableView.moveRow(at: dragRow!, to: row - 1)
        }
        else
        {
            // Re-order the model data
            do {
                var sortedProjects = projects.sorted { (obj1: JenkinsProject, obj2: JenkinsProject) -> Bool in
                    return obj1 < obj2
                }
                let movedProject = sortedProjects.remove(at: dragRow!)
                sortedProjects.insert(movedProject, at: row)
                
                var index: Int32 = 0
                for aProject: JenkinsProject in sortedProjects
                {
                    aProject.listOrder = NSNumber(value:index)
                    index += 1
                }
            }
            
            tableView.noteNumberOfRowsChanged()
            tableView.moveRow(at: dragRow!, to: row)
        }
        
        guard let appDelegate = NSApp.delegate as? JenkinsNotifierAppDelegate,
              let manageObjectContext = appDelegate.managedObjectContext else { return false }
        do
        {
            try manageObjectContext.save()
        }
        catch
        {
            
        }
        
        updateMenuItems()
        
        return true
    }
}

// Notes on my Linux VM Jenkins set up running on MacPro.
//
// http://192.168.61.131:8080/job/Test2/lastBuild
// gerard
// 4ed905e750caceed90156be1caf1da2a





