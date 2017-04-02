//
//  StressTests.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/21/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate
import Foundation

#if !nodispatch
    import Dispatch
#endif

@testable import RunLoop

func threadWithRunLoop<RL: RunLoopProtocol>(type: RL.Type) -> (thread:Boilerplate.Thread, loop: RL) {
    var sema: SemaphoreProtocol
    sema = BlockingSemaphore()
    var loop: RL?
    let thread = try! Boilerplate.Thread {
        loop = RL.current as? RL
        let _ = sema.signal()
        let _ = (loop as? RunnableRunLoopProtocol)?.run()
    }
    let _ = sema.wait()
    return (thread, loop!)
}

#if !os(tvOS)
class StressTests: XCTestCase {
    let threadCount = 100
    let taskCount = 1000
    
    #if uv
    func testStressUV() {
        let lock = NSLock()
        var counter = 0
        let exp = self.expectation(description: "WAIT UV")
        
        let task = {
            lock.lock()
            counter += 1
            if counter == self.threadCount * self.taskCount {
                exp.fulfill()
            }
            lock.unlock()
        }
        var loops = [RunLoopProtocol]()
        
        for _ in 0..<threadCount {
            let thAndLoop = threadWithRunLoop(UVRunLoop)
            loops.append(thAndLoop.loop)
        }
        
        for _ in 0..<taskCount {
            for l in loops {
                l.execute(task)
            }
        }
        
        defer {
            for l in loops {
                if let rl = l as? RunnableRunLoopType {
                    rl.stop()
                }
            }
        }
        
        self.waitForExpectations(withTimeout: 20, handler: nil)
        
        print("Counter \(counter), maxValue: \(threadCount*taskCount)")
    }
    #endif //uv
    
    #if !nodispatch
    func testStressDispatch() {
        let lock = NSLock()
        var counter = 0
        let exp = self.expectation(description: "WAIT DISPATCH")
        
        let task = {
            lock.lock()
            counter += 1
            if counter == self.threadCount * self.taskCount {
                exp.fulfill()
            }
            lock.unlock()
        }
    
        var loops = [RunLoopProtocol]()
        
        for _ in 0..<threadCount {
            loops.append(DispatchRunLoop())
        }
        for _ in 0..<taskCount {
            for l in loops {
                l.execute(task: task)
            }
        }
        
        self.waitForExpectations(timeout: 20, handler: nil)
        
        print("Counter \(counter), maxValue: \(threadCount*taskCount)")
    }
    #endif //!nodispatch
}
#endif //!os(tvOS)

#if os(Linux)
extension StressTests {
	static var allTests : [(String, (StressTests) -> () throws -> Void)] {
        var tests:[(String, (StressTests) -> () throws -> Void)] = []
        #if uv
            tests.append(("testStressUV", testStressUV))
        #endif //!nodispatch
        #if !nodispatch
            tests.append(("testStressDispatch", testStressDispatch))
        #endif //!nodispatch
        return tests
	}
}
#endif
