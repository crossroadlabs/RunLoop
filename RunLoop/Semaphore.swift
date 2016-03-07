//===--- Semaphore.swift ----------------------------------------------===//
//Copyright (c) 2016 Daniel Leping (dileping)
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation
import Boilerplate

public protocol SemaphoreType {
    init()
    init(value: Int)
    
    func wait() -> Bool
    func wait(until:NSDate) -> Bool
    func wait(timeout: Timeout) -> Bool
    
    func signal() -> Int
}

public extension SemaphoreType {
    public static var defaultValue:Int {
        get {
            return 0
        }
    }
}

public extension SemaphoreType {
    /// Performs the wait operation on this semaphore until the timeout
    /// Returns true if the semaphore was signalled before the timeout occurred
    /// or false if the timeout occurred.
    public func wait(timeout: Timeout) -> Bool {
        switch timeout {
        case .Infinity:
            return wait()
        default:
            return wait(timeout.timeSinceNow())
        }
    }
}

private extension NSCondition {
    func waitWithConditionalEnd(date:NSDate?) -> Bool {
        guard let date = date else {
            self.wait()
            return true
        }
        return self.waitUntilDate(date)
    }
}

/// A wrapper around NSCondition
public class BlockingSemaphore : SemaphoreType {
    
    /// The underlying NSCondition
    private(set) public var underlyingSemaphore: NSCondition
    private(set) public var value: Int
    
    /// Creates a new semaphore with the given initial value
    /// See NSCondition and https://developer.apple.com/library/prerelease/mac/documentation/Cocoa/Conceptual/Multithreading/ThreadSafety/ThreadSafety.html#//apple_ref/doc/uid/10000057i-CH8-SW13
    public required init(value: Int) {
        self.underlyingSemaphore = NSCondition()
        self.value = value
    }
    
    /// Creates a new semaphore with initial value 0
    /// This kind of semaphores is useful to protect a critical section
    public convenience required init() {
        self.init(value: BlockingSemaphore.defaultValue)
    }
    
    private func waitWithConditionalDate(until:NSDate?) -> Bool {
        underlyingSemaphore.lock()
        defer {
            underlyingSemaphore.unlock()
        }
        
        var signaled:Bool = true
        while value <= 0 {
            signaled = underlyingSemaphore.waitWithConditionalEnd(until)
            if !signaled {
                break
            }
        }
        
        if signaled {
            value -= 1
        }
        
        return signaled
    }
    
    public func wait() -> Bool {
        return waitWithConditionalDate(nil)
    }
    
    /// returns true on success (false if timeout expired)
    /// if nil is passed - waits forever
    public func wait(until:NSDate) -> Bool {
        return waitWithConditionalDate(until)
    }
    
    /// Performs the signal operation on this semaphore
    public func signal() -> Int {
        underlyingSemaphore.lock()
        defer {
            underlyingSemaphore.unlock()
        }
        value += 1
        underlyingSemaphore.signal()
        return value
    }
}