//===--- Sync.swift ----------------------------------------------===//
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
import Result

public extension RunLoopType {
    private func syncThroughAsync<ReturnType>(task:() throws -> ReturnType) throws -> ReturnType {
        if let settled = self as? SettledType where settled.isHome {
            return try task()
        }
        
        var result:Result<ReturnType, AnyError>?
        
        let sema = RunLoop.current.semaphore()
        
        self.execute {
            defer {
                sema.signal()
            }
            result = materializeAny(task)
        }
        
        sema.wait()
        
        return try result!.dematerializeAny()
    }
    
    private func syncThroughAsync2<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        //rethrow hack
        return try {
            try self.syncThroughAsync(task)
        }()
    }
    
    /*public func sync<ReturnType>(@autoclosure(escaping) task:() throws -> ReturnType) rethrows -> ReturnType {
        return try syncThroughAsync2(task)
    }*/
    
    public func sync<ReturnType>(task:() throws -> ReturnType) rethrows -> ReturnType {
        return try syncThroughAsync2(task)
    }
}