//
//  SymbolTextView.swift
//  Cymbals
//
//  Created by Peter Kraml on 13.03.16.
//  Copyright © 2016 MacPiets Apps. All rights reserved.
//

import Cocoa

class SymbolTextView: NSTextView {
	
	override func viewDidMoveToSuperview() {
		self.font = NSFont(name: "Menlo", size: 11)
	}
	
	override func paste(sender: AnyObject?) {
		let symbolicator = Symbolicator()
		
		let pasteboard = NSPasteboard.generalPasteboard()
		if let paste = pasteboard.stringForType(NSPasteboardTypeString)
		{
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
				}
			}
		}
		else
		{
			self.window?.title = "👎 Cymbals"
			self.string = "Could not load content of pasteboard 😕"
		}
	}
}
