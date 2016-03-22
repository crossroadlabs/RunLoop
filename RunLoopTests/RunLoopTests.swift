//
//  RunLoopTests.swift
//  RunLoopTests
//
//  Created by Daniel Leping on 3/7/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate

@testable import RunLoop

class RunLoopTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        let expectation = self.expectationWithDescription("init dispatch")
        dispatch_async(dispatch_get_main_queue()) {
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(0.1, handler: nil)
        
        let id = NSUUID().UUIDString
        let queue = dispatch_queue_create(id, DISPATCH_QUEUE_CONCURRENT)
        
        var counter = 0
        
        RunLoop.main.execute(.In(timeout: 0.1)) {
            (RunLoop.current as? RunnableRunLoopType)?.stop()
            print("The End")
        }
        
        for _ in 0...1000 {
            dispatch_async(queue) {
                RunLoop.main.execute {
                    print("lalala:", counter)
                    counter += 1
                }
            }
        }
        
        (RunLoop.main as? RunnableRunLoopType)?.run()
        print("!!!!END!!!")
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testUrgent() {
        let loop = UVRunLoop()
        
        var counter = 1
        
        let execute = self.expectationWithDescription("execute")
        loop.execute {
            XCTAssertEqual(2, counter)
            execute.fulfill()
            loop.stop()
        }
        
        let urgent = self.expectationWithDescription("urgent")
        loop.urgent {
            XCTAssertEqual(1, counter)
            counter += 1
            urgent.fulfill()
        }
        
        loop.run()
        
        self.waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testImmediateTimeout() {
        let expectation = self.expectationWithDescription("OK TIMER")
        RunLoop.current.execute(.Immediate) {
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testNested() {
        let loop = UVRunLoop()
        let outer = self.expectationWithDescription("outer")
        let inner = self.expectationWithDescription("inner")
        loop.execute {
            loop.execute {
                inner.fulfill()
                loop.stop()
            }
            loop.run()
            outer.fulfill()
            loop.stop()
        }
        loop.run()
        self.waitForExpectationsWithTimeout(2, handler: nil)
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
    
    func testBasicRelay() {
        let dispatchLoop = DispatchRunLoop()
        let loop = UVRunLoop()
        loop.relay = dispatchLoop
        
        let immediate = self.expectationWithDescription("immediate")
        let timer = self.expectationWithDescription("timer")
        
        loop.execute {
            XCTAssert(dispatchLoop.isEqualTo(RunLoop.current))
            immediate.fulfill()
        }
        
        loop.execute(.In(timeout: 0.1)) {
            XCTAssert(dispatchLoop.isEqualTo(RunLoop.current))
            timer.fulfill()
            loop.stop()
        }
        
        loop.run()
        
        loop.relay = nil
        
        let immediate2 = self.expectationWithDescription("immediate2")
        loop.execute {
            XCTAssertFalse(dispatchLoop.isEqualTo(RunLoop.current))
            immediate2.fulfill()
            loop.stop()
        }
        
        loop.run()
        
        self.waitForExpectationsWithTimeout(0.2, handler: nil)
    }
    
    func testAutorelay() {
        let immediate = self.expectationWithDescription("immediate")
        RunLoop.main.execute {
            immediate.fulfill()
        }
        self.waitForExpectationsWithTimeout(0.2, handler: nil)
        
        let timer = self.expectationWithDescription("timer")
        RunLoop.main.execute(Timeout(timeout: 0.1)) {
            timer.fulfill()
        }
        self.waitForExpectationsWithTimeout(0.2, handler: nil)
    }
    
    enum TestError : ErrorType {
        case E1
        case E2
    }
    
    func testSyncToDispatch() {
        let dispatchLoop = DispatchRunLoop()
        
        let result = dispatchLoop.sync {
            return "result"
        }
        
        XCTAssertEqual(result, "result")
        
        let fail = self.expectationWithDescription("failed")
        
        do {
            try dispatchLoop.sync {
                throw TestError.E1
            }
            XCTFail("shoud not reach this")
        } catch let e as TestError {
            XCTAssertEqual(e, TestError.E1)
            fail.fulfill()
        } catch {
            XCTFail("shoud not reach this")
        }
        
        self.waitForExpectationsWithTimeout(0.1, handler: nil)
    }
    
    func testSyncToRunLoop() {
        let sema = RunLoop.current.semaphore()
        var loop:RunLoopType = RunLoop.current
        let thread = try! Thread {
            loop = RunLoop.current
            sema.signal()
            (loop as? RunnableRunLoopType)?.run()
        }
        sema.wait()
        
        XCTAssertFalse(loop.isEqualTo(RunLoop.current))
        
        let result = loop.sync {
            return "result"
        }
        
        XCTAssertEqual(result, "result")
        
        let fail = self.expectationWithDescription("failed")
        
        do {
            try loop.sync {
                defer {
                    (loop as? RunnableRunLoopType)?.stop()
                }
                throw TestError.E1
            }
            XCTFail("shoud not reach this")
        } catch let e as TestError {
            XCTAssertEqual(e, TestError.E1)
            fail.fulfill()
        } catch {
            XCTFail("shoud not reach this")
        }
        
        try! thread.join()
        
        self.waitForExpectationsWithTimeout(0.1, handler: nil)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
