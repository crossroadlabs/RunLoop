//
//  EquatableTests.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/22/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest
import Boilerplate

@testable import RunLoop

class EquatableTests : XCTestCase {
    
    func testUVEquatable() {
        let loop1 = UVRunLoop()
        let loop2 = UVRunLoop()
        
        XCTAssert(loop1 != loop2)
        XCTAssert(loop1 == loop1)
        XCTAssert(loop2 == loop2)
    }
    
    #if !os(Linux) || dispatch
    func testDispatchEquatable() {
        let loop1 = DispatchRunLoop()
        let loop2 = DispatchRunLoop()
        
        XCTAssert(loop1 != loop2)
        XCTAssert(loop1 == loop1)
        XCTAssert(loop2 == loop2)
    }
    #endif
}
