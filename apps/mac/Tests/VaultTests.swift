import XCTest
import CryptoKit
@testable import meOS

/// Zero-knowledge vault: proves data is unreadable without the passphrase, that a
/// fresh device can unlock from the server metadata alone, and that recovery and
/// passphrase changes behave.
final class VaultTests: XCTestCase {

    private let financeJSON = #"{"txns":[{"amount":200,"cat":"auto"}]}"#.data(using: .utf8)!

    func testVerifyAcceptsOnlyTheRealPassphrase() throws {
        // Re-auth in front of a wipe: right pass yes, anything else no.
        let v = Vault()
        _ = try v.setup(passphrase: "correct-pass-123")
        XCTAssertTrue(v.verify(passphrase: "correct-pass-123"))
        XCTAssertFalse(v.verify(passphrase: "correct-pass-124"))
        XCTAssertFalse(v.verify(passphrase: ""))
    }

    func testVerifyDoesNotUnlockOrRelockTheVault() throws {
        let a = Vault()
        let (meta, _) = try a.setup(passphrase: "correct-pass-123")

        // A locked device stays locked, whatever it's asked.
        let b = Vault()
        b.adoptMeta(meta)
        XCTAssertTrue(b.verify(passphrase: "correct-pass-123"))
        XCTAssertFalse(b.isUnlocked, "verify must never unlock as a side effect")

        // An unlocked one stays unlocked after a wrong guess.
        XCTAssertFalse(a.verify(passphrase: "nope"))
        XCTAssertTrue(a.isUnlocked)
    }

    func testVerifyIsFalseWithoutMeta() {
        XCTAssertFalse(Vault().verify(passphrase: "anything"))
    }

    func testEnvelopeHidesPlaintext() throws {
        let v = Vault()
        _ = try v.setup(passphrase: "berjil-strong-pass")
        let env = try v.sealValue(financeJSON, key: "myos.finance")
        let s = String(data: env, encoding: .utf8)!
        XCTAssertFalse(s.contains("auto"), "ciphertext must not leak plaintext")
        XCTAssertFalse(s.contains("200"))
        XCTAssertTrue(s.contains("\"ct\""), "should be a {v,ct} envelope")
    }

    func testFreshDeviceUnlocksFromMetaOnly() throws {
        // Device A sets up and seals a value.
        let a = Vault()
        let (meta, _) = try a.setup(passphrase: "correct-pass-123")
        let env = try a.sealValue(financeJSON, key: "myos.finance")
        let envObj = try JSONSerialization.jsonObject(with: env) as! [String: Any]

        // Device B has only the server meta.
        let b = Vault()
        b.adoptMeta(meta)
        XCTAssertFalse(b.isUnlocked)
        XCTAssertThrowsError(try b.unlock(passphrase: "wrong")) // wrong pass rejected
        XCTAssertFalse(b.isUnlocked)
        try b.unlock(passphrase: "correct-pass-123")
        XCTAssertTrue(b.isUnlocked)
        XCTAssertEqual(try b.openValue(envObj, key: "myos.finance"), financeJSON)
    }

    func testSlotBinding() throws {
        let v = Vault()
        _ = try v.setup(passphrase: "pass-pass-pass")
        let env = try v.sealValue(financeJSON, key: "myos.finance")
        let envObj = try JSONSerialization.jsonObject(with: env) as! [String: Any]
        XCTAssertThrowsError(try v.openValue(envObj, key: "myos.journal"),
                             "an envelope must not decrypt under a different key")
    }

    func testRecoveryCodeUnlocks() throws {
        let a = Vault()
        let (meta, code) = try a.setup(passphrase: "some-pass-word")
        let env = try a.sealValue(financeJSON, key: "myos.finance")
        let envObj = try JSONSerialization.jsonObject(with: env) as! [String: Any]

        let b = Vault(); b.adoptMeta(meta)
        try b.unlock(recoveryCode: code)
        XCTAssertEqual(try b.openValue(envObj, key: "myos.finance"), financeJSON)
        // Case/format tolerance.
        let c = Vault(); c.adoptMeta(meta)
        try c.unlock(recoveryCode: code.lowercased())
        XCTAssertTrue(c.isUnlocked)
    }

    func testChangePassphraseKeepsDataAndRecovery() throws {
        let a = Vault()
        let (meta, code) = try a.setup(passphrase: "old-pass-word")
        let env = try a.sealValue(financeJSON, key: "myos.finance")
        let envObj = try JSONSerialization.jsonObject(with: env) as! [String: Any]
        let newMeta = try a.rewrap(newPassphrase: "new-pass-word")

        let b = Vault(); b.adoptMeta(newMeta)
        XCTAssertThrowsError(try b.unlock(passphrase: "old-pass-word"))
        try b.unlock(passphrase: "new-pass-word")
        XCTAssertEqual(try b.openValue(envObj, key: "myos.finance"), financeJSON)

        // Recovery still works after a passphrase change.
        let c = Vault(); c.adoptMeta(newMeta)
        try c.unlock(recoveryCode: code)
        XCTAssertTrue(c.isUnlocked)
    }

    func testPlaintextKeyPolicy() throws {
        let v = Vault()
        XCTAssertFalse(v.shouldEncrypt("myos.crypto"))
        XCTAssertFalse(v.shouldEncrypt("myos.ai.routes"))
        XCTAssertTrue(v.shouldEncrypt("myos.finance"))
        XCTAssertTrue(v.shouldEncrypt("myos.journal"))
    }

    func testKDFDeterministicAndSalted() throws {
        let salt1 = meOSCrypto.newSalt()
        let salt2 = meOSCrypto.newSalt()
        let k1 = try meOSCrypto.deriveKey(from: "abc", salt: salt1, iterations: 10_000)
        let k1b = try meOSCrypto.deriveKey(from: "abc", salt: salt1, iterations: 10_000)
        let k2 = try meOSCrypto.deriveKey(from: "abc", salt: salt2, iterations: 10_000)
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k1b.withUnsafeBytes { Data($0) })
        XCTAssertNotEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
    }

    /// The off-main-thread split (`derive*` pure, `adopt*` on the actor) must
    /// derive exactly what the inline path derives: a fresh device adopting a
    /// derived setup unlocks and reads, and a wrong passphrase still fails.
    func testDerivedSetupAdoptsIntoWorkingVault() throws {
        let m = try Vault.deriveSetup(passphrase: "off-main-pass-1")
        let v = Vault()
        XCTAssertFalse(v.isUnlocked)
        v.adoptSetup(m)
        XCTAssertTrue(v.isUnlocked)
        let env = try v.sealValue(financeJSON, key: "myos.finance")
        let envObj = try JSONSerialization.jsonObject(with: env) as! [String: Any]
        XCTAssertEqual(try v.openValue(envObj, key: "myos.finance"), financeJSON)

        // Same meta, derived unlock path.
        let other = Vault(); other.adoptMeta(m.meta)
        let dekData = try Vault.deriveUnlockDEK(passphrase: "off-main-pass-1", meta: m.meta)
        try other.adoptUnwrapped(dekData, meta: m.meta)
        XCTAssertTrue(other.isUnlocked)
        XCTAssertEqual(try other.openValue(envObj, key: "myos.finance"), financeJSON)

        let recovery = Vault(); recovery.adoptMeta(m.meta)
        let recData = try Vault.deriveUnlockDEK(recoveryCode: m.recoveryCode, meta: m.meta)
        try recovery.adoptUnwrapped(recData, meta: m.meta)
        XCTAssertTrue(recovery.isUnlocked)

        XCTAssertThrowsError(try Vault.deriveUnlockDEK(passphrase: "wrong-pass", meta: m.meta))
    }
}
