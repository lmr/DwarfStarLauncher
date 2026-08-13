import XCTest
import Foundation
@testable import App

final class DownloadTargetsTests: XCTestCase {

    func testAllCasesCoverExpectedCount() {
        XCTAssertEqual(DownloadTarget.allCases.count, 13)
    }

    func testCategoryMapping() {
        XCTAssertEqual(DownloadTarget.ds4fQ2.category, .deepSeekFlash)
        XCTAssertEqual(DownloadTarget.ds4fDspark.category, .deepSeekFlash)
        XCTAssertEqual(DownloadTarget.proQ2Imatrix.category, .proModels)
        XCTAssertEqual(DownloadTarget.proQ4Split.category, .proModels)
        XCTAssertEqual(DownloadTarget.glmUnslothQ4.category, .glmModels)
        XCTAssertEqual(DownloadTarget.glmAntirezQ4.category, .glmModels)
    }

    func testRepoMapping() {
        XCTAssertEqual(DownloadTarget.ds4fQ2.repo, "antirez/deepseek-v4-gguf")
        XCTAssertEqual(DownloadTarget.proQ4Split.repo, "antirez/deepseek-v4-gguf")
        XCTAssertEqual(DownloadTarget.glmUnslothQ4.repo, "unsloth/GLM-5.2-GGUF")
        XCTAssertEqual(DownloadTarget.glmAntirezIQ2XXS.repo, "antirez/GLM-5.2-GGUF")
    }

    func testMultiFileTargets() {
        XCTAssertEqual(DownloadTarget.proQ4Split.files.count, 2)
        XCTAssertEqual(DownloadTarget.glmUnslothQ4.files.count, 11)
    }

    func testGlmUnslothShardNames() {
        let files = DownloadTarget.glmUnslothQ4.files
        XCTAssertEqual(files[0].localName, "GLM-5.2-UD-Q4_K_XL-00001-of-00011.gguf")
        XCTAssertEqual(files[10].localName, "GLM-5.2-UD-Q4_K_XL-00011-of-00011.gguf")
        XCTAssertEqual(files[0].remoteName, "UD-Q4_K_XL/GLM-5.2-UD-Q4_K_XL-00001-of-00011.gguf")
    }

    func testExpectedTotalSizeIsSumOfFiles() {
        for target in DownloadTarget.allCases {
            XCTAssertGreaterThan(target.expectedTotalSize, 0)
            XCTAssertEqual(target.expectedTotalSize, target.files.reduce(0) { $0 + $1.size })
        }
    }

    func testFilenameReturnsFirstLocalName() {
        XCTAssertEqual(DownloadTarget.proQ4Split.filename, "DeepSeek-V4-Pro-Q4K-Layers00-30.gguf")
        XCTAssertEqual(DownloadTarget.ds4fQ2.filename, DownloadTarget.ds4fQ2.files[0].localName)
    }

    func testDisplayNameNonEmptyForAllCases() {
        for target in DownloadTarget.allCases {
            XCTAssertFalse(target.displayName.isEmpty)
        }
    }

    func testDescriptionContainsDisplayNameAndSize() {
        let description = DownloadTarget.ds4fQ2.description
        XCTAssertTrue(description.contains("DeepSeek Flash Q2"))
        XCTAssertTrue(description.contains("GB") || description.contains("MB"))
    }
}
