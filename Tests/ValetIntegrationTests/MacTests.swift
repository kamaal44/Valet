//
//  MacTests.swift
//  Valet
//
//  Created by Dan Federman and Eric Muller on 9/16/17.
//  Copyright © 2017 Square, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import XCTest

@testable import Valet

#if os(macOS)
class ValetMacTests: XCTestCase
{
    // This test verifies that we are neutralizing the zero-day Mac OS X Access Control List vulnerability.
    // Whitepaper: https://drive.google.com/file/d/0BxxXk1d3yyuZOFlsdkNMSGswSGs/view
    // Square Corner blog post: https://corner.squareup.com/2015/06/valet-beats-the-ox-x-keychain-access-control-list-zero-day-vulnerability.html
    func test_setStringForKey_neutralizesMacOSAccessControlListVuln()
    {
        let valet = Valet.valet(with: Identifier(nonEmpty: "MacOSVulnTest")!, accessibility: .whenUnlocked)
        let vulnKey = "KeepIt"
        let vulnValue = "Secret"
        valet.removeObject(forKey: vulnKey)

        guard let keychainQuery = valet.keychainQuery else {
            XCTFail()
            return
        }
        var query = keychainQuery
        query[kSecAttrAccount as String] = vulnKey

        var accessList: SecAccess?
        var trustedAppSelf: SecTrustedApplication?
        var trustedAppSystemUIServer: SecTrustedApplication?

        XCTAssertEqual(SecTrustedApplicationCreateFromPath(nil, &trustedAppSelf), errSecSuccess)
        XCTAssertEqual(SecTrustedApplicationCreateFromPath("/System/Library/CoreServices/SystemUIServer.app", &trustedAppSystemUIServer), errSecSuccess);
        let trustedList = [trustedAppSelf!, trustedAppSystemUIServer!] as NSArray?

        // Add an entry to the keychain with an access control list.
        XCTAssertEqual(SecAccessCreate("Access Control List" as CFString, trustedList, &accessList), errSecSuccess)
        var accessListQuery = query
        accessListQuery[kSecAttrAccess as String] = accessList
        accessListQuery[kSecValueData as String] = Data(vulnValue.utf8)
        XCTAssertEqual(SecItemAdd(accessListQuery as CFDictionary, nil), errSecSuccess)

        // The potentially vulnerable keychain item should exist in our Valet now.
        XCTAssertTrue(valet.containsObject(forKey: vulnKey))

        // Obtain a reference to the vulnerable keychain entry.
        query[kSecReturnRef as String] = true
        query[kSecReturnAttributes as String] = true
        var vulnerableEntryReference: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &vulnerableEntryReference), errSecSuccess)

        guard let vulnerableKeychainEntry = vulnerableEntryReference as! NSDictionary? else {
            XCTFail()
            return
        }
        guard let vulnerableValueRef = vulnerableKeychainEntry[kSecValueRef as String] else {
            XCTFail()
            return
        }

        let queryWithVulnerableReference = [
            kSecValueRef as String: vulnerableValueRef
            ] as CFDictionary
        // Demonstrate that the item is accessible with the reference.
        XCTAssertEqual(SecItemCopyMatching(queryWithVulnerableReference, nil), errSecSuccess)

        // Update the vulnerable value with Valet - we should have deleted the existing item, making the entry no longer vulnerable.
        let updatedValue = "Safe"
        XCTAssertTrue(valet.set(string: updatedValue, forKey: vulnKey))

        // We should no longer be able to access the keychain item via the ref.
        let queryWithVulnerableReferenceAndAttributes = [
            kSecValueRef as String: vulnerableValueRef,
            kSecReturnAttributes as String: true
            ] as CFDictionary
        XCTAssertEqual(SecItemCopyMatching(queryWithVulnerableReferenceAndAttributes, nil), errSecItemNotFound)

        // If you add a breakpoint here then manually inspect the keychain via Keychain.app (search for "MacOSVulnTest"), "xctest" should be the only member of the Access Control list.
        // This is not be the case upon setting a breakpoint and inspecting before the valet.setString(, forKey:) call above.
    }

    func test_withExplicitlySet_identifierHasExplicitlySetIdentifier() {
        let explicitlySetIdentifier = Identifier(nonEmpty: #function)!
        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertEqual($0.keychainQuery?[kSecAttrService as String], explicitlySetIdentifier.description)
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertEqual($0.keychainQuery?[kSecAttrService as String], explicitlySetIdentifier.description)
        }

        XCTAssertEqual(
            Valet.iCloudValet(withExplicitlySet: explicitlySetIdentifier, accessibility: .whenUnlocked).keychainQuery?[kSecAttrService as String],
            explicitlySetIdentifier.description)

        guard testEnvironmentIsSigned() else {
            return
        }

        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertEqual($0.keychainQuery?[kSecAttrService as String], explicitlySetIdentifier.description)
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertEqual($0.keychainQuery?[kSecAttrService as String], explicitlySetIdentifier.description)
        }
    }

    func test_withExplicitlySet_canAccessKeychain() {
        let explicitlySetIdentifier = Identifier(nonEmpty: #function)!
        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertTrue($0.canAccessKeychain())
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertTrue($0.canAccessKeychain())
        }

        XCTAssertEqual(
            Valet.iCloudValet(withExplicitlySet: explicitlySetIdentifier, accessibility: .whenUnlocked).keychainQuery?[kSecAttrService as String],
            explicitlySetIdentifier.description)

        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertTrue($0.canAccessKeychain())
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertTrue($0.canAccessKeychain())
        }
    }

    func test_withExplicitlySet_canReadWrittenString() {
        let explicitlySetIdentifier = Identifier(nonEmpty: #function)!
        let key = "key"
        let passcode = "12345"

        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertTrue($0.set(string: passcode, forKey: key))
            XCTAssertEqual($0.string(forKey: key), passcode)
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: false).forEach {
            XCTAssertTrue($0.set(string: passcode, forKey: key))
            XCTAssertEqual($0.string(forKey: key), passcode)
        }

        XCTAssertEqual(
            Valet.iCloudValet(withExplicitlySet: explicitlySetIdentifier, accessibility: .whenUnlocked).keychainQuery?[kSecAttrService as String],
            explicitlySetIdentifier.description)

        guard testEnvironmentIsSigned() else {
            return
        }

        Valet.permutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertTrue($0.set(string: passcode, forKey: key))
            XCTAssertEqual($0.string(forKey: key), passcode)
        }

        Valet.iCloudPermutations(withExplictlySet: explicitlySetIdentifier, shared: true).forEach {
            XCTAssertTrue($0.set(string: passcode, forKey: key))
            XCTAssertEqual($0.string(forKey: key), passcode)
        }
    }

    // MARK: Migration - PreCatalina

    func test_migrateObjectsFromPreCatalina_migratesDataWrittenPreCatalina() {
        guard #available(macOS 10.15, *) else {
            return
        }
        guard testEnvironmentIsSigned() else {
            return
        }

        let valet = Valet.valet(with: Identifier(nonEmpty: "PreCatalinaTest")!, accessibility: .afterFirstUnlock)
        guard var preCatalinaWriteQuery = valet.keychainQuery else {
            XCTFail()
            return
        }
        preCatalinaWriteQuery[kSecUseDataProtectionKeychain as String] = nil

        let key = "PreCatalinaKey"
        let object = Data("PreCatalinaValue".utf8)
        preCatalinaWriteQuery[kSecAttrAccount as String] = key
        preCatalinaWriteQuery[kSecValueData as String] = object

        // Make sure the item is not in the keychain before we start this test
        SecItemDelete(preCatalinaWriteQuery as CFDictionary)

        XCTAssertEqual(SecItemAdd(preCatalinaWriteQuery as CFDictionary, nil), errSecSuccess)
        XCTAssertNil(valet.object(forKey: key))
        XCTAssertEqual(valet.migrateObjectsFromPreCatalina(), .success)
        XCTAssertEqual(valet.object(forKey: key), object)
    }

}
#endif
