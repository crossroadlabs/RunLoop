//
//  SemaphoreTests.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/21/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import XCTest3
import Foundation
import Foundation3
import Boilerplate

#if os(Linux) && dispatch
    import Dispatch
#endif

@testable import RunLoop

class SemaphoreTests : XCTestCase {
    
    let taskCount = 1000
    
    func testBlockingSemaphoreTimeout() {
        let sema = BlockingSemaphore()
        let _ = try! Thread {
            Thread.sleep(.In(timeout: 2))
            sema.signal()
        }
        XCTAssert(!sema.wait(.In(timeout: 1)))
        XCTAssert(sema.wait(.In(timeout: 2)))
    }
    
    func testBlockingSemaphoreManySignalTimeout() {
        let count = 3
        let sema = BlockingSemaphore(value: count)
        let _ = try! Thread {
            for _ in 0..<count {
                sema.signal()
                Thread.sleep(.In(timeout: 2))
            }
        }
        for _ in 0...count {
            sema.wait()
        }
        
        XCTAssert(!sema.wait(.In(timeout: 1)))
        XCTAssert(sema.wait(.In(timeout: 2)))
    }
    
    #if !os(Linux) || dispatch
    func stressSemaphoreDispatch<Semaphore: SemaphoreType>(type:Semaphore.Type) {
        let id = NSUUID().uuidString
        let queue = dispatch_queue_create(id, DISPATCH_QUEUE_CONCURRENT)
        let sema = Semaphore(value: 1)
        
        for i in 0..<taskCount {
            let expectation = self.expectation(withDescription: "expectation \(i)")
            dispatch_async(queue) {
                sema.wait()
                expectation.fulfill()
                sema.signal()
            }
        }
        
        self.waitForExpectations(withTimeout: 1.0, handler: nil)
    }
    
    func testLoopSemaphoreStressDispatch() {
        stressSemaphoreDispatch(RunLoopSemaphore)
    }
    
    func testBlockingSemaphoreStressDispatch() {
        stressSemaphoreDispatch(BlockingSemaphore)
    }
    
    #if !nouv
    func testSemaphoreExternal() {
        let loop = UVRunLoop()
        let sema = loop.semaphore()
        let dispatchLoop = DispatchRunLoop()
        
        dispatchLoop.execute {
            sema.signal()
        }
        
        XCTAssert(sema.wait(.In(timeout: 2)))
    }
    #endif
    
    #endif
    
    #if !nouv
    func stressSemaphoreUV<Semaphore: SemaphoreType>(type: Semaphore.Type) {
        let loopCount = 10
        var loops:[UVRunLoop] = []
        let sema = Semaphore(value: 1)
        
        for _ in 0..<loopCount {
            let thAndLoop = threadWithRunLoop(UVRunLoop)
            loops.append(thAndLoop.loop)
        }
        for i in 0..<taskCount {
            let expectation = self.expectation(withDescription: "expectation \(i)")
            loops[(i % loopCount)].execute {
                sema.wait()
                expectation.fulfill()
                sema.signal()
            }
        }
        
        defer {
            for l in loops {
                l.stop()
            }
        }
        
        self.waitForExpectations(withTimeout: 1, handler: nil)
    }
    
    func testLoopSemaphoreStressUV() {
        stressSemaphoreUV(RunLoopSemaphore)
    }
    
    func testBlockingSemaphoreUV() {
        stressSemaphoreUV(BlockingSemaphore)
    }
    
    #endif
}

#if os(Linux)
extension SemaphoreTests {
	static var allTests : [(String, SemaphoreTests -> () throws -> Void)] {
        var tests:[(String, SemaphoreTests -> () throws -> Void)] = [
			("testBlockingSemaphoreTimeout", testBlockingSemaphoreTimeout),
			("testBlockingSemaphoreManySignalTimeout", testBlockingSemaphoreManySignalTimeout),
			("testLoopSemaphoreStressUV", testLoopSemaphoreStressUV),
			("testBlockingSemaphoreUV", testBlockingSemaphoreUV),
		]
        #if dispatch
            tests.append(("testBlockingSemaphoreStressDispatch", testBlockingSemaphoreStressDispatch))
            tests.append(("testLoopSemaphoreStressDispatch", testLoopSemaphoreStressDispatch))
            tests.append(("testSemaphoreExternal", testSemaphoreExternal))
        #endif
        return tests
    }
}
#endif
