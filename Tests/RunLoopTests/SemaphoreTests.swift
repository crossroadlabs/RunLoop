//
//  SemaphoreTests.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/21/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Foundation
import Boilerplate

#if dispatch || !os(Linux)
    import Dispatch
#endif

@testable import RunLoop

class SemaphoreTests : XCTestCase {
    
    let taskCount = 1000
    
    func testBlockingSemaphoreTimeout() {
        let sema = BlockingSemaphore()
        let _ = try! Boilerplate.Thread {
            Boilerplate.Thread.sleep(timeout: .In(timeout: 2))
            sema.signal()
        }
        XCTAssert(!sema.wait(timeout: .In(timeout: 1)))
        XCTAssert(sema.wait(timeout: .In(timeout: 2)))
    }
    
    func testBlockingSemaphoreManySignalTimeout() {
        let count = 3
        let sema = BlockingSemaphore(value: count)
        let _ = try! Boilerplate.Thread {
            for _ in 0..<count {
                sema.signal()
                Boilerplate.Thread.sleep(timeout: .In(timeout: 2))
            }
        }
        for _ in 0...count {
            sema.wait()
        }
        
        XCTAssert(!sema.wait(timeout: .In(timeout: 1)))
        XCTAssert(sema.wait(timeout: .In(timeout: 2)))
    }
    
    #if !os(Linux) || dispatch
    func stressSemaphoreDispatch<Semaphore: SemaphoreProtocol>(type:Semaphore.Type) {
        let id = NSUUID().uuidString
        let queue = DispatchQueue(label: id, qos: .default, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
        
        let sema = Semaphore(value: 1)
        
        for i in 0..<taskCount {
            let expectation = self.expectation(description: "expectation \(i)")
            queue.async {
                sema.wait()
                expectation.fulfill()
                sema.signal()
            }
        }
        
        self.waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testLoopSemaphoreStressDispatch() {
        stressSemaphoreDispatch(type: RunLoopSemaphore.self)
    }
    
    func testBlockingSemaphoreStressDispatch() {
        stressSemaphoreDispatch(type: BlockingSemaphore.self)
    }
    
    #if (os(Linux) && !nouv) || uv
    func testSemaphoreExternal() {
        let loop = UVRunLoop()
        let sema = loop.semaphore()
        let dispatchLoop = DispatchRunLoop()
        
        dispatchLoop.execute {
            sema.signal()
        }
        
        XCTAssert(sema.wait(.In(timeout: 2)))
    }
    #endif //(os(Linux) && !nouv) || uv
    
    #endif
    
    #if (os(Linux) && !nouv) || uv
    func stressSemaphoreUV<Semaphore: SemaphoreType>(type: Semaphore.Type) {
        let loopCount = 10
        var loops:[UVRunLoop] = []
        let sema = Semaphore(value: 1)
        
        for _ in 0..<loopCount {
            let thAndLoop = threadWithRunLoop(UVRunLoop)
            loops.append(thAndLoop.loop)
        }
        for i in 0..<taskCount {
            let expectation = self.expectation(description: "expectation \(i)")
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
        
        self.waitForExpectations(timeout: 1, handler: nil)
    }
    
    func testLoopSemaphoreStressUV() {
        stressSemaphoreUV(RunLoopSemaphore.self)
    }
    
    func testBlockingSemaphoreUV() {
        stressSemaphoreUV(BlockingSemaphore.self)
    }
    
    #endif //(os(Linux) && !nouv) || uv
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
