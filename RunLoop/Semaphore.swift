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

public protocol SemaphoreProtocol {
    init()
    init(value: Int)
    
    func wait() -> Bool
    func wait(until:Date) -> Bool
    func wait(timeout: Timeout) -> Bool
    
    func signal() -> Int
}

public extension SemaphoreProtocol {
    public static var `default`:Int {
        get {
            return 0
        }
    }
}

public extension SemaphoreProtocol {
    /// Performs the wait operation on this semaphore until the timeout
    /// Returns true if the semaphore was signalled before the timeout occurred
    /// or false if the timeout occurred.
    public func wait(timeout: Timeout) -> Bool {
        switch timeout {
        case .Infinity:
            return wait()
        default:
            return wait(until: timeout.timeSinceNow())
        }
    }
}

private extension NSCondition {
    func waitWithConditionalEnd(date:Date?) -> Bool {
        guard let date = date else {
            self.wait()
            return true
        }
        return self.wait(until: date)
    }
}

/// A wrapper around NSCondition
public class BlockingSemaphore : SemaphoreProtocol {
    
    /// The underlying NSCondition
    private(set) public var underlying: NSCondition
    private(set) public var value: Int
    
    /// Creates a new semaphore with the given initial value
    /// See NSCondition and https://developer.apple.com/library/prerelease/mac/documentation/Cocoa/Conceptual/Multithreading/ThreadSafety/ThreadSafety.html#//apple_ref/doc/uid/10000057i-CH8-SW13
    public required init(value: Int) {
        self.underlying = NSCondition()
        self.value = value
    }
    
    /// Creates a new semaphore with initial value 0
    /// This kind of semaphores is useful to protect a critical section
    public convenience required init() {
        self.init(value: BlockingSemaphore.default)
    }
    
    //TODO: optimise with atomics for value. Will allow to run not-blocked sema faster
    private func waitWithConditionalDate(until:Date?) -> Bool {
        underlying.lock()
        defer {
            underlying.unlock()
        }
        value -= 1
        
        var signaled:Bool = true
        if value < 0 {
            signaled = underlying.waitWithConditionalEnd(date: until)
        }
        
        return signaled
    }
    
    public func wait() -> Bool {
        return waitWithConditionalDate(until: nil)
    }
    
    /// returns true on success (false if timeout expired)
    /// if nil is passed - waits forever
    public func wait(until:Date) -> Bool {
        return waitWithConditionalDate(until: until)
    }
    
    /// Performs the signal operation on this semaphore
    public func signal() -> Int {
        underlying.lock()
        defer {
            underlying.unlock()
        }
        value += 1
        underlying.signal()
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
    case Loop(loop:RunnableRunLoopProtocol)
    case LoopedSema(loop:RunLoopProtocol, sema:SemaphoreProtocol)
    case Sema(sema:SemaphoreProtocol, leftovers:Array<SafeTask>)
}

private extension Wakeable {
    init(loop:RunLoopProtocol?) {
        guard let loop = loop else {
            self = .Sema(sema: RunLoop.semaphore(loop: nil), leftovers:[])
            return
        }
        
        if let loop = loop as? RunnableRunLoopProtocol {
            self = .Loop(loop: loop)
        } else {
            self = .LoopedSema(loop:loop, sema: type(of: loop).semaphore(loop: loop))
        }
    }
    
    private static func wait(sema:SemaphoreProtocol, until:Date?) -> Bool {
        if let until = until {
            return sema.wait(until: until)
        } else {
            return sema.wait()
        }
    }
    
    func waitWithConditionalDate(until:Date?) -> Bool {
        switch self {
        case .Loop(let loop):
            if let until = until {
                return loop.run(timeout: Timeout(until: until))
            } else {
                return loop.run()
            }
            //SWIFT BUG: crash
        case .Sema(let sema, _)/*, .LoopedSema(_, let sema)*/:
            return Wakeable.wait(sema: sema, until: until)
        case .LoopedSema(_, let sema):
            return Wakeable.wait(sema: sema, until: until)
        }
    }
    
    func wake(task:SafeTask) {
        switch self {
        case .Loop(let loop):
            loop.execute {
                task()
                loop.stop()
            }
        case .LoopedSema(let loop, let sema):
            loop.execute {
                task()
                let _ = sema.signal()
            }
        case .Sema(let sema, var leftovers):
            leftovers.append(task)
            let _ = sema.signal()
        }
    }
    
    func afterwake() {
        switch self {
        case .Sema(_, var leftovers):
            while !leftovers.isEmpty {
                leftovers.removeFirst()()
            }
        default:
            break
        }
    }
}

public class RunLoopSemaphore : SemaphoreProtocol {
    private var signals:[SafeTask]
    private let lock:NSLock
    private var value:Int
    private var signaled:ThreadLocal<Bool>
    
    public required convenience init() {
        self.init(value: 0)
    }
    
    public required init(value: Int) {
        self.value = value
        signals = Array()
        lock = NSLock()
        signaled = try! ThreadLocal()
    }
    
    //TODO: optimise with atomics for value. Will allow to run non-blocked sema faster
    private func waitWithConditionalDate(until:Date?) -> Bool {
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
        
        let signal = {
            wakeable.wake {
                self.signaled.value = true
            }
        }
        
        signals.append(signal)
        
        if value < 0 {
            lock.unlock()
            //defer {
            //    lock.lock()
            //}
            while !signaled && !timedout {
                timedout = wakeable.waitWithConditionalDate(until: until)
                wakeable.afterwake()
                signaled = self.signaled.value ?? false
            }
            self.signaled.value = false
            lock.lock()
        }
        
        return signaled
    }
    
    public func wait() -> Bool {
        return waitWithConditionalDate(until: nil)
    }
    
    public func wait(until:Date) -> Bool {
        return waitWithConditionalDate(until: until)
    }
    
    public func signal() -> Int {
        lock.lock()
        value += 1
        let signal:SafeTask? = signals.isEmpty ? nil : signals.removeLast()
        lock.unlock()
        signal?()
        return 1
    }
}
