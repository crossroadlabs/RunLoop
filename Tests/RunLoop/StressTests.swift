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
            let thAndLoop:(thread: Thread, loop:UVRunLoop) = threadWithRunLoop()
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
