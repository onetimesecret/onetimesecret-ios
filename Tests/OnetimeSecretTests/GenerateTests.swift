import Foundation
import Testing
@testable import OnetimeSecret

@Suite("Generate")
struct GenerateTests {
    @Test("generate claims the generated value from the receipt by default")
    func generateClaimsValue() async throws {
        let transport = MockTransport(fixture: "generate")
        transport.enqueue(fixture: "receipt_generated")
        let client = OnetimeSecretClient.guest(transport)

        let result = try await client.secrets.generate(
            options: GenerateOptions(length: 20, characterSets: CharacterSets(symbols: false))
        )

        #expect(transport.requests.count == 2)
        let create = transport.requests[0]
        #expect(create.url.path == "/api/v2/guest/secret/generate")
        let secret = try #require(create.jsonBody?["secret"] as? [String: Any])
        #expect(secret["kind"] as? String == "generate")
        #expect(secret["length"] as? Int == 20)
        #expect((secret["character_sets"] as? [String: Any])?["symbols"] as? Bool == false)
        #expect(secret["secret"] == nil)

        let fetch = transport.requests[1]
        #expect(fetch.method == .get)
        #expect(fetch.url.path == "/api/v2/guest/receipt/\(result.receipt.identifier)")

        #expect(result.value == "bvpPtGPgtLd7ApUVqdEn")
        #expect(result.receipt.generatedValue == "bvpPtGPgtLd7ApUVqdEn")
        #expect(result.receipt.viewCount == 0)
        #expect(result.receipt.kind == .generate)
    }

    @Test("generate survives a failed claim and reports it")
    func generateClaimFails() async throws {
        let transport = MockTransport(fixture: "generate")
        transport.enqueue(.response(TransportResponse(statusCode: 429, body: Data(#"{"error":"slow down"}"#.utf8))))
        let client = OnetimeSecretClient.guest(transport)

        let result = try await client.secrets.generate()

        #expect(result.value == nil)
        #expect(result.claimFailure == "slow down")
        #expect(result.receipt.shortID == "receipt0")
        #expect(!result.description.contains("bvpPtGPgtLd7ApUVqdEn"))
    }

    @Test("generate can skip the claim")
    func generateWithoutClaim() async throws {
        let transport = MockTransport(fixture: "generate")
        let client = OnetimeSecretClient.guest(transport)

        let result = try await client.secrets.generate(options: GenerateOptions(claimValue: false))

        #expect(transport.requests.count == 1)
        #expect(result.value == nil)
    }

    @Test("generate validates length", arguments: [3, 129, 0, -1])
    func generateLength(length: Int) async {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.secrets.generate(options: GenerateOptions(length: length))
        }
        #expect(transport.requests.isEmpty)
    }
}
