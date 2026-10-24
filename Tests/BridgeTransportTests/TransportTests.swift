import XCTest
import Foundation
import CryptoKit
@testable import BridgeTransport

final class TransportTests: XCTestCase {
    func testPinnedSelfSignedHTTPSAndWrongKey() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let cert = directory.appendingPathComponent("server.crt").path
        let key = directory.appendingPathComponent("server.key").path
        let der = directory.appendingPathComponent("server.der")
        func run(_ arguments: [String]) throws {
            let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/env"); process.arguments=arguments
            process.standardOutput=FileHandle.nullDevice; process.standardError=FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        }
        try run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1","-keyout",key,"-out",cert,"-subj","/CN=127.0.0.1","-addext","subjectAltName=IP:127.0.0.1"])
        try run(["openssl","x509","-in",cert,"-outform","DER","-out",der.path])
        let pin=SHA256.hash(data:try Data(contentsOf:der)).map { String(format:"%02x",$0) }.joined()
        let server=Process(); server.executableURL=URL(fileURLWithPath:"/usr/bin/env")
        server.arguments=["python3","Server/bridge.py","--directory",directory.appendingPathComponent("state").path,"--cert",cert,"--key",key,"--port","18865"]
        server.environment=ProcessInfo.processInfo.environment.merging(["CODEX_QUOTA_KEY":String(repeating:"k",count:48)]) { _,new in new }
        server.standardOutput=FileHandle.nullDevice; server.standardError=FileHandle.nullDevice
        try server.run(); defer { server.terminate(); server.waitUntilExit() }
        try await Task.sleep(for:.seconds(1))
        func profile(_ gatewayKey:String,_ certificate:String) throws -> ServerProfile {
            let data=try JSONSerialization.data(withJSONObject:["server_url":"https://127.0.0.1:18865","gateway_key":gatewayKey,"certificate_sha256":certificate])
            return try ServerProfile(pairing:String(decoding:data,as:UTF8.self))
        }
        let good=try BridgeClient(profile:profile(String(repeating:"k",count:48),pin))
        let (_,status)=try await good.request("health")
        XCTAssertEqual(status,200)
        do { _ = try await good.usage(); XCTFail("Unauthenticated quota must be login_required") }
        catch let error as ServiceError { XCTAssertEqual(error.status,409) }
        let wrongPin=try BridgeClient(profile:profile(String(repeating:"k",count:48),String(repeating:"0",count:64)))
        do { _ = try await wrongPin.request("health"); XCTFail("Wrong TLS pin must fail") } catch { }
        let wrongKey=try BridgeClient(profile:profile(String(repeating:"x",count:48),pin))
        do { _ = try await wrongKey.usage(); XCTFail("Wrong gateway key must fail") } catch { }
    }
}
