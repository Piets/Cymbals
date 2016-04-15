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
	
	/**
	Process a sample report or stacktrace
	
	- Parameter report: The complete report to process
	
	- Returns: The `result` contains the symbolicated report if symbolication succeeded, `message` contains information if symbolication did not succeed or debug information even if symbolication succeeded
	*/
	internal func processSampleReport(report: String) -> (result:String?, message:String?)
	{
		var message:String? = nil
		var result = ""
		
		//split the report into lines
		let lines = report.characters.split { $0 == "\n" || $0 == "\r\n" }.map(String.init)
		
//		if (lines.count == 1)
//		{
//			//try to insert some newlines, don't know if it's a good idea
//			//wait, i definetly know it's a bad idea 😇
//			let lineExpression = try! NSRegularExpression(pattern: "\\+\\s[0-9]+\\s?", options: [])
//			let expanedLine = lineExpression.stringByReplacingMatchesInString(report, options: [], range: NSRange(location: 0, length: report.utf16.count), withTemplate: "$0\n")
//			
//			lines = expanedLine.characters.split { $0 == "\n" || $0 == "\r\n" }.map(String.init)
//		}
		
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
				
				let hangLine = symbolicateHangtrace(trimmedLine)
				if let hangMessage = hangLine.message {
					message = appendMessage(hangMessage, originalString: message)
				}
				
				if hangLine.symbolicated {
					result += "\n\(hangLine.result)"
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
	
	/**
	Try to symbolicate a line of a sample report
	
	- Parameter line: A line of a stacktrace to try symbolication on
	- Parameter report: The complete report the line is from. This is needed in order to parse the dsym UUIDs at the bottom
	
	- Returns: The `result` contains the symbolicated line (or the original if symbolication was unsuccessful), `symbolicated` is true if atos did output a symbol name, `message` additionally contains some information which may be presented to the user
	*/
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
	
	/**
	Try to symbolicate a line of a stacktrace
	
	- Parameter line: A line of a stacktrace to try symbolication on
	
	- Returns: The `result` contains the symbolicated line (or the original if symbolication was unsuccessful), `symbolicated` is true if atos did output a symbol name, `message` additionally contains some information which may be presented to the user
	*/
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
	
	/**
	Try to symbolicate a line of a hang
	
	- Parameter line: A line of a hang to try symbolication on
	
	- Returns: The `result` contains the symbolicated line (or the original if symbolication was unsuccessful), `symbolicated` is true if atos did output a symbol name, `message` additionally contains some information which may be presented to the user
	*/
	private func symbolicateHangtrace(line: String) -> (result: String, symbolicated: Bool, message: String?)
	{
		var message: String? = nil
		var resultLine = line
		var symbolicated = false
		
		let hangExpression = try! NSRegularExpression(pattern: "\\?\\?\\?.*\\((.*)\\s\\+\\s([0-9]+).*(0[xX][0-9a-fA-F]+)\\]", options: [.AnchorsMatchLines])
		let hangMatches = hangExpression.matchesInString(line, options: [], range: NSRange(location: 0, length: line.utf16.count))
		
		if hangMatches.count > 0
		{
			let match = hangMatches[0] as NSTextCheckingResult
			
			let binary = (line as NSString).substringWithRange(match.rangeAtIndex(1))
			let stackAddress = (line as NSString).substringWithRange(match.rangeAtIndex(3))
			let decimalAddress = Int((line as NSString).substringWithRange(match.rangeAtIndex(2)))!
			
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
					resultLine = (line as NSString).stringByReplacingCharactersInRange(match.rangeAtIndex(0), withString: trimmedString)
					symbolicated = true
				}
			}
		}
		
		return (resultLine, symbolicated, message)
	}
	
	/**
	Append a message to the end of a string
	
	- Parameter input: The message to append
	- Parameter originalString: The string where the message should be appended. Will be generated if nil
	
	- Returns: The `originalString` + the `input` string concatenated
	*/
	private func appendMessage(input: String, originalString: String?) -> String
	{
		if let origString = originalString
		{
			return origString + "\n\(input)"
		}
		
		return input
	}
	
	/**
	Runs a shell command and outputs the result as a string
	
	- Parameter args: A variable list of arguments beginning with the launchPath (e. g. `"ls", "-l"`)
	
	- Returns: The complete result of `stdout` of the shell command
	*/
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
	
	/**
	Remove whitespaces at the end of a string.
	
	Used in order to maintain intendations in the front of lines
	
	- Parameter str: The string to trim
	
	- Returns: The trimmed string with removed whitespaces from the end of the string
	*/
	private func removingSpacesAtTheEndOfAString(str: String) -> String {
		var i: Int = str.characters.count - 1, j: Int = i
		
		while(i >= 0 && str[str.startIndex.advancedBy(i)] == " ") {
			--i
		}
		
		return str.substringWithRange(Range<String.Index>(start: str.startIndex, end: str.endIndex.advancedBy(-(j - i))))
	}
	
	/**
	Returns the path to a dsym file to use with atos
	
	If the user specified a dsym to use this method simply returns the path to this dsym
	
	- Parameter binary: (If applicable) the binary which contains the symbol (for lookup)
	- Parameter report: The report in which to search for the dsym UUID
	
	- Returns: A touple containing a `result` path and a `message` if needed
	*/
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
