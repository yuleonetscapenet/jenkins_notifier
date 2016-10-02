//
//  JenkinsProjectCreationController.swift
//  JenkinsNotifier
//
//  Created by Gerard Guillemette on 1/10/16.
//
//

import Foundation

class JenkinsProjectCreationController : NSWindowController
{
    @IBOutlet weak var createButton: NSButton!
    @IBOutlet weak var projectNameTextField: NSTextField!
    
    var defaultTitle: String?
    
    /**
        Overridden method of NSNibAwaking.
     */
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.window?.defaultButtonCell = self.createButton.cell as? NSButtonCell
        
        self.projectNameTextField.placeholderString = defaultTitle ?? ""
    }
    
    /**
        Callback for when the user decides not to create a new project.
     */
    @IBAction func didCancelButton(_ button:NSButton?)
    {
        if let window = self.window
        {
            window.sheetParent?.endSheet(window, returnCode: NSModalResponseCancel)
        }
    }
    
    /**
        Callback when user confirms they want a new project created.
     */
    @IBAction func didCreateButton(_ button:NSButton?)
    {
        if let window = self.window
        {
            window.sheetParent?.endSheet(window, returnCode: NSModalResponseOK)
        }
    }
}
