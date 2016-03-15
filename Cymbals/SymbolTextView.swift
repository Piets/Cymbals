//
//  SymbolTextView.swift
//  Cymbals
//
//  Created by Peter Kraml on 13.03.16.
//  Copyright © 2016 MacPiets Apps. All rights reserved.
//

import Cocoa

class SymbolTextView: NSTextView {
	
	var dsymURL: NSURL? {
		didSet {
			dsymView.hidden = (self.dsymURL == nil)
			
			if let url = dsymURL {
				let filename = (url.URLByDeletingPathExtension?.lastPathComponent)!
				dsymLabel.stringValue = "Using dSYM: \(filename)"
			}
		}
	}
	
	let dsymView = NSView(frame: NSZeroRect)
	let dsymLabel = NSTextField(frame: NSZeroRect)
	let removeDsymButton = NSButton(frame: NSZeroRect)
	
	override func viewDidMoveToSuperview() {
		self.font = NSFont(name: "Menlo", size: 11)
		
		self.registerForDraggedTypes([NSFilenamesPboardType])
		
		//setup dsym view
		dsymView.removeFromSuperview()
		dsymView.frame = NSRect(x: 0, y: 0, width: frame.size.width, height: 30)
		dsymView.autoresizingMask = [.ViewWidthSizable, .ViewMaxYMargin]
		dsymView.wantsLayer = true
		dsymView.layer?.backgroundColor = NSColor.windowBackgroundColor().CGColor
		superview!.superview!.superview!.addSubview(dsymView)
		
		dsymLabel.removeFromSuperview()
		dsymLabel.frame = NSRect(x: 5, y: 5, width: frame.size.width - 30, height: 20)
		dsymLabel.bordered = false
		dsymLabel.editable = false
		dsymLabel.backgroundColor = NSColor.clearColor()
		dsymLabel.autoresizingMask = [.ViewWidthSizable]
		dsymView.addSubview(dsymLabel)
		
		removeDsymButton.removeFromSuperview()
		removeDsymButton.frame = NSRect(x: frame.size.width - 25, y: 5, width: 20, height: 20)
		removeDsymButton.autoresizingMask = [.ViewMinXMargin]
		removeDsymButton.setButtonType(.MomentaryPushInButton)
		removeDsymButton.bordered = false
		removeDsymButton.image = NSImage(named: NSImageNameStopProgressFreestandingTemplate)
		removeDsymButton.target = self
		removeDsymButton.action = "removeDsym:"
		dsymView.addSubview(removeDsymButton)
		
		dsymView.hidden = (self.dsymURL == nil)
	}
	
	override func paste(sender: AnyObject?) {
		let symbolicator = Symbolicator()
		if let dsymURL = self.dsymURL
		{
			symbolicator.userDsym = dsymURL.path
		}
		
		let pasteboard = NSPasteboard.generalPasteboard()
		
		let objects = pasteboard.readObjectsForClasses([NSString.self], options: nil)
		if objects!.count > 0
		{
			let paste = objects![0] as! String
			
			self.window?.title = "👀 Symbolicating…"
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
				
				let result = symbolicator.processSampleReport(paste)
				
				var string = ""
				
				if (result.message != nil)
				{
					string = result.message!
				}
				
				if ((result.message != nil) && (result.result != nil))
				{
					string += "\n➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖\n"
				}
				
				if (result.result != nil)
				{
					string += result.result!
				}

				dispatch_async(dispatch_get_main_queue()) {
						self.window?.title = "Cymbals"
						self.string = string
					
					if (result.result != nil)
					{
						if let hihat = NSSound(named: "HiHat.aif")
						{
							hihat.play()
						}
					}
				}
			}
		}
		else
		{
			self.window?.title = "👎 Cymbals"
			self.string = "Could not load content of pasteboard 😕"
		}
	}
	
	override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation
	{
		let pasteboard = sender.draggingPasteboard()
		
		if pasteboard.types!.contains(NSFilenamesPboardType)
		{
			let filenames = pasteboard.propertyListForType(NSFilenamesPboardType) as? NSArray
			
			for filename in filenames!
			{
				let url = NSURL(fileURLWithPath: filename as! String)
				
				if url.path == "dsym"
				{
					return .Link
				}
			}
		}
		
		return super.draggingEntered(sender)
	}

	override func performDragOperation(sender: NSDraggingInfo) -> Bool {
		let pasteboard = sender.draggingPasteboard()
		
		if pasteboard.types!.contains(NSFilenamesPboardType)
		{
			let filenames = pasteboard.propertyListForType(NSFilenamesPboardType) as? NSArray
			
			for filename in filenames!
			{
				let url = NSURL(fileURLWithPath: filename as! String)
				
				if url.pathExtension?.lowercaseString == "dsym"
				{
					self.dsymURL = url
					
					return true
				}
			}
		}
		
		return super.performDragOperation(sender)
	}
	
	func removeDsym(sender: AnyObject) {
		dsymURL = nil
	}
}
