//===--- RunLoop.swift ----------------------------------------------===//
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

public protocol SettledType {
    var isHome:Bool {get}
}

public protocol RunLoopType : NonStrictEquatable {
    init()
    
    func semaphore() -> SemaphoreType
    func semaphore(value:Int) -> SemaphoreType
    
    /// tries to execute before other tasks
    func urgent(task:SafeTask)
    func execute(task:SafeTask)
    func execute(delay:Timeout, task:SafeTask)
    
    // commented until @autoclosure is resolved in Swift 3.0
    //func sync<ReturnType>(@autoclosure(escaping) task:() throws -> ReturnType) rethrows -> ReturnType
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType
    
    var native:Any {get}
    
    static var main:RunLoopType {get}
}

public protocol RunnableRunLoopType : RunLoopType {
    func run(timeout:Timeout, once:Bool) -> Bool
    func run(until:NSDate, once:Bool) -> Bool
    
    func stop()
    
    /// protected loop stop shout take to effect while this flag is set
    /// false by default
    var protected:Bool {get set}
}

public extension RunnableRunLoopType {
    func run(timeout:Timeout = .Infinity, once:Bool = false) -> Bool {
        return self.run(timeout.timeSinceNow(), once: once)
    }
    
    func run(until:NSDate) -> Bool {
        return self.run(until, once: false)
    }
}

#if os(Linux)
    #if dispatch
        #if nouv
            public typealias RunLoop = DispatchRunLoop
        #else
            public typealias RunLoop = UVRunLoop
        #endif
    #else
        #if nouv
            private func error() {
                let error = "You can not use 'nouv' key' without dispatch support"
            }
        #else
            public typealias RunLoop = UVRunLoop
        #endif
    #endif
#else
    #if nouv
        public typealias RunLoop = DispatchRunLoop
    #else
        public typealias RunLoop = UVRunLoop
    #endif
#endif