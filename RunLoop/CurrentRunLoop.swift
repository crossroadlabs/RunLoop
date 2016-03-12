//===--- CurrentRunLoop.swift ----------------------------------------------===//
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

public typealias RunLoopFactory = () -> RunLoopType

private class RunLoopData {
    private var _loop:RunLoopType?
    let factory:RunLoopFactory
    
    init(factory:RunLoopFactory) {
        self.factory = factory
    }
    
    var loop:RunLoopType {
        get {
            if _loop == nil {
                _loop = factory()
            }
            // yes, it's always value
            return _loop!
        }
    }
}

private let _runLoopData = try! ThreadLocal<RunLoopData>()

private func defaultRunLoopFactory() -> RunLoopType {
    return Thread.isMain ? RunLoop.main : RunLoop()
}

public extension RunLoopType {
    public static var current:RunLoopType {
        get {
            var value = _runLoopData.value
            if value == nil {
                value = RunLoopData(factory: defaultRunLoopFactory)
                _runLoopData.value = value
                
            }
            
            //yes, it always has value
            return value!.loop
        }
    }
    
    /// sets RunLoopFactory for current thread if not set yet.
    /// returns: true if succesfully set, false otherwise
    public static func trySetFactory(factory:RunLoopFactory) -> Bool {
        if _runLoopData.value == nil {
            _runLoopData.value = RunLoopData(factory: factory)
            return true
        } else {
            return false
        }
    }
}