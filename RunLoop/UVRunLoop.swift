//===--- UVRunLoop.swift ----------------------------------------------===//
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
import UV
import CUV

private struct UVRunLoopTask {
    let task: SafeTask
    let urgent:Bool
    let relay:Bool
    
    init(task: SafeTask, urgent:Bool, relay:Bool) {
        self.task = task
        self.urgent = urgent
        self.relay = relay
    }
}

private let _currentLoopSignature = try! ThreadLocal<NSUUID>()

public class UVRunLoop : RunnableRunLoopType, SettledType, RelayRunLoopType {
    typealias Semaphore = BlockingSemaphore
    
    //wrapping as containers to avoid copying
    private var _relayQueue:MutableAnyContainer<Array<UVRunLoopTask>>
    private var _personalQueue:MutableAnyContainer<Array<UVRunLoopTask>>
    private var _commonQueue:MutableAnyContainer<Array<UVRunLoopTask>>
    private var _stop:MutableAnyContainer<Bool>
    
    private let _loop:Loop
    private let _wake:Async
    private let _caller:Prepare
    private let _semaphore:SemaphoreType
    
    public var protected:Bool = false
    
    private let _loopSignature:NSUUID = NSUUID()
    
    private (set) public var isRunning:Bool = false
    public var isHome:Bool {
        get {
            guard let currentLoopSignature = _currentLoopSignature.value else {
                return false
            }
            return _loopSignature == currentLoopSignature
        }
    }
    
    private var signature:NSUUID = NSUUID()
    private func resign() {
        self.signature = NSUUID()
    }
    
    public var relay:RunLoopType? = nil {
        didSet {
            //I would love to add something to Optional, but it does not work. Stupid Swift
            guard let lhs = oldValue else {
                switch relay {
                case .None:
                    break
                default:
                    relayChanged()
                }
                return
            }
            
            guard let rhs = relay else {
                relayChanged()
                return
            }
            
            if !lhs.isEqualTo(rhs) {
                relayChanged()
            }
        }
    }
    
    private (set) public static var main:RunLoopType = UVRunLoop(loop: Loop.defaultLoop())
    
    private init(loop:Loop) {
        let relayQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let personalQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let commonQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let stop = MutableAnyContainer(false)
        
        self._relayQueue = relayQueue
        self._personalQueue = personalQueue
        self._commonQueue = commonQueue
        self._stop = stop
        
        let sema = BlockingSemaphore(value: 1)
        self._semaphore = sema
        
        //Yes, exactly. Fail in runtime if we can not create a loop
        self._loop = loop
        
        var requestRelay:SafeTask? = nil
        var callRelayed:Optional<(UVRunLoopTask)->Void> = nil
        var callTask:Optional<(UVRunLoopTask)->Void> = nil
        
        self._caller = try! Prepare(loop: _loop) { _ in
            var hadRelayed = false
            while !personalQueue.content.isEmpty {
                let task = personalQueue.content.removeFirst()
                
                if task.relay {
                    callRelayed?(task)
                    hadRelayed = true
                } else {
                    callTask?(task)
                }
                
                if stop.content {
                    break
                }
            }
            
            if hadRelayed {
                requestRelay?()
            }
        }
        
        //same with async
        self._wake = try! Async(loop: _loop) { _ in
            sema.wait()
            defer {
                sema.signal()
            }
            
            let urgents = commonQueue.content.filter { task in
                task.urgent
            }
            let commons = commonQueue.content.filter { task in
                !task.urgent
            }
            commonQueue.content.removeAll()
            
            personalQueue.content.insertContentsOf(urgents, at: commonQueue.content.startIndex)
            personalQueue.content.appendContentsOf(commons)
        }
        
        requestRelay = self.requestRelay
        callRelayed = self.callRelayed
        callTask = self.callTask
    }
    
    public convenience required init() {
        self.init(loop: try! Loop())
    }
    
    deinit {
        _wake.close()
        _caller.close()
    }
    
    public func semaphore() -> SemaphoreType {
        return relay.map{$0.semaphore()}.getOrElse(RunLoopSemaphore())
    }
    
    public func semaphore(value:Int) -> SemaphoreType {
        return relay.map{$0.semaphore(value)}.getOrElse(RunLoopSemaphore(value: value))
    }
    
    private func relayChanged() {
        self.urgentNoRelay {
            self.resign()
            
            if self.relay == nil {
                self._personalQueue.content.appendContentsOf(self._relayQueue.content)
                self._relayQueue.content.removeAll()
            } else {
                self.requestRelay()
            }
        }
    }
    
    private func callTask(task:UVRunLoopTask) {
        if isHome {
            task.task()
        } else {
            self.execute(task)
        }
    }
    
    private func callRelayed(task:UVRunLoopTask) -> Void {
        if self.relay != nil {
            _relayQueue.content.append(task)
        } else {
            callTask(task)
        }
    }
    
    private func requestRelay() {
        if let relay = self.relay {
            let signature = self.signature
            relay.execute {
                if signature != self.signature {
                    return
                }
                let sema = relay.semaphore()
                self.executeNoRelay {
                    defer {
                        sema.signal()
                    }
                    for task in self._relayQueue.content {
                        relay.execute(task.task)
                    }
                    self._relayQueue.content.removeAll()
                }
                sema.wait()
            }
        }
    }
    
    private func execute(task:UVRunLoopTask) {
        if isHome {
            //here we are safe to be lock-less
            if task.urgent {
                _personalQueue.content.insert(task, atIndex: _personalQueue.content.startIndex)
            } else {
                _personalQueue.content.append(task)
            }
        } else {
            _semaphore.wait()
            defer {
                _semaphore.signal()
                _wake.send()
            }
            _commonQueue.content.append(task)
        }
    }
    
    public func urgent(relay:Bool, task:SafeTask) {
        let task = UVRunLoopTask(task: task, urgent: true, relay: relay)
        self.execute(task)
    }
    
    public func execute(relay:Bool, task: SafeTask) {
        let task = UVRunLoopTask(task: task, urgent: false, relay: relay)
        self.execute(task)
    }
    
    public func execute(relay:Bool, delay:Timeout, task: SafeTask) {
        let endTime = delay.timeSinceNow()
        executeNoRelay {
            let timeout = Timeout(until: endTime)
            switch timeout {
            case .Immediate:
                self.urgent(relay, task: task)
            default:
                //yes, this is a runtime error
                let timer = try! Timer(loop: self._loop) { timer in
                    defer {
                        timer.close()
                    }
                    self.urgent(relay, task: task)
                }
                //yes, this is a runtime error
                try! timer.start(timeout)
            }
        }
    }
    
    public var native:Any {
        get {
            return _loop
        }
    }
    
    /// returns true if timed out, false otherwise
    public func run(until:NSDate, once:Bool) -> Bool {
        var finalizer:SafeTask? = {
            //yes, fail if so. It's runtime error
            try! self._caller.stop()
        }
        defer {
            finalizer?()
        }
        
        if !isHome && isRunning {
            let sema = BlockingSemaphore()
            let relay = self.relay
            let protected = self.protected
            
            finalizer = {
                self.relay = relay
                self.protected = protected
                sema.signal()
            }
            
            self.relay = nil
            self.protected = false
            
            let sema2 = BlockingSemaphore()
            self.urgentNoRelay {
                sema2.signal()
                sema.wait()
            }
            print("before wait")
            sema2.wait()
            print("passed")
        }
        

        let currentLoopSignature = _currentLoopSignature.value
        defer {
            _currentLoopSignature.value = currentLoopSignature
        }
        _currentLoopSignature.value = self._loopSignature
        
        let running = self.isRunning
        defer {
            self.isRunning = running
        }
        self.isRunning = true
        
        defer {
            self._stop.content = false
        }
        //yes, fail if so. It's runtime error
        try! _caller.start() //stops in finalizer, see above
        
        let mode = once ? UV_RUN_ONCE : UV_RUN_DEFAULT
        var timedout:Bool = false
        //yes, fail if so. It's runtime error
        let timer = try! Timer(loop: _loop) {_ in
            timedout = true
            self.stop()
        }
        //yes, fail if so. It's runtime error
        try! timer.start(Timeout(until: until))
        defer {
            timer.close()
        }
        while until.timeIntervalSinceNow >= 0 {
            _loop.run(mode)
            if once || self._stop.content {
                break
            }
        }
        return timedout
    }
    
    public func stop() {
        //protected loops can not stop
        if protected {
            return
        }
        
        if isHome {
            self._stop.content = true
            _loop.stop()
        } else {
            self.executeNoRelay {
                self._stop.content = true
                self._loop.stop()
            }
        }
    }
    
    public func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? UVRunLoop else {
            return false
        }
        return _loop == other._loop
    }
}