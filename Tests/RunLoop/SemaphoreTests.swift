//
//  SemaphoreTests.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/21/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate

@testable import RunLoop

class SemaphoreTests : XCTestCase {
    
    func testBlockingSemaphoreTimeout() {
        let sema = BlockingSemaphore()
        try! Thread {
            Thread.sleep(.In(timeout: 2))
            sema.signal()
        }
        XCTAssert(!sema.wait(.In(timeout: 1)), "Wait not working")
        XCTAssert(sema.wait(.In(timeout: 2)), "Wait not working")
    }
    
    func testBlockingSemaphoreManySignalTimeout() {
        let count = 3
        let sema = BlockingSemaphore(value: count)
        try! Thread {
            for _ in 0..<count {
                sema.signal()
                Thread.sleep(.In(timeout: 2))
            }
        }
        for _ in 0...count {
            sema.wait()
        }
        
        XCTAssert(!sema.wait(.In(timeout: 1)), "Wait not working")
        XCTAssert(sema.wait(.In(timeout: 2)), "Wait not working")
    }
    
    func stressSemaphore<Semaphore: SemaphoreType>(type:Semaphore.Type) {
        let id = NSUUID().UUIDString
        let queue = dispatch_queue_create(id, DISPATCH_QUEUE_CONCURRENT)
        let sema = Semaphore(value: 1)
        
        for i in 0...1000 {
            let expectation = self.expectationWithDescription("expectation \(i)")
            dispatch_async(queue) {
                sema.wait()
                expectation.fulfill()
                sema.signal()
            }
        }
        
        self.waitForExpectationsWithTimeout(0.2, handler: nil)
    }
    
    func testSemaphoreStress() {
        stressSemaphore(RunLoopSemaphore)
        stressSemaphore(BlockingSemaphore)
    }
    
    func testSemaphoreExternal() {
        let loop = UVRunLoop()
        let sema = loop.semaphore()
        let dispatchLoop = DispatchRunLoop()
        
        dispatchLoop.execute {
            sema.signal()
        }
        
        XCTAssert(sema.wait(.In(timeout: 1)))
    }
}