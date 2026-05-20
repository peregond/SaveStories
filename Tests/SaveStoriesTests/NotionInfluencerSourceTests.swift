import XCTest
@testable import SaveMe

final class NotionInfluencerSourceTests: XCTestCase {
    func testParseProfilesExtractsNotionRichTextWithoutAnnotations() throws {
        let payload = """
        {
          "recordMap": {
            "block": {
              "page": {
                "value": {
                  "value": {
                    "type": "page",
                    "content": ["url", "italic-handle", "plain-handle"],
                    "properties": {
                      "title": [["Список инфлюенсеров"]]
                    }
                  }
                }
              },
              "url": {
                "value": {
                  "value": {
                    "properties": {
                      "title": [["https://www.instagram.com/brothersbonus/", [["a", "https://www.instagram.com/brothersbonus/"]]]]
                    }
                  }
                }
              },
              "italic-handle": {
                "value": {
                  "value": {
                    "properties": {
                      "title": [["@"], ["berthi", [["i"]]]]
                    }
                  }
                }
              },
              "plain-handle": {
                "value": {
                  "value": {
                    "properties": {
                      "title": [["@upngo____"]]
                    }
                  }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try NotionInfluencerSource.parseProfiles(from: payload),
            [
                "https://www.instagram.com/brothersbonus/",
                "https://www.instagram.com/berthi/",
                "https://www.instagram.com/upngo____/",
            ]
        )
    }

    func testExtractProfilesIgnoresHeadingsAndDeduplicates() {
        XCTAssertEqual(
            NotionInfluencerSource.extractProfiles(from: "Список инфлюенсеров @stake https://www.instagram.com/stake/ @stoffer__"),
            [
                "https://www.instagram.com/stake/",
                "https://www.instagram.com/stoffer__/",
            ]
        )
    }
}
