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

public protocol Settled {
    var isHome:Bool {get}
}

public protocol RunLoopProtocol : NonStrictEquatable {
    init()
    
    //for private use
    static func makeSemaphore(value:Int?, loop:RunLoopProtocol?) -> SemaphoreProtocol
    
    /// tries to execute before other tasks
    func urgent(task:@escaping SafeTask)
    func execute(task:@escaping SafeTask)
    func execute(delay:Timeout, task:@escaping SafeTask)
    
    // commented until @autoclosure is resolved in Swift 3.0
    //func sync<ReturnType>(@autoclosure(escaping) task:() throws -> ReturnType) rethrows -> ReturnType
    func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType
    
    var native:Any {get}
    
    static var main:RunLoopProtocol {get}
}

public extension RunLoopProtocol {
    static func semaphore(value:Int? = nil, loop:RunLoopProtocol? = RunLoop.current) -> SemaphoreProtocol {
        guard let semaClass = loop.flatMap({type(of: $0)}) else {
            return self.makeSemaphore(value: value, loop: loop)
        }
        
        return semaClass.makeSemaphore(value: value, loop: loop)
    }
}

public extension RunLoopProtocol {
    public static var reactive:Self.Type {
        get {
            return self
        }
    }
}

public protocol RunnableRunLoopProtocol : RunLoopProtocol {
    func run(timeout:Timeout, once:Bool) -> Bool
    func run(until:Date, once:Bool) -> Bool
    
    func stop()
    
    /// protected loop stop shout take to effect while this flag is set
    /// false by default
    var protected:Bool {get set}
}

public extension RunnableRunLoopProtocol {
    func run(timeout:Timeout = .Infinity, once:Bool = false) -> Bool {
        return self.run(timeout: timeout, once: once)
    }
    
    func run(until:Date) -> Bool {
        return self.run(until: until, once: false)
    }
}

#if uv
    public typealias RunLoop = UVRunLoop
#elseif !nodispatch
    public typealias RunLoop = DispatchRunLoop
#else
    private func error() {
        let error = "You can not use 'nodispatch' key' without other (uv) run loop support"
    }
#endif //uv
