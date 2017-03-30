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
    #if uv
    func testUVEquatable() {
        let loop1 = UVRunLoop()
        let loop2 = UVRunLoop()
        
        XCTAssert(loop1 != loop2)
        XCTAssert(loop1 == loop1)
        XCTAssert(loop2 == loop2)
    }
    #endif //uv
    
    #if !nodispatch
    func testDispatchEquatable() {
        let loop1 = DispatchRunLoop()
        let loop2 = DispatchRunLoop()
        
        XCTAssert(loop1 != loop2)
        XCTAssert(loop1 == loop1)
        XCTAssert(loop2 == loop2)
    }
    #endif //!nodispatch
}

#if os(Linux)
extension EquatableTests {
	static var allTests : [(String, (EquatableTests) -> () throws -> Void)] {
        var tests:[(String, (EquatableTests) -> () throws -> Void)] = []
        #if uv
            tests.append(("testUVEquatable", testUVEquatable))
        #endif //!nodispatch
        #if !nodispatch
            tests.append(("testDispatchEquatable", testDispatchEquatable))
        #endif //!nodispatch
		return tests
	}
}
#endif
