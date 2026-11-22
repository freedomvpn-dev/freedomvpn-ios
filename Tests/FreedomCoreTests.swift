import XCTest

final class FreedomCoreTests: XCTestCase {
    func testParsesPanelXrayJsonArray() throws {
        let body = """
        [{"remarks":"⚡ Авто — лучший сервер","outbounds":[{"protocol":"vless","tag":"proxy"}]},
         {"remarks":"🇳🇱 Netherlands","outbounds":[{"protocol":"vless","tag":"proxy"}]}]
        """
        let servers = try SubscriptionParser.parseServers(Data(body.utf8))
        XCTAssertEqual(servers.map(\.name), ["⚡ Авто — лучший сервер", "🇳🇱 Netherlands"])
        XCTAssertNotEqual(servers[0].id, servers[1].id)
        // Same input gives the same id (selection survives a refresh).
        XCTAssertEqual(try SubscriptionParser.parseServers(Data(body.utf8)).map(\.id), servers.map(\.id))
    }

    func testRejectsBase64Subscription() {
        XCTAssertThrowsError(try SubscriptionParser.parseServers(Data("dmxlc3M6Ly8=".utf8)))
    }

    func testParsesUsageHeader() {
        let usage = SubscriptionParser.parseUsage("upload=10; download=20; total=0; expire=1765000000")
        XCTAssertEqual(usage?.usedBytes, 30)
        XCTAssertEqual(usage?.totalBytes, 0)
        XCTAssertEqual(usage?.expire, 1_765_000_000)
        XCTAssertNil(SubscriptionParser.parseUsage("upload=1; expire=0")?.expire)
    }

    func testDecodesBase64Title() {
        XCTAssertEqual(SubscriptionParser.decodeTitle("base64:RnJlZWRvbSBWUE4="), "Freedom VPN")
        XCTAssertEqual(SubscriptionParser.decodeTitle("Plain"), "Plain")
    }

    func testTunnelConfigGetsOurSocksInboundOnly() throws {
        let raw = """
        {"remarks":"x","log":{"access":"/var/log/a.log"},"inbounds":[{"protocol":"socks","port":10808},{"protocol":"http","port":10809}],
         "outbounds":[{"protocol":"vless","tag":"proxy"}],"routing":{"rules":[]}}
        """
        let patched = try XrayConfigPatcher.prepareForTunnel(raw, socksPort: 12345)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(patched.utf8)) as? [String: Any])
        let inbounds = try XCTUnwrap(root["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.count, 1)
        XCTAssertEqual(inbounds[0]["port"] as? Int, 12345)
        XCTAssertEqual(inbounds[0]["listen"] as? String, "127.0.0.1")
        XCTAssertNil((root["log"] as? [String: Any])?["access"])
        XCTAssertNil(root["remarks"])
        XCTAssertNotNil(root["routing"])
    }

    func testTunnelConfigNeedsOutbounds() {
        XCTAssertThrowsError(try XrayConfigPatcher.prepareForTunnel(#"{"outbounds":[]}"#))
        XCTAssertThrowsError(try XrayConfigPatcher.prepareForTunnel("[]"))
    }

    func testHwidMatchesAndroidFormat() {
        let a = HWID.value(secret: "secret", host: "Sub.Example.com")
        XCTAssertEqual(a.count, 32)
        XCTAssertNotNil(a.range(of: "^[a-f0-9]{32}$", options: .regularExpression))
        XCTAssertEqual(a, HWID.value(secret: "secret", host: "sub.example.com"))
        XCTAssertNotEqual(a, HWID.value(secret: "secret", host: "other.example.net"))
    }

    func testHeaderValueIsPrintableAscii() {
        XCTAssertEqual(HWID.headerValue("iPhone™ 15\n"), "iPhone 15")
    }
}
