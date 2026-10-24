import XCTest
import Foundation
import CryptoKit
@testable import BridgeTransport

final class TransportTests: XCTestCase {
    func testLogoutSessionRotationRejectsOldIdentity() throws {
        let data=try JSONSerialization.data(withJSONObject:["server_url":"https://127.0.0.1:18865","gateway_key":String(repeating:"k",count:48),"certificate_sha256":String(repeating:"a",count:64)])
        let original=try ServerProfile(pairing:String(decoding:data,as:UTF8.self))
        let rotated=original.rotated()
        XCTAssertNotEqual(rotated.sessionID,original.sessionID)
        XCTAssertEqual(rotated.serverURL,original.serverURL)
        XCTAssertEqual(rotated.gatewayKey,original.gatewayKey)
    }
    func testPinnedSelfSignedHTTPSAndWrongKey() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let cert = directory.appendingPathComponent("server.crt").path
        let key = directory.appendingPathComponent("server.key").path
        let der = directory.appendingPathComponent("server.der")
        func run(_ arguments: [String]) throws {
            let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/env"); process.arguments=arguments
            process.standardOutput=FileHandle.standardOutput; process.standardError=FileHandle.standardError
            try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        }
        try run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1","-keyout",key,"-out",cert,"-subj","/CN=127.0.0.1","-addext","subjectAltName=IP:127.0.0.1","-addext","extendedKeyUsage=serverAuth","-addext","keyUsage=critical,digitalSignature,keyEncipherment","-addext","basicConstraints=critical,CA:FALSE"])
        try run(["openssl","x509","-in",cert,"-outform","DER","-out",der.path])
        let pin=SHA256.hash(data:try Data(contentsOf:der)).map { String(format:"%02x",$0) }.joined()
        let server=Process(); server.executableURL=URL(fileURLWithPath:"/usr/bin/env")
        server.arguments=["python3","Server/bridge.py","--directory",directory.appendingPathComponent("state").path,"--cert",cert,"--key",key,"--port","18865"]
        server.environment=ProcessInfo.processInfo.environment.merging(["CODEX_QUOTA_KEY":String(repeating:"k",count:48)]) { _,new in new }
        server.standardOutput=FileHandle.standardOutput; server.standardError=FileHandle.standardError
        try server.run(); defer { server.terminate(); server.waitUntilExit() }
        try await Task.sleep(for:.seconds(1))
        XCTAssertTrue(server.isRunning, "Python gateway must be alive")
        try run(["python3", "-c", "import socket; s=socket.create_connection(('127.0.0.1',18865),timeout=2); print('TCP localhost connected'); s.close()"])

        try run(["python3", "-c", "import urllib.request,ssl; r=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=" + String(reflecting:cert) + "))).open('https://127.0.0.1:18865/health',timeout=4); print(r.status)"])
        print("Python HTTPS probe completed")
        func profile(_ gatewayKey:String,_ certificate:String) throws -> ServerProfile {
            let data=try JSONSerialization.data(withJSONObject:["server_url":"https://127.0.0.1:18865","gateway_key":gatewayKey,"certificate_sha256":certificate])
            return try ServerProfile(pairing:String(decoding:data,as:UTF8.self))
        }
        let good=try BridgeClient(profile:profile(String(repeating:"k",count:48),pin),timeout:8)
        let (_,status)=try await good.request("health")
        XCTAssertEqual(status,200)
        do { _ = try await good.usage(); XCTFail("Unauthenticated quota must be login_required") }
        catch let error as ServiceError { XCTAssertEqual(error.status,409) }
        let wrongPin=try BridgeClient(profile:profile(String(repeating:"k",count:48),String(repeating:"0",count:64)),timeout:8)
        do { _ = try await wrongPin.request("health"); XCTFail("Wrong TLS pin must fail") } catch { }
        let wrongKey=try BridgeClient(profile:profile(String(repeating:"x",count:48),pin),timeout:8)
        do { _ = try await wrongKey.usage(); XCTFail("Wrong gateway key must fail") } catch { }
    }
}
