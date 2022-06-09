//    Copyright (c) 2019, SeatGeek, Inc
//    All rights reserved.
//
//    Redistribution and use in source and binary forms, with or without
//    modification, are permitted provided that the following conditions are met:
//
//    * Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
//    * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//    DispatchQueue+Debounce.swift
//    Created by James Van-As on 21/09/18.
import Foundation

extension DispatchQueue {
	
	/**
	 - parameters:
		- target: Object used as the sentinel for de-duplication.
		- delay: The time window for de-duplication to occur
		- work: The work item to be invoked on the queue.
	 Performs work only once for the given target, given the time window. The last added work closure
	 is the work that will finally execute.
	 Note: This is currently only safe to call from the main thread.
	 Example usage:
	 ```
	 DispatchQueue.main.asyncDebounced(target: self, after: 1.0) { [weak self] in
		 self?.doTheWork()
	 }
	 ```
	 */
	public func asyncDebounce(target: AnyObject, after delay: TimeInterval, execute work: @escaping @convention(block) () -> Void) {
		let debounceIdentifier = DispatchQueue.debounceIdentifierFor(target)
		if let existingWorkItem = DispatchQueue.workItems.removeValue(forKey: debounceIdentifier) {
			existingWorkItem.cancel()
		}
		let workItem = DispatchWorkItem {
			DispatchQueue.workItems.removeValue(forKey: debounceIdentifier)
			
			for ptr in DispatchQueue.weakTargets.allObjects {
				if debounceIdentifier == DispatchQueue.debounceIdentifierFor(ptr as AnyObject) {
					work()
					break
				}
			}
		}
		
		DispatchQueue.workItems[debounceIdentifier] = workItem
		DispatchQueue.weakTargets.addPointer(Unmanaged.passUnretained(target).toOpaque())
		
		asyncAfter(deadline: .now() + delay, execute: workItem)
	}
	
	public func asyncThrottle(target: AnyObject, minimumDelay delay: TimeInterval, execute work: @escaping @convention(block) () -> Void) {
		let throttleIdentifier = DispatchQueue.throttleIdentifierFor(target)
		if let existingWorkItem = DispatchQueue.workItems.removeValue(forKey: throttleIdentifier) {
			existingWorkItem.cancel()
		}
		
		let workItem = DispatchWorkItem {
			DispatchQueue.workItems.removeValue(forKey: throttleIdentifier)
			
			for ptr in DispatchQueue.weakTargets.allObjects {
				if throttleIdentifier == DispatchQueue.throttleIdentifierFor(ptr as AnyObject) {
					work()
					break
				}
			}
		}
		
		DispatchQueue.workItems[throttleIdentifier] = workItem
		DispatchQueue.weakTargets.addPointer(Unmanaged.passUnretained(target).toOpaque())
		
		let lastExecutionTime = DispatchQueue.executeTime[throttleIdentifier] ?? 0
		let timeSinceLastExecution = Date().timeIntervalSinceReferenceDate - lastExecutionTime
		if timeSinceLastExecution > delay {
			DispatchQueue.executeTime[throttleIdentifier] = Date().timeIntervalSinceReferenceDate
			async(execute: workItem)
		}
	}
}

// MARK: - Static Properties for De-Duping
private extension DispatchQueue {
	
	static var workItems = [AnyHashable : DispatchWorkItem]()
	
	static var weakTargets = NSPointerArray.weakObjects()
	static var executeTime = [AnyHashable : TimeInterval]()
	
	static func debounceIdentifierFor(_ object: AnyObject) -> String {
		return "\(Unmanaged.passUnretained(object).toOpaque()).debounce."// + String(describing: object)
	}
	
	static func throttleIdentifierFor(_ object: AnyObject) -> String {
		return "\(Unmanaged.passUnretained(object).toOpaque()).throttle."// + String(describing: object)
	}

}
