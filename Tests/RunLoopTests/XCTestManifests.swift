import XCTest

#if os(Linux)
public func allTests() -> [XCTestCaseEntry] {
	 return [
		testCase(EquatableTests.allTests),
		testCase(RunLoopTests.allTests),
		testCase(SemaphoreTests.allTests),
		testCase(StressTests.allTests)
	]
}
#endif