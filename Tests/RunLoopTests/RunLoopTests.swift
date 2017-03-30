//
//  RunLoopTests.swift
//  RunLoopTests
//
//  Created by Daniel Leping on 3/7/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate

#if !nodispatch
    import Dispatch
#endif //!nodispatch

import RunLoop

class RunLoopTests: XCTestCase {
    #if !nodispatch
        func freshLoop() -> RunLoopProtocol {
            let queue = DispatchQueue.global()
            let loop = DispatchRunLoop(queue: queue)
            return loop
        }
    #else
        //FIXME
        func freshLoop() -> RunLoopProtocol {
            var loop = RunLoop.reactive.current
            let sema = RunLoop.semaphore(loop: loop)
            let thread = try! Boilerplate.Thread {
                loop = RunLoop.current
                sema.signal()
                loop.flatMap({$0 as? RunnableRunLoopProtocol})?.run()
            }
            sema.wait()
        }
    #endif
    
    #if uv
    func testUVExecute() {
        var counter = 0
        
        let task = {
            RunLoop.main.execute {
                counter += 1
            }
        }
        var loops = [RunLoopProtocol]()
        
        for _ in 0..<3 {
            let thAndLoop = threadWithRunLoop(UVRunLoop)
            loops.append(thAndLoop.loop)
        }
        for i in 0..<1000 {
            loops[i % loops.count].execute(task: task)
        }
        
        defer {
            for l in loops {
                if let rl = l as? RunnableRunLoopProtocol {
                    rl.stop()
                }
            }
        }
        
        
        RunLoop.main.execute(.In(timeout: 0.1)) {
            (RunLoop.current as? RunnableRunLoopProtocol)?.stop()
            print("The End. Counter: \(counter)")
        }
        
        let main = (RunLoop.main as? RunnableRunLoopProtocol)
        main?.run()
    }
    #endif //uv
    
    #if !nodispatch
    func testDispatchExecute() {
        let rl = DispatchRunLoop()
        let count = 1000
        var counter = 0
        
        let exp = self.expectation(description: "OK EXECUTE")
        
        let task = {
            counter += 1
            if counter == count {
                exp.fulfill()
            }
        }
        for _ in 0..<count {
            rl.execute(task: task)
        }
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    #endif //!nodispatch
    
    func testImmediateTimeout() {
        let expectation = self.expectation(description: "OK TIMER")
        let loop = RunLoop.reactive.current!
        loop.execute(delay: .Immediate) {
            expectation.fulfill()
            (loop as? RunnableRunLoopProtocol)?.stop()
        }
        let _ = (loop as? RunnableRunLoopProtocol)?.run()
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testNested() {
        #if os(Linux)
            let rl = RunLoop.current.flatMap({$0 as? RunnableRunLoopProtocol}) // will be main
        #else //os(Linux)
            let rl = RunLoop.reactive.current // will be main too.
        #endif //os(Linux)
        
        print("Current run loop: \(rl)")
        
        let outer = self.expectation(description: "outer")
        let inner = self.expectation(description: "inner")
        rl?.execute {
            rl?.execute {
                print("Inner execute called")
                inner.fulfill()
                #if uv
                    rl?.stop()
                #endif //uv
            }
            #if uv
                rl?.run()
            #endif //uv
            print("Execute called")
            outer.fulfill()
            #if uv
                rl?.stop()
            #endif //uv
        }
        
        #if uv
            rl?.run(.In(timeout: 2))
        #endif //uv
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    enum TestError : Error {
        case E1
        case E2
    }
    
    #if !nodispatch
    func testSyncToDispatch() {
        let dispatchLoop = DispatchRunLoop()
        
        let result = dispatchLoop.sync {
            return "result"
        }
        
        XCTAssertEqual(result, "result")
        
        let fail = self.expectation(description: "failed")
        
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
        
        self.waitForExpectations(timeout: 0.1, handler: nil)
    }
    #endif //!nodispatch
    
    func testSyncToRunLoop() {
        var loop = freshLoop()
        
        XCTAssertFalse(RunLoop.reactive.current.map({$0.isEqual(to: loop)}) ?? false)
        
        let result = loop.sync {
            return "result"
        }
        
        XCTAssertEqual(result, "result")
        
        let fail = self.expectation(description: "failed")
        
        do {
            try loop.sync {
                defer {
                    (loop as? RunnableRunLoopProtocol)?.stop()
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
        
        self.waitForExpectations(timeout: 0.1, handler: nil)
    }
    
    #if uv
    func testUrgent() {
        let loop = UVRunLoop()
        
        var counter = 1
        
        let execute = self.expectation(description: "execute")
        loop.execute {
            XCTAssertEqual(2, counter)
            execute.fulfill()
            loop.stop()
        }
        
        let urgent = self.expectation(description: "urgent")
        loop.urgent {
            XCTAssertEqual(1, counter)
            counter += 1
            urgent.fulfill()
        }
        
        loop.run()
        
        self.waitForExpectations(timeout: 1, handler: nil)
    }
    
    #if !nodispatch
    func testBasicRelay() {
        let dispatchLoop = DispatchRunLoop()
        let loop = UVRunLoop()
        loop.relay = dispatchLoop
        
        let immediate = self.expectation(description: "immediate")
        let timer = self.expectation(description: "timer")
        
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
        
        let immediate2 = self.expectation(description: "immediate2")
        loop.execute {
            XCTAssertFalse(dispatchLoop.isEqualTo(RunLoop.current))
            immediate2.fulfill()
            loop.stop()
        }
        
        loop.run()
        
        self.waitForExpectations(timeout: 0.2, handler: nil)
    }
    
    func testAutorelay() {
        let immediate = self.expectation(description: "immediate")
        RunLoop.current.execute {
            immediate.fulfill()
        }
        self.waitForExpectations(timeout: 0.2, handler: nil)
        
        let timer = self.expectation(description: "timer")
        RunLoop.current.execute(timeout: Timeout(timeout: 0.1)) {
            timer.fulfill()
        }
        self.waitForExpectations(timeout: 0.2, handler: nil)
    }
    #endif //!nodispatch
    
    func testStopUV() {
        let rl = threadWithRunLoop(UVRunLoop.self).loop
        var counter = 0
        rl.execute {
            counter += 1
            rl.stop()
        }
        rl.execute {
            counter += 1
            rl.stop()
        }
        
        (RunLoop.current as? RunnableRunLoopProtocol)?.run(timeout: .In(timeout: 1))
        
        XCTAssert(counter == 1)
    }
    
    func testNestedUV() {
        let rl = threadWithRunLoop(UVRunLoop).loop
        let lvl1 = self.expectation(description: "lvl1")
        let lvl2 = self.expectation(description: "lvl2")
        let lvl3 = self.expectation(description: "lvl3")
        let lvl4 = self.expectation(description: "lvl4")
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
        self.waitForExpectations(timeout: 0.2, handler: nil)
    }
    
    func testNestedUVTimeoutRun() {
        let rl = threadWithRunLoop(UVRunLoop.self).loop
        var counter = 0
        
        rl.execute {
            rl.execute {
                counter += 1
            }
            rl.run(.In(timeout: 2))
            counter += 1
        }
        Thread.sleep(timeout: 1)
        XCTAssert(counter == 1)
        Thread.sleep(timeout: 1.5)
        XCTAssert(counter == 2)
        rl.stop()
    }
    
    #if nodispatch
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
    #endif //nodispatch
    #endif //uv
}

#if os(Linux)
extension RunLoopTests {
	static var allTests : [(String, (RunLoopTests) -> () throws -> Void)] {
        var tests:[(String, (RunLoopTests) -> () throws -> Void)] = [
			("testImmediateTimeout", testImmediateTimeout),
			("testNested", testNested),
			("testSyncToRunLoop", testSyncToRunLoop),
		]
        #if uv
            tests.append(("testUrgent", testUrgent))
            tests.append(("testUVExecute", testUVExecute))
            tests.append(("testStopUV", testStopUV))
            tests.append(("testNestedUV", testNestedUV))
            tests.append(("testNestedUVTimeoutRun", testNestedUVTimeoutRun))
            tests.append(("testMainUVTimeoutRun", testMainUVTimeoutRun))
        #endif
        #if !nodispatch
            tests.append(("testDispatchExecute", testDispatchExecute))
            tests.append(("testSyncToDispatch", testSyncToDispatch))
            #if uv
                tests.append(("testBasicRelay", testBasicRelay))
                tests.append(("testAutorelay", testAutorelay))
            #endif //uv
        #endif //!nodispatch
        
        return tests
	}
}
#endif
