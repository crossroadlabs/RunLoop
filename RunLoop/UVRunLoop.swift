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

public class UVRunLoop : RunnableRunLoopType {
    typealias Semaphore = BlockingSemaphore
    
    //wrapping as containers to avoid copying
    private var _personalQueue:MutableAnyContainer<Array<SafeTask>>
    private var _commonQueue:MutableAnyContainer<Array<SafeTask>>
    
    private let _loop:Loop
    private let _wake:Async
    private let _semaphore:SemaphoreType
    
    init() {
        var personalQueue = MutableAnyContainer(Array<SafeTask>())
        var commonQueue = MutableAnyContainer(Array<SafeTask>())
        
        self._personalQueue = personalQueue
        self._commonQueue = commonQueue
        
        let sema = Semaphore(value: 1)
        self._semaphore = sema
        
        //Yes, exactly. Fail in runtime if we can not create a loop
        self._loop = try! Loop()
        //same with async
        self._wake = try! Async(loop: _loop) { _ in
            sema.wait()
            personalQueue.content.appendContentsOf(commonQueue.content)
            commonQueue.content.removeAll()
            defer {
                sema.signal()
            }
        }
    }
    
    public func semaphore() -> SemaphoreType {
        return Semaphore()
    }
    
    public func semaphore(value:Int) -> SemaphoreType {
        return Semaphore(value: value)
    }
    
    public func execute(task:SafeTask) {
        if RunLoop.current.isEqualTo(self) {
            //here we are safe to be lock-less
            _personalQueue.content.append(task)
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
    
    public var native:Any {
        get {
            return _loop
        }
    }
    
    /// returns true if timed out, false otherwise
    public func run(until:NSDate, once:Bool) -> Bool {
        let mode = once ? UV_RUN_ONCE : UV_RUN_DEFAULT
        var timedout:Bool = false
        //yes, fail if so. It's runtime error
        let timer = try! Timer(loop: _loop) {_ in
            timedout = true
            self._loop.stop()
        }
        //yes, fail if so. It's runtime error
        try! timer.start(Timeout(until: until))
        defer {
            timer.close()
        }
        while until.timeIntervalSinceNow <= 0 {
            _loop.run(mode)
            if once {
                break
            }
        }
        return timedout
    }
    
    public func isEqualTo(other: NonStrictEquatable) -> Bool {
        guard let other = other as? UVRunLoop else {
            return false
        }
        return _loop == other._loop
    }
}