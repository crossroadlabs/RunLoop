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
    
    func testExample() {
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
        
        let main = (RunLoop.main as? RunnableRunLoopType)
        main?.run()
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testImmediateTimeout() {
        let expectation = self.expectationWithDescription("OK TIMER")
        RunLoop.current.execute(.Immediate) {
            expectation.fulfill()
            (RunLoop.current as? RunnableRunLoopType)?.stop()
        }
        (RunLoop.current as? RunnableRunLoopType)?.run()
        self.waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testNested() {
        let rl = RunLoop.current as? RunnableRunLoopType
        let outer = self.expectationWithDescription("outer")
        let inner = self.expectationWithDescription("inner")
        RunLoop.current.execute {
            RunLoop.current.execute {
                inner.fulfill()
                rl?.stop()
            }
            rl?.run()
            outer.fulfill()
            rl?.stop()
        }
        rl?.run()
        self.waitForExpectationsWithTimeout(2, handler: nil)
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
    
}

#if os(Linux)
extension RunLoopTests : XCTestCaseProvider {
	var allTests : [(String, () throws -> Void)] {
		return [
			("testExample", testExample),
			("testImmediateTimeout", testImmediateTimeout),
			("testNested", testNested),
			("testSemaphoreStress", testSemaphoreStress),
			("testSemaphoreExternal", testSemaphoreExternal),
			("testSyncToDispatch", testSyncToDispatch),
			("testSyncToRunLoop", testSyncToRunLoop),
			("testUrgent", testUrgent),
		]
	}
}
#endif