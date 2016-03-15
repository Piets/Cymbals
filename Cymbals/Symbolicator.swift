//
//  Symbolicator.swift
//  Cymbals
//
//  Created by Peter Kraml on 13.03.16.
//  Copyright © 2016 MacPiets Apps. All rights reserved.
//

import Cocoa

class Symbolicator: NSObject
{
	
	var dsymsCache = [String: String]()
	
	var userDsym: String?
	
	internal func processSampleReport(report: String) -> (result:String?, message:String?)
	{
		var message:String? = nil
		
		//I know, I know, regexes are bad, but boy are they usefull 🙈
		let sampleReportExpression = try! NSRegularExpression(pattern: "\\?\\?\\?\\s*\\(in\\s(.*)\\)\\s*load\\saddress\\s(.*)\\s\\+.*\\[(.*)\\]", options: [])
		let stacktraceExpression = try! NSRegularExpression(pattern: "[0-9]+\\s+(.*)\\s+(0[xX][0-9a-fA-F]+)\\s(\\1).*\\s([0-9]+)$", options: [.AnchorsMatchLines])
		
		var sampleMatches = sampleReportExpression.matchesInString(report, options: [], range: NSRange(location: 0, length: report.utf16.count))
		let sampleMatchesCount = sampleMatches.count
		
		var stacktraceMatches = stacktraceExpression.matchesInString(report, options: [], range: NSRange(location: 0, length: report.utf16.count))
		let stacktraceMatchesCount = stacktraceMatches.count
		
		if sampleMatchesCount > 0
		{
			var itemsToSkip = 0
			var replacedReport = report
			
			for var index = 0; index < sampleMatchesCount; index++ {
				let match = sampleMatches[itemsToSkip] as NSTextCheckingResult
				
				let binary = (replacedReport as NSString).substringWithRange(match.rangeAtIndex(1))
				let loadAddress = (replacedReport as NSString).substringWithRange(match.rangeAtIndex(2))
				let stackAddress = (replacedReport as NSString).substringWithRange(match.rangeAtIndex(3))
				
				let dsymResult = dsymForBinary(binary, report: replacedReport)
				
				if let dsymPath = dsymResult.result
				{
					//We got everything atos needs 😃
					let symbol = shell("atos", "-o", dsymPath, "-l", loadAddress, stackAddress)
					
					let trimmedString = symbol.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
					
					if (trimmedString == "")
					{
						message = appendMessage("Output from atos was an empty string:\natos -o \"\(dsymPath)\" -l \(loadAddress) \(stackAddress)", originalString: message)
						itemsToSkip++
					}
					else
					{
						replacedReport = (replacedReport as NSString).stringByReplacingCharactersInRange(match.rangeAtIndex(0), withString: trimmedString)
					}
				}
				else
				{
					if let dsymMessage = dsymResult.message
					{
						message = appendMessage(dsymMessage, originalString: message)
					}
					itemsToSkip++
				}
				
				sampleMatches = sampleReportExpression.matchesInString(replacedReport, options: [], range: NSRange(location: 0, length: replacedReport.utf16.count))
			}
			
			return (replacedReport, message)
		}
		else if stacktraceMatchesCount > 0 && userDsym != nil
		{
			var itemsToSkip = 0
			var replacedReport = report
			
			for var index = 0; index < stacktraceMatchesCount; index++ {
				let match = stacktraceMatches[itemsToSkip] as NSTextCheckingResult
				
				let binary = (replacedReport as NSString).substringWithRange(match.rangeAtIndex(1))
				let stackAddress = (replacedReport as NSString).substringWithRange(match.rangeAtIndex(2))
				let decimalAddress = Int((replacedReport as NSString).substringWithRange(match.rangeAtIndex(4)))!
				
				let cleanStackAddress = stackAddress.stringByReplacingOccurrencesOfString("0x", withString: "")
				let intStackAddress = Int(cleanStackAddress, radix: 16)!
				
				let loadAddress = "0x" + String((intStackAddress - decimalAddress), radix: 16)
				
				let dsymResult = dsymForBinary(binary, report: replacedReport)
				
				if let dsymPath = dsymResult.result
				{
					//We got everything atos needs 😃
					let symbol = shell("atos", "-o", dsymPath, "-l", loadAddress, stackAddress)
					let trimmedString = symbol.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
					
					if (trimmedString == "")
					{
						message = appendMessage("Output from atos was an empty string:\natos -o \"\(dsymPath)\" -l \(loadAddress) \(stackAddress)", originalString: message)
						itemsToSkip++
					}
					else
					{
						replacedReport = (replacedReport as NSString).stringByReplacingCharactersInRange(match.rangeAtIndex(3), withString: trimmedString)
					}
				}
				
				stacktraceMatches = stacktraceExpression.matchesInString(replacedReport, options: [], range: NSRange(location: 0, length: replacedReport.utf16.count))
			}
			
			return (replacedReport, message)
		}
		else
		{
			message = appendMessage("couldn't find any addresses that need symbolication 😞", originalString: message)
		}
		
		return (nil, message)
	}
	
	private func appendMessage(input: String, originalString: String?) -> String
	{
		if let origString = originalString
		{
			return origString + "\n\(input)"
		}
		
		return input
	}
	
	private func shell(args: String...) -> String
	{
		let task = NSTask()
		task.launchPath = "/usr/bin/env"
		task.arguments = args
		
		let pipe = NSPipe()
		task.standardOutput = pipe
		task.launch()
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		let output = String(data: data, encoding: NSUTF8StringEncoding)!
		
		return output
	}
	
	private func dsymForBinary(binary: String, report: String) -> (result:String?, message:String?)
	{
		if let userDsym = self.userDsym
		{
			let deeperPath = "\(userDsym)/Contents/Resources/DWARF/"
			
			let fileManager = NSFileManager.defaultManager()
			
			let files = fileManager.enumeratorAtPath(deeperPath)
			if let file = files?.allObjects.first {
				return("\(userDsym)/Contents/Resources/DWARF/\(file)", nil)
			}
			
			return(nil, "😢 no dsym were found at your path")
		}
		
		var cachedValue = dsymsCache[binary]
		
		if (cachedValue != nil)
		{
			if (cachedValue == "")
			{
				cachedValue = nil
			}
			
			return (cachedValue, nil)
		}
		
		var message: String? = nil
		
		let uuidExpression = try! NSRegularExpression(pattern: "<(.*)>.*(\(binary))", options: [])
		let matches = uuidExpression.matchesInString(report, options: [], range: NSRange(location: 0, length: report.utf16.count))
		
		if matches.count > 0
		{
			let match = matches[0] as NSTextCheckingResult
			
			let dsymUUID = (report as NSString).substringWithRange(match.rangeAtIndex(1))
			
			let dsyms = shell("mdfind", "com_apple_xcode_dsym_uuids == \(dsymUUID)")
			
			let dsymExpression = try! NSRegularExpression(pattern: "(.*\\.dSYM)", options: [])
			let dsymMatches = dsymExpression.matchesInString(dsyms, options: [], range: NSRange(location: 0, length: dsyms.utf16.count))
			
			if dsymMatches.count > 0
			{
				let match = dsymMatches[0] as NSTextCheckingResult
				
				var dsymPath = (dsyms as NSString).substringWithRange(match.rangeAtIndex(1))
				
				dsymPath = dsymPath + "/Contents/Resources/DWARF/\(binary)"
				
				dsymsCache[binary] = dsymPath
				return (dsymPath, nil)
			}
			else
			{
				message = "😳 uhoh, couldn't find any dsym files for the UUID <\(dsymUUID)> (\(binary))"
			}
		}
		else
		{
			message = "🤔 uhm, couldn't find the UUID for the binary \(binary)"
		}
		
		dsymsCache[binary] = ""
		return (nil, message)
	}
	
}
