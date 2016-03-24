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


class StressTests: XCTestCase {
    let threadCount = 100
    let taskCount = 1000
    
    func testStressUV() {
        let lock = NSLock()
        var counter = 0
        
        let task = {
            lock.lock()
            counter += 1
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
        
        (RunLoop.current as? RunnableRunLoopType)?.run(.In(timeout: 10), once: false)
        
        print("Counter \(counter), maxValue: \(threadCount*taskCount)")
        
        XCTAssert(counter == threadCount*taskCount, "Timeout")
    }
    
    #if !os(Linux) || dispatch
    func testStressDispatch() {
        let lock = NSLock()
        var counter = 0
        
        let task = {
            lock.lock()
            counter += 1
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
        
        (RunLoop.current as? RunnableRunLoopType)?.run(.In(timeout: 10), once: false)
        
        print("Counter \(counter), maxValue: \(threadCount*taskCount)")
        
        XCTAssert(counter == threadCount*taskCount, "Timeout")
    }
    #endif
}
