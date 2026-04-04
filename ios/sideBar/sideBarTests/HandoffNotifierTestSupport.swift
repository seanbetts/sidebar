import XCTest

func assertSingleHandoffDelivery(
    in testCase: XCTestCase,
    description: String,
    observe: (@escaping () -> Void) -> AnyObject,
    post: () -> Void,
    removeObserver: (AnyObject) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expectation = testCase.expectation(description: description)
    var callbackCount = 0
    let observer = observe {
        callbackCount += 1
        expectation.fulfill()
    }

    post()
    testCase.wait(for: [expectation], timeout: 1.0)

    let settled = testCase.expectation(description: "\(description) settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        XCTAssertEqual(callbackCount, 1, file: file, line: line)
        settled.fulfill()
    }

    testCase.wait(for: [settled], timeout: 0.2)
    removeObserver(observer)
}
