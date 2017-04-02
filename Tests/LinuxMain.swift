import XCTest

import RunLoopTests

var tests = [XCTestCaseEntry]()

tests += RunLoopTests.allTests()

XCTMain(tests)
