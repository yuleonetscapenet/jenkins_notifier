//
//  PasteableNSTextField.swift
//  JenkinsNotifier
//
//  Created by Josh Outwater.
//
//

import AppKit
import Foundation

/**
 
 */
class PasteableNSTextField : NSTextField
{
    /**
        Overridden method of NSView.
     */
    override func performKeyEquivalent(with theEvent: NSEvent) -> Bool
    {
        if (theEvent.type == .keyDown)
            && ((theEvent.modifierFlags.rawValue & NSEventModifierFlags.command.rawValue) != 0)
        {
            if let textView = self.window?.firstResponder as? NSTextView
            {
                let range = textView.selectedRange()
                let bHasSelectedTexts = range.length > 0
                
                let keyCode: UInt16 = theEvent.keyCode
                
                var bHandled = false
                
                //0 A, 6 Z, 7 X, 8 C, 9 V
                if keyCode == 0
                {
                    textView.selectAll(self)
                    bHandled = true
                }
                else if keyCode == 6
                {
                    if textView.undoManager?.canUndo ?? false
                    {
                        textView.undoManager?.undo()
                        bHandled = true
                    }
                }
                else if keyCode == 7 && bHasSelectedTexts
                {
                    textView.cut(self)
                    bHandled = true
                }
                else if keyCode == 8 && bHasSelectedTexts
                {
                    textView.copy(self)
                    bHandled = true
                }
                else if keyCode == 9
                {
                    textView.paste(self)
                    bHandled = true
                }
                
                if bHandled
                {
                    return true
                }
            }
        }
        
        return false
    }
}
