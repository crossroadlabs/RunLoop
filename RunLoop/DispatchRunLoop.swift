//===--- DispatchRunLoop.swift ----------------------------------------------===//
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

#if !os(Linux) || dispatch
    import Foundation
    import Foundation3
    import Dispatch
    
    import Boilerplate
    import Result
    
    public class DispatchSemaphore : SemaphoreType {
        let sema:dispatch_semaphore_t
        
        public required convenience init() {
            self.init(value: 0)
        }
        
        public required init(value: Int) {
            self.sema = dispatch_semaphore_create(value)
        }
        
        public func wait() -> Bool {
            return wait(.Infinity)
        }
        
        public func wait(until:NSDate) -> Bool {
            return wait(Timeout(until: until))
        }
        
        public func wait(timeout: Timeout) -> Bool {
            let time = timeout.dispatchTime
            let result = dispatch_semaphore_wait(sema, time)
            return result == 0
        }
        
        public func signal() -> Int {
            return dispatch_semaphore_signal(sema)
        }
    }
    
    public class DispatchRunLoop: RunLoopType, NonStrictEquatable {
        private let _queue:dispatch_queue_t!
        
        public init(queue:dispatch_queue_t!) {
            self._queue = queue
        }
        
        public required convenience init() {
            let name = NSUUID().uuidString
            let queue = dispatch_queue_create(name, nil)
            self.init(queue: queue)
        }
        
        public func semaphore() -> SemaphoreType {
            return DispatchSemaphore()
        }
        
        public func semaphore(value:Int) -> SemaphoreType {
            return DispatchSemaphore(value: value)
        }
        
        public func execute(task:SafeTask) {
            dispatch_async(_queue) {
                RunLoop.trySetFactory {
                    return self
                }
                task()
            }
        }
        
        public func execute(delay:Timeout, task:SafeTask) {
            dispatch_after(delay.dispatchTime, _queue) {
                RunLoop.trySetFactory {
                    return self
                }
                task()
            }
        }
        
        private func dispatchSync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
            //rethrow hack
            return try {
                //TODO: test
                if dispatch_queue_get_label(self._queue) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) {
                    return try task()
                }
                
                var result:Result<ReturnType, AnyError>?
                
                dispatch_sync(_queue) {
                    result = materializeAny(task)
                }
                
                return try result!.dematerializeAny()
            }()
        }
        
        /*public func sync<ReturnType>(@autoclosure(escaping) task:() throws -> ReturnType) rethrows -> ReturnType {
            return try dispatchSync(task)
        }*/
        
        public func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
            return try dispatchSync(task)
        }
        
        public var native:Any {
            get {
                return _queue
            }
        }
        
        public static let main:RunLoopType = DispatchRunLoop(queue: dispatch_get_main_queue())
        
        public func isEqualTo(other: NonStrictEquatable) -> Bool {
            guard let other = other as? DispatchRunLoop else {
                return false
            }
            //TODO: test
            return dispatch_queue_get_label(self._queue) == dispatch_queue_get_label(other._queue)
        }
    }
#endif
