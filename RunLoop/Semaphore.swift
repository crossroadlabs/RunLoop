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
    
    //TODO: optimise with atomics for value. Will allow to run not-blocked sema faster
    private func waitWithConditionalDate(until:NSDate?) -> Bool {
        underlyingSemaphore.lock()
        defer {
            underlyingSemaphore.unlock()
        }
        value -= 1
        
        var signaled:Bool = true
        if value < 0 {
            signaled = underlyingSemaphore.waitWithConditionalEnd(until)
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

class HashableAnyContainer<T> : AnyContainer<T>, Hashable {
    let guid = NSUUID()
    let hashValue: Int
    
    override init(_ item: T) {
        hashValue = self.guid.hashValue
        super.init(item)
    }
}

func ==<T>(lhs:HashableAnyContainer<T>, rhs:HashableAnyContainer<T>) -> Bool {
    return lhs.guid == rhs.guid
}

private enum Wakeable {
    case Loop(loop:RunnableRunLoopType)
    case Sema(sema:SemaphoreType)
}

private extension Wakeable {
    init(loop:RunLoopType) {
        if let loop = loop as? RunnableRunLoopType {
            self = .Loop(loop: loop)
        } else {
            self = .Sema(sema: loop.semaphore())
        }
    }
    
    func waitWithConditionalDate(until:NSDate?) -> Bool {
        switch self {
        case .Loop(let loop):
            if let until = until {
                return loop.run(Timeout(until: until))
            } else {
                return loop.run()
            }
        case .Sema(let sema):
            if let until = until {
                return sema.wait(until)
            } else {
                return sema.wait()
            }
        }
    }
    
    func wake(task:SafeTask) {
        switch self {
        case .Loop(let loop):
            loop.execute {
                task()
                loop.stop()
            }
        case .Sema(let sema):
            task()
            sema.signal()
        }
    }
}

public class RunLoopSemaphore : SemaphoreType {
    private var signals:[HashableAnyContainer<SafeTask>]
    private let lock:NSLock
    private var value:Int
    
    public required convenience init() {
        self.init(value: 0)
    }
    
    public required init(value: Int) {
        self.value = value
        signals = Array()
        lock = NSLock()
    }
    
    //TODO: optimise with atomics for value. Will allow to run non-blocked sema faster
    private func waitWithConditionalDate(until:NSDate?) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        value -= 1
        
        if value >= 0 {
            return true
        }
        
        var signaled = false
        var timedout = false
        
        let loop = RunLoop.current
        let wakeable:Wakeable = Wakeable(loop: loop)
        
        let signal = HashableAnyContainer {
            wakeable.wake {
                signaled = true
            }
        }
        
        signals.append(signal)
        
        if value < 0 {
            lock.unlock()
            defer {
                lock.lock()
            }
            while !signaled && !timedout {
                timedout = wakeable.waitWithConditionalDate(until)
            }
        }
        
        let index = signals.indexOf { element in
            element == signal
        }
        if let index = index {
            signals.removeAtIndex(index)
        }
        
        return signaled
    }
    
    public func wait() -> Bool {
        return waitWithConditionalDate(nil)
    }
    
    public func wait(until:NSDate) -> Bool {
        return waitWithConditionalDate(until)
    }
    
    public func signal() -> Int {
        lock.lock()
        value += 1
        let signal:AnyContainer<SafeTask>? = signals.isEmpty ? nil : signals.removeFirst()
        lock.unlock()
        signal?.content()
        return 1
    }
}