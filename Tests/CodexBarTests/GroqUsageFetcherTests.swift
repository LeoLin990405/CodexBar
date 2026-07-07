import CodexBarCore
import Foundation
import Testing

struct GroqUsageFetcherTests {
    @Test
    func `parses prometheus scalar response`() throws {
        let json = """
        {
          "status": "success",
          "data": {
            "result": [
              { "value": [1710000000, "2.5"] },
              { "value": [1710000000, "1.5"] }
            ]
          }
        }
        """

        let value = try GroqUsageFetcher._parseScalarForTesting(Data(json.utf8))

        #expect(value == 4)
    }

    @Test
    func `fetch maps not found metrics endpoint to plan availability error`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(url.absoluteString.contains("/metrics/prometheus/api/v1/query"))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            let body = """
            {"error":{"message":"Not Found","type":"invalid_request_error","code":"not_found"}}
            """
            return (Data(body.utf8), response)
        }

        await #expect {
            _ = try await GroqUsageFetcher.fetchUsage(
                apiKey: "gsk_test",
                transport: transport)
        } throws: { error in
            guard case let GroqUsageError.metricsUnavailable(message) = error else { return false }
            return message.contains("Not Found")
                && message.contains("Enterprise-only feature")
        }
    }

    @Test
    func `snapshot maps prometheus rates to menu windows`() {
        let snapshot = GroqUsageSnapshot(
            requestRatePerSecond: 2,
            inputTokenRatePerSecond: 100,
            outputTokenRatePerSecond: 50,
            promptCacheHitRatePerSecond: 3,
            updatedAt: Date(timeIntervalSince1970: 1))
            .toUsageSnapshot()

        #expect(snapshot.identity?.providerID == .groq)
        #expect(snapshot.identity?.loginMethod == "Prometheus metrics")
        #expect(snapshot.primary?.resetDescription == "120 req/min")
        #expect(snapshot.secondary?.resetDescription == "9000 tok/min")
        #expect(snapshot.tertiary?.resetDescription == "180 cache/min")
    }
}
