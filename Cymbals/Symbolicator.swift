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
		var result = ""
		
		//split the report into lines
		var lines = report.characters.split { $0 == "\n" || $0 == "\r\n" }.map(String.init)
		
		if (lines.count == 1)
		{
			//try to insert some newlines, don't know if it's a good idea
			//wait, i definetly know it's a bad idea 😇
			let lineExpression = try! NSRegularExpression(pattern: "\\+\\s[0-9]+\\s?", options: [])
			let expanedLine = lineExpression.stringByReplacingMatchesInString(report, options: [], range: NSRange(location: 0, length: report.utf16.count), withTemplate: "$0\n")
			
			lines = expanedLine.characters.split { $0 == "\n" || $0 == "\r\n" }.map(String.init)
		}
		
		var oneLineSymbolicated = false
		
		for line in lines
		{
			let trimmedLine = removingSpacesAtTheEndOfAString(line)
			
			let sampleLine = symbolicateSampleReport(trimmedLine, report: report)
			if let sampleMessage = sampleLine.message {
				message = appendMessage(sampleMessage, originalString: message)
			}
			
			if sampleLine.symbolicated {
				result += "\n\(sampleLine.result)"
				oneLineSymbolicated = true
				continue
			}
			
			if userDsym != nil
			{
				let stackLine = symbolicateStacktrace(trimmedLine)
				if let stackMessage = stackLine.message {
					message = appendMessage(stackMessage, originalString: message)
				}
				
				if stackLine.symbolicated {
					result += "\n\(stackLine.result)"
					oneLineSymbolicated = true
					continue
				}
			}
			
			result += "\n\(line)"
		}
		
		if (!oneLineSymbolicated)
		{
			message = appendMessage("couldn't find any addresses that need symbolication 😞", originalString: message)
		}
		
		return (result, message)
	}
	
	private func symbolicateSampleReport(line: String, report: String) -> (result: String, symbolicated: Bool, message: String?)
	{
		var message: String? = nil
		var resultLine = line
		var symbolicated = false
		
		let sampleReportExpression = try! NSRegularExpression(pattern: "\\?\\?\\?\\s*\\(in\\s(.*)\\)\\s*load\\saddress\\s(.*)\\s\\+.*\\[(.*)\\]", options: [])
		let sampleMatches = sampleReportExpression.matchesInString(line, options: [], range: NSRange(location: 0, length: line.utf16.count))
		
		if (sampleMatches.count > 0)
		{
			let match = sampleMatches[0] as NSTextCheckingResult
		
			let binary = (line as NSString).substringWithRange(match.rangeAtIndex(1))
			let loadAddress = (line as NSString).substringWithRange(match.rangeAtIndex(2))
			let stackAddress = (line as NSString).substringWithRange(match.rangeAtIndex(3))
		
			let dsymResult = dsymForBinary(binary, report: report)
		
			if let dsymPath = dsymResult.result
			{
				//We got everything atos needs 😃
				let symbol = shell("atos", "-o", dsymPath, "-l", loadAddress, stackAddress)
				
				let trimmedString = symbol.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
				
				if (trimmedString == "")
				{
					message = appendMessage("Output from atos was an empty string:\natos -o \"\(dsymPath)\" -l \(loadAddress) \(stackAddress)", originalString: message)
				}
				else
				{
					resultLine = (line as NSString).stringByReplacingCharactersInRange(match.rangeAtIndex(0), withString: trimmedString)
					symbolicated = true
				}
			}
			else
			{
				if let dsymMessage = dsymResult.message
				{
					message = appendMessage(dsymMessage, originalString: message)
				}
			}
		}
		
		return (resultLine, symbolicated, message)
	}
	
	private func symbolicateStacktrace(line: String) -> (result: String, symbolicated: Bool, message: String?)
	{
		var message: String? = nil
		var resultLine = line
		var symbolicated = false
		
		let stacktraceExpression = try! NSRegularExpression(pattern: "[0-9]+\\s+(.*)\\s+(0[xX][0-9a-fA-F]+)\\s(\\1).*\\s([0-9]+)$", options: [.AnchorsMatchLines])
		let stacktraceMatches = stacktraceExpression.matchesInString(line, options: [], range: NSRange(location: 0, length: line.utf16.count))

		if stacktraceMatches.count > 0
		{
			let match = stacktraceMatches[0] as NSTextCheckingResult
			
			let binary = (line as NSString).substringWithRange(match.rangeAtIndex(1))
			let stackAddress = (line as NSString).substringWithRange(match.rangeAtIndex(2))
			let decimalAddress = Int((line as NSString).substringWithRange(match.rangeAtIndex(4)))!
			
			let cleanStackAddress = stackAddress.stringByReplacingOccurrencesOfString("0x", withString: "")
			let intStackAddress = Int(cleanStackAddress, radix: 16)!
		
			let loadAddress = "0x" + String((intStackAddress - decimalAddress), radix: 16)
			
			//We can put in an empty string for the report as we really only have one coice for stacktraces: the user providing it's own dSYM
			let dsymResult = dsymForBinary(binary, report: "")
		
			if let dsymPath = dsymResult.result
			{
				//We got everything atos needs 😃
				let symbol = shell("atos", "-o", dsymPath, "-l", loadAddress, stackAddress)
				let trimmedString = symbol.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			
				if (trimmedString == "")
				{
					message = appendMessage("Output from atos was an empty string:\natos -o \"\(dsymPath)\" -l \(loadAddress) \(stackAddress)", originalString: message)
				}
				else
				{
					resultLine = (line as NSString).stringByReplacingCharactersInRange(match.rangeAtIndex(3), withString: trimmedString)
					symbolicated = true
				}
			}
		}
		
		return (resultLine, symbolicated, message)
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
	
	private func removingSpacesAtTheEndOfAString(str: String) -> String {
		var i: Int = str.characters.count - 1, j: Int = i
		
		while(i >= 0 && str[str.startIndex.advancedBy(i)] == " ") {
			--i
		}
		
		return str.substringWithRange(Range<String.Index>(start: str.startIndex, end: str.endIndex.advancedBy(-(j - i))))
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
