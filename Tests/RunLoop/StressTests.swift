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

#if !os(tvOS)
    import XCTest3
#endif

#if os(Linux) && dispatch
    import Dispatch
#endif

@testable import RunLoop

func threadWithRunLoop<RL: RunLoopType>(type: RL.Type) -> (thread:Thread, loop: RL) {
    var sema: SemaphoreType
    sema = BlockingSemaphore()
    var loop: RL?
    let thread = try! Thread {
        loop = RL.current as? RL
        sema.signal()
        (loop as? RunnableRunLoopType)?.run()
    }
    sema.wait()
    return (thread, loop!)
}

#if !os(tvOS)
class StressTests: XCTestCase {
    let threadCount = 100
    let taskCount = 1000
    
    #if !nouv
    func testStressUV() {
        let lock = NSLock()
        var counter = 0
        let exp = self.expectation(withDescription: "WAIT UV")
        
        let task = {
            lock.lock()
            counter += 1
            if counter == self.threadCount * self.taskCount {
                exp.fulfill()
            }
            lock.unlock()
        }
        var loops = [RunLoopType]()
        
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
    #endif
    
    #if !os(Linux) || dispatch
    func testStressDispatch() {
        let lock = NSLock()
        var counter = 0
        let exp = self.expectation(withDescription: "WAIT DISPATCH")
        
        let task = {
            lock.lock()
            counter += 1
            if counter == self.threadCount * self.taskCount {
                exp.fulfill()
            }
            lock.unlock()
        }
    
        var loops = [RunLoopType]()
        
        for _ in 0..<threadCount {
            loops.append(DispatchRunLoop())
        }
        for _ in 0..<taskCount {
            for l in loops {
                l.execute(task)
            }
        }
        
        self.waitForExpectations(withTimeout: 20, handler: nil)
        
        print("Counter \(counter), maxValue: \(threadCount*taskCount)")
    }
    #endif
}
#endif

#if os(Linux)
extension StressTests {
	static var allTests : [(String, StressTests -> () throws -> Void)] {
        var tests:[(String, StressTests -> () throws -> Void)] = [
			("testStressUV", testStressUV),
		]
        #if dispatch
            tests.append(("testStressDispatch", testStressDispatch))
        #endif
        return tests
	}
}
#endif
