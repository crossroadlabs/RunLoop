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

#if !nodispatch
    import Foundation
    import Dispatch
    
    import Boilerplate
    import Result
    
    private extension DispatchQueue {
        private static let _idKey = DispatchSpecificKey<UUID>()
        
        var id:UUID {
            get {
                guard let id = self.getSpecific(key: DispatchQueue._idKey) else {
                    let newid = UUID()
                    self.setSpecific(key: DispatchQueue._idKey, value: newid)
                    return newid
                }
                return id
            }
        }
        
        static var id:UUID? {
            get {
                return self.getSpecific(key: DispatchQueue._idKey)
            }
        }
    }
    
    public class DispatchSemaphore : SemaphoreProtocol {
        let sema:Dispatch.DispatchSemaphore
        
        public required convenience init() {
            self.init(value: 0)
        }
        
        public required init(value: Int) {
            self.sema = Dispatch.DispatchSemaphore(value: value)
        }
        
        public func wait() -> Bool {
            return wait(timeout: .Infinity)
        }
        
        public func wait(until:Date) -> Bool {
            return wait(timeout: Timeout(until: until))
        }
        
        public func wait(timeout: Timeout) -> Bool {
            let time = timeout.dispatchTime
            let result = sema.wait(timeout: time)
            return result == .success
        }
        
        public func signal() -> Int {
            return sema.signal()
        }
    }
    
    public class DispatchRunLoop: RunLoopProtocol, NonStrictEquatable {
        private let _queue:DispatchQueue
        
        public init(queue:DispatchQueue) {
            self._queue = queue
        }
        
        public required convenience init() {
            let name = NSUUID().uuidString
            let queue = DispatchQueue(label: name)
            self.init(queue: queue)
        }
        
        public class func makeSemaphore(value:Int?, loop:RunLoopProtocol?) -> SemaphoreProtocol {
            return value.map({DispatchSemaphore(value: $0)}) ?? DispatchSemaphore()
        }
        
        public func semaphore() -> SemaphoreProtocol {
            return DispatchSemaphore()
        }
        
        public func semaphore(value:Int) -> SemaphoreProtocol {
            return DispatchSemaphore(value: value)
        }
        
        public func execute(task:@escaping SafeTask) {
            _queue.async {
                let _ = RunLoop.trySetFactory {
                    return self
                }
                task()
            }
        }
        
        public func execute(delay:Timeout, task:@escaping SafeTask) {
            _queue.asyncAfter(deadline: delay.dispatchTime) {
                let _ = RunLoop.trySetFactory {
                    return self
                }
                task()
            }
        }
        
        private func dispatchSync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
            //rethrow hack
            return try {
                //TODO: test
                if let currentId = DispatchQueue.id, currentId == self._queue.id {
                    return try task()
                }
                
                var result:Result<ReturnType, AnyError>?
                
                _queue.sync {
                    result = materialize(task)
                }
                
                return try result!.dematerializeAny()
            }()
        }
        
        /*public func sync<ReturnType>(@autoclosure(escaping) task:() throws -> ReturnType) rethrows -> ReturnType {
            return try dispatchSync(task)
        }*/
        
        public func sync<ReturnType>(task:TaskWithResult<ReturnType>) rethrows -> ReturnType {
            return try dispatchSync(task: task)
        }
        
        public var native:Any {
            get {
                return _queue
            }
        }
        
        public static let main:RunLoopProtocol = DispatchRunLoop(queue: DispatchQueue.main)
        
        public func isEqual(to other: NonStrictEquatable) -> Bool {
            guard let other = other as? DispatchRunLoop else {
                return false
            }
            //TODO: test
            return self._queue == other._queue
        }
    }
#endif
