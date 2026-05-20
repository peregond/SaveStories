import XCTest
@testable import SaveMe

final class NotionRoutingRulesSourceTests: XCTestCase {
    func testNormalizeRulesCleansCommentsAndExpandsAliases() {
        let input = """
        Правила для сортировки
        *nadir_bs* = Australia (AU) 🇦🇺 INF
        jimisworld (без зуба) = Australia (AU) 🇦🇺 INF
        ryanjslots : ryanjstewart1 = Germany (DE) 🇩🇪 INF
        """

        XCTAssertEqual(
            NotionRoutingRulesSource.normalizeRules(input),
            """
            nadir_bs = Australia (AU) 🇦🇺 INF
            jimisworld = Australia (AU) 🇦🇺 INF
            ryanjslots = Germany (DE) 🇩🇪 INF
            ryanjstewart1 = Germany (DE) 🇩🇪 INF
            """
        )
    }

    func testParseRulesExtractsNotionRichTextWithoutAnnotations() throws {
        let payload = """
        {
          "recordMap": {
            "block": {
              "page": {
                "value": {
                  "value": {
                    "properties": {
                      "title": [["Правила для сортировки"]]
                    }
                  }
                }
              },
              "rule": {
                "value": {
                  "value": {
                    "properties": {
                      "title": [["ryanjslots : "], ["ryanjstewart1", [["i"]]], [" = Germany (DE) 🇩🇪 INF"]]
                    }
                  }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try NotionRoutingRulesSource.parseRules(from: payload),
            """
            ryanjslots = Germany (DE) 🇩🇪 INF
            ryanjstewart1 = Germany (DE) 🇩🇪 INF
            """
        )
    }
}
