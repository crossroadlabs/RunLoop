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
    #if !os(Linux) || dispatch
        if Thread.isMain {
            let main = dispatch_get_main_queue()
            dispatch_async(main) {
                if var loop = RunLoop.main as? RelayRunLoopType {
                    loop.relay = DispatchRunLoop.main
                    if let loop = loop as? RunnableRunLoopType {
                        struct CleanupData {
                            let thread:Thread
                            let loop:RunnableRunLoopType
                            
                            init(thread:Thread, loop:RunnableRunLoopType) {
                                self.thread = thread
                                self.loop = loop
                            }
                        }
                        func cleanup(context:UnsafeMutablePointer<Void>) {
                            let data = Unmanaged<AnyContainer<CleanupData>>.fromOpaque(COpaquePointer(context)).takeRetainedValue()
                            data.content.loop.stop()
                            try! data.content.thread.join()
                        }
                        //skip runtime error
                        let thread = try! Thread {
                            loop.run()
                        }
                        
                        let data = CleanupData(thread: thread, loop: loop)
                        let arg = UnsafeMutablePointer<Void>(Unmanaged.passRetained(AnyContainer(data)).toOpaque())
                        dispatch_set_context(main, arg);
                        dispatch_set_finalizer_f(main, cleanup)
                    }
                }
            }
        }
    #endif
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