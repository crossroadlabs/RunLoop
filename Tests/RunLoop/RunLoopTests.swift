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
    func testUVExecute() {
        var counter = 0
        
        let task = {
            RunLoop.main.execute {
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
            print("The End. Counter: \(counter)")
        }
        
        let main = (RunLoop.main as? RunnableRunLoopType)
        main?.run()
    }
    #endif
    
    #if !os(Linux) || dispatch
    func testDispatchExecute() {
        let rl = DispatchRunLoop()
        let count = 1000
        var counter = 0
        
        let exp = self.expectation(withDescription: "OK EXECUTE")
        
        let task = {
            counter += 1
            if counter == count {
                exp.fulfill()
            }
        }
        for _ in 0..<count {
            rl.execute(task)
        }
        self.waitForExpectations(withTimeout: 2, handler: nil)
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
        #if os(Linux)
            let rl = RunLoop.current as? RunnableRunLoopType // will be main
        #else
            let rl = Optional<RunLoopType>(RunLoop.current) // will be main too.
        #endif
        
        print("Current run loop: \(rl)")
        
        let outer = self.expectation(withDescription: "outer")
        let inner = self.expectation(withDescription: "inner")
        rl?.execute {
            rl?.execute {
                print("Inner execute called")
                inner.fulfill()
                #if os(Linux) && !dispatch
                    rl?.stop()
                #endif
            }
            #if os(Linux) && !dispatch
                rl?.run()
            #endif
            print("Execute called")
            outer.fulfill()
            #if os(Linux) && !dispatch
                rl?.stop()
            #endif
        }
        
        #if os(Linux) && !dispatch
            rl?.run(.In(timeout: 2))
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
    
    func testNestedUVTimeoutRun() {
        let rl = threadWithRunLoop(UVRunLoop).loop
        var counter = 0
        
        rl.execute {
            rl.execute {
                counter += 1
            }
            rl.run(.In(timeout: 2))
            counter += 1
        }
        Thread.sleep(1)
        XCTAssert(counter == 1)
        Thread.sleep(1.5)
        XCTAssert(counter == 2)
        rl.stop()
    }
    
    #if os(Linux) && !dispatch
    func testMainUVTimeoutRun() {
        let rl = UVRunLoop.main as! RunnableRunLoopType
        var counter = 0
        
        rl.execute {
            rl.execute {
                counter += 1
            }
            rl.run(.In(timeout: 2))
            counter += 1
        }
        rl.run(.In(timeout: 1))
        XCTAssert(counter == 2)
        rl.run(.In(timeout: 1))
        XCTAssert(counter == 2)
    }
    #endif
    #endif
}

#if os(Linux)
extension RunLoopTests {
	static var allTests : [(String, RunLoopTests -> () throws -> Void)] {
        var tests:[(String, RunLoopTests -> () throws -> Void)] = [
			("testUVExecute", testUVExecute),
			("testImmediateTimeout", testImmediateTimeout),
			("testNested", testNested),
			("testSyncToRunLoop", testSyncToRunLoop),
			("testUrgent", testUrgent),
			("testStopUV", testStopUV),
			("testNestedUV", testNestedUV),
			("testNestedUVTimeoutRun", testNestedUVTimeoutRun)
		]
        #if dispatch
            tests.append(("testDispatchExecute", testDispatchExecute))
            tests.append(("testSyncToDispatch", testSyncToDispatch))
            tests.append(("testBasicRelay", testBasicRelay))
            tests.append(("testAutorelay", testAutorelay))
        #else
            tests.append(("testMainUVTimeoutRun", testMainUVTimeoutRun))
        #endif
        
        return tests
	}
}
#endif
