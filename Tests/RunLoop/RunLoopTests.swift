//
//  RunLoopTests.swift
//  RunLoopTests
//
//  Created by Daniel Leping on 3/7/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate
import Foundation3

#if !os(tvOS)
    import XCTest3
#endif

@testable import RunLoop

class RunLoopTests: XCTestCase {
    
    #if !nouv
    func testExecute() {
        var counter = 0
        
        let task = {
            RunLoop.main.execute {
                print("lalala:", counter)
                counter += 1
            }
        }
        var loops = [RunLoopType]()
        
        for _ in 0..<3 {
            let thAndLoop = threadWithRunLoop(UVRunLoop)
            loops.append(thAndLoop.loop)
        }
        for i in 0..<1000 {
            loops[i % loops.count].execute(task)
        }
        
        defer {
            for l in loops {
                if let rl = l as? RunnableRunLoopType {
                    rl.stop()
                }
            }
        }
        
        
        RunLoop.main.execute(.In(timeout: 0.1)) {
            (RunLoop.current as? RunnableRunLoopType)?.stop()
            print("The End")
        }
        
        let main = (RunLoop.main as? RunnableRunLoopType)
        main?.run()
    }
    #endif
    
    func testImmediateTimeout() {
        let expectation = self.expectation(withDescription: "OK TIMER")
        let loop = RunLoop.current
        loop.execute(.Immediate) {
            expectation.fulfill()
            #if os(Linux)
                (loop as? RunnableRunLoopType)?.stop()
            #endif
        }
        #if os(Linux)
            (loop as? RunnableRunLoopType)?.run()
        #endif
        self.waitForExpectations(withTimeout: 2, handler: nil)
    }
    
    func testNested() {
        let rl = RunLoop.current as? RunnableRunLoopType // will be main
        
        let outer = self.expectation(withDescription: "outer")
        let inner = self.expectation(withDescription: "inner")
        rl?.execute {
            print("Execute called")
            rl?.execute {
                print("Inner execute called")
                inner.fulfill()
                #if os(Linux)
                    rl?.stop()
                #endif
            }
            #if os(Linux)
                rl?.run()
            #endif
            outer.fulfill()
            #if os(Linux)
                rl?.stop()
            #endif
        }
        #if os(Linux)
            rl?.run()
        #endif
        self.waitForExpectations(withTimeout: 2, handler: nil)
    }
    
    enum TestError : ErrorProtocol {
        case E1
        case E2
    }
    
    #if !os(Linux) || dispatch
    func testSyncToDispatch() {
        let dispatchLoop = DispatchRunLoop()
        
        let result = dispatchLoop.sync {
            return "result"
        }
        
        XCTAssertEqual(result, "result")
        
        let fail = self.expectation(withDescription: "failed")
        
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
        
        self.waitForExpectations(withTimeout: 0.1, handler: nil)
    }
    #endif
    
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
        
        let fail = self.expectation(withDescription: "failed")
        
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
        
        self.waitForExpectations(withTimeout: 0.1, handler: nil)
    }
    
    #if !nouv
    func testUrgent() {
        let loop = UVRunLoop()
        
        var counter = 1
        
        let execute = self.expectation(withDescription: "execute")
        loop.execute {
            XCTAssertEqual(2, counter)
            execute.fulfill()
            loop.stop()
        }
        
        let urgent = self.expectation(withDescription: "urgent")
        loop.urgent {
            XCTAssertEqual(1, counter)
            counter += 1
            urgent.fulfill()
        }
        
        loop.run()
        
        self.waitForExpectations(withTimeout: 1, handler: nil)
    }
    
    #if !os(Linux) || dispatch
    func testBasicRelay() {
        let dispatchLoop = DispatchRunLoop()
        let loop = UVRunLoop()
        loop.relay = dispatchLoop
        
        let immediate = self.expectation(withDescription: "immediate")
        let timer = self.expectation(withDescription: "timer")
        
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
        
        let immediate2 = self.expectation(withDescription: "immediate2")
        loop.execute {
            XCTAssertFalse(dispatchLoop.isEqualTo(RunLoop.current))
            immediate2.fulfill()
            loop.stop()
        }
        
        loop.run()
        
        self.waitForExpectations(withTimeout: 0.2, handler: nil)
    }
    
    func testAutorelay() {
        let immediate = self.expectation(withDescription: "immediate")
        RunLoop.current.execute {
            immediate.fulfill()
        }
        self.waitForExpectations(withTimeout: 0.2, handler: nil)
        
        let timer = self.expectation(withDescription: "timer")
        RunLoop.current.execute(Timeout(timeout: 0.1)) {
            timer.fulfill()
        }
        self.waitForExpectations(withTimeout: 0.2, handler: nil)
    }
    #endif
    
    func testStopUV() {
        let rl = threadWithRunLoop(UVRunLoop).loop
        var counter = 0
        rl.execute {
            counter += 1
            rl.stop()
        }
        rl.execute {
            counter += 1
            rl.stop()
        }
        
        (RunLoop.current as? RunnableRunLoopType)?.run(.In(timeout: 1))
        
        XCTAssert(counter == 1)
    }
    
    func testNestedUV() {
        let rl = threadWithRunLoop(UVRunLoop).loop
        let lvl1 = self.expectation(withDescription: "lvl1")
        let lvl2 = self.expectation(withDescription: "lvl2")
        let lvl3 = self.expectation(withDescription: "lvl3")
        let lvl4 = self.expectation(withDescription: "lvl4")
        rl.execute {
            rl.execute {
                rl.execute {
                    rl.execute {
                        lvl4.fulfill()
                        rl.stop()
                    }
                    rl.run()
                    lvl3.fulfill()
                    rl.stop()
                }
                rl.run()
                lvl2.fulfill()
                rl.stop()
            }
            rl.run()
            lvl1.fulfill()
            rl.stop()
        }
        self.waitForExpectations(withTimeout: 0.2, handler: nil)
    }
    #endif
}

#if os(Linux)
extension RunLoopTests {
	static var allTests : [(String, RunLoopTests -> () throws -> Void)] {
        var tests:[(String, RunLoopTests -> () throws -> Void)] = [
			("testExecute", testExecute),
			("testImmediateTimeout", testImmediateTimeout),
			("testNested", testNested),
			("testSyncToRunLoop", testSyncToRunLoop),
			("testUrgent", testUrgent),
			("testStopUV", testStopUV),
			("testNestedUV", testNestedUV),
		]
        #if dispatch
            tests.insert(("testSyncToDispatch", testSyncToDispatch))
            tests.insert(("testBasicRelay", testBasicRelay))
            tests.insert(("testAutorelay", testAutorelay))
        #endif
        
        return tests
	}
}
#endif