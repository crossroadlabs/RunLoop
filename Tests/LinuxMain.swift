import XCTest

@testable import RunLoopTestSuite

XCTMain([
	testCase(EquatableTests.allTests),
	testCase(RunLoopTests.allTests),
	testCase(SemaphoreTests.allTests),
	testCase(StressTests.allTests),
])