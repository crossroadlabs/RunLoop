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

private struct RelayData {
    let relay:RunLoopType
    let signature:NSUUID
    
    init(relay:RunLoopType, signature:NSUUID) {
        self.relay = relay
        self.signature = signature
    }
}

public class UVRunLoop : RunnableRunLoopType, RelayRunLoopType {
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
    
    private var _relay:MutableAnyContainer<RelayData?>
    
    public var protected:Bool = false
    
    private func newRelayData(relay:RunLoopType?) -> RelayData? {
        var data:RelayData?
        
        switch relay {
        case .Some(let relay) where _relay.content?.relay.isEqualTo(relay) ?? false:
            data = RelayData(relay: relay, signature: _relay.content!.signature)
        case .Some(let relay):
            data = RelayData(relay: relay, signature: NSUUID())
        default:
            data = nil
        }
        
        return data
    }
    
    public var relay:RunLoopType? {
        didSet {
            let data = newRelayData(relay)
            let oldData = _relay.content
            _relay.content = data
            
            let new = data.map { data in
                oldData.map { oldData in
                    data.relay.isEqualTo(oldData.relay)
                } ?? true
            } ?? false
            
            if new {
                if let data = data {
                    sendRelayRequest(data)
                }
            }
        }
    }
    
    private (set) public static var main:RunLoopType = UVRunLoop(loop: Loop.defaultLoop())
    
    private init(loop:Loop) {
        let relayQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let personalQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let commonQueue = MutableAnyContainer(Array<UVRunLoopTask>())
        let stop = MutableAnyContainer(false)
        let relay:MutableAnyContainer<RelayData?> = MutableAnyContainer(nil)
        
        self._relayQueue = relayQueue
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
                
                if task.relay {
                    relayQueue.content.append(task)
                } else {
                    task.task()
                }
            }
            
            while relay.content == nil && !relayQueue.content.isEmpty {
                let task = relayQueue.content.removeFirst()
                task.task()
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
    
    private func sendRelayRequest(data:RelayData) {
        data.relay.execute {
            self.relayTasks(data.signature)
        }
    }
    
    private func relayTasks(signature:NSUUID) {
        let sema = RunLoop.current.semaphore()
        
        self.executeNoRelay {
            defer {
                sema.signal()
            }
            guard let relay = self._relay.content else {
                print("CONTENT FAIL")
                return
            }
            
            if relay.signature != signature {
                print("SIG FAIL")
                //we don't process if there is no sig match
                return
            }
            
            while !self._relayQueue.content.isEmpty {
                let task = self._relayQueue.content.removeFirst()
                relay.relay.execute(task.task)
            }
            
            let data = RelayData(relay: relay.relay, signature: NSUUID())
            self._relay.content = data
            self.sendRelayRequest(data)
        }
        
        sema.wait()
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
        
        if self.relay == nil && RunLoop.current.isEqualTo(self) {
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
        if protected {
            return
        }
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