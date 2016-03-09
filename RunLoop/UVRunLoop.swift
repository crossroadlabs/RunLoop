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
    let relay: Bool
    let urgent:Bool
    
    init(task: SafeTask, relay: Bool, urgent:Bool) {
        self.task = task
        self.relay = relay
        self.urgent = urgent
    }
}

public class UVRunLoop : RunnableRunLoopType, RelayRunLoopType {
    typealias Semaphore = BlockingSemaphore
    
    //wrapping as containers to avoid copying
    private var _personalQueue:MutableAnyContainer<Array<UVRunLoopTask>>
    private var _commonQueue:MutableAnyContainer<Array<UVRunLoopTask>>
    private var _stop:MutableAnyContainer<Bool>
    
    private let _loop:Loop
    private let _wake:Async
    private let _caller:Prepare
    private let _semaphore:SemaphoreType
    
    private var _relay:MutableAnyContainer<RunLoopType?>
    
    public var relay:RunLoopType? {
        didSet {
            _relay.content = relay
        }
    }
    
    private (set) public static var main:RunLoopType = UVRunLoop(loop: Loop.defaultLoop())
    
    private init(loop:Loop) {
        var personalQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        var commonQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        var stop = MutableAnyContainer(false)
        var relay:MutableAnyContainer<RunLoopType?> = MutableAnyContainer(nil)
        
        self._personalQueue = personalQueue
        self._commonQueue = commonQueue
        self._stop = stop
        self._relay = relay
        
        let sema = BlockingSemaphore(value: 1)
        self._semaphore = sema
        
        //Yes, exactly. Fail in runtime if we can not create a loop
        self._loop = loop
        
        self._caller = try! Prepare(loop: _loop) { _ in
            while !personalQueue.content.isEmpty {
                let task = personalQueue.content.removeFirst()
                
                switch relay.content {
                case .Some(let relay):
                    if task.relay {
                        relay.execute(task.task)
                    } else {
                        fallthrough
                    }
                default:
                    task.task()
                    if stop.content {
                        break
                    }
                }
            }
        }
        
        //same with async
        self._wake = try! Async(loop: _loop) { _ in
            sema.wait()
            let urgents = commonQueue.content.filter { task in
                task.urgent
            }.reverse()
            let commons = commonQueue.content.filter { task in
                !task.urgent
            }
            commonQueue.content.removeAll()
            sema.signal()
            
            personalQueue.content.insertContentsOf(urgents, at: commonQueue.content.startIndex)
            personalQueue.content.appendContentsOf(commons)
        }
    }
    
    public convenience required init() {
        self.init(loop: try! Loop())
    }
    
    deinit {
        _wake.close()
        _caller.close()
    }
    
    public func semaphore() -> SemaphoreType {
        return relay?.semaphore() ?? RunLoopSemaphore()
    }
    
    public func semaphore(value:Int) -> SemaphoreType {
        return relay?.semaphore(value) ?? RunLoopSemaphore(value: value)
    }
    
    public func execute(relay:Bool, task: SafeTask) {
        self.execute(relay, urgent: false, task: task)
    }
    
    public func urgent(relay:Bool, task: SafeTask) {
        self.execute(relay, urgent: true, task: task)
    }
    
    public func execute(relay:Bool, urgent:Bool, task: SafeTask) {
        let task = UVRunLoopTask(task: task, relay: relay, urgent: urgent)
        
        if RunLoop.current.isEqualTo(self) {
            //here we are safe to be lock-less
            if urgent {
                _personalQueue.content.insert(task, atIndex: _personalQueue.content.startIndex)
            } else {
                _personalQueue.content.append(task)
            }
        } else {
            do {
                _semaphore.wait()
                _commonQueue.content.append(task)
                defer {
                    _semaphore.signal()
                }
            }
            _wake.send()
        }
    }
    
    public func execute(relay:Bool, delay:Timeout, task: SafeTask) {
        let endTime = delay.timeSinceNow()
        execute {
            let timeout = Timeout(until: endTime)
            
            if relay {
                if let relay = self.relay {
                    relay.execute(timeout, task: task)
                    return
                }
            }
            
            switch timeout {
            case .Immediate:
                self.execute(relay, task: task)
            default:
                //yes, this is a runtime error
                let timer = try! Timer(loop: self._loop) { timer in
                    defer {
                        timer.close()
                    }
                    //it could have changed now when the timer fires
                    if !relay || self.relay == nil {
                        task()
                    } else {
                        self.execute(relay, task: task)
                    }
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
        defer {
            self._stop.content = false
        }
        //yes, fail if so. It's runtime error
        try! _caller.start()
        defer {
            //yes, fail if so. It's runtime error
            try! _caller.stop()
        }
        
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
        if relay != nil {
            self.executeNoRelay {
                self._stop.content = true
                self._loop.stop()
            }
        } else {
            self._stop.content = true
            _loop.stop()
        }
    }
    
    public func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? UVRunLoop else {
            return false
        }
        return _loop == other._loop
    }
}