import AuthenticationServices
import Foundation
import Testing
@testable import AmparoShared

@Suite("Autofill matcher")
struct AutofillMatcherTests {
    @Test(arguments: [
        ("bank.example.com", "bank.example.com", true),
        ("https://bank.example.com/login", "bank.example.com", true),
        ("www.bank.example.com", "bank.example.com", true),          // sub → stored
        ("bank.example.com", "www.bank.example.com", true),          // stored → sub
        ("HTTPS://BANK.EXAMPLE.COM", "bank.example.com", true),
        ("electric.example.com", "bank.example.com", false),
        ("notbank.example.com", "bank.example.com", false),          // no partial-label match
        ("bank.example.com", "", false),
    ])
    func matching(identifier: String, domain: String, expected: Bool) {
        #expect(AutofillMatcher.matches(serviceIdentifier: identifier, domain: domain) == expected)
    }

    @Test func nilDomainNeverMatches() {
        #expect(!AutofillMatcher.matches(serviceIdentifier: "bank.example.com", domain: nil))
    }

    @Test(arguments: [
        ("https://bank.example.com/login?x=1", "bank.example.com"),
        ("bank.example.com", "bank.example.com"),
        ("  Bank.Example.Com  ", "bank.example.com"),
    ])
    func hostExtraction(identifier: String, expected: String?) {
        #expect(AutofillMatcher.host(from: identifier) == expected)
    }

    @Test func emptyIdentifierHasNoHost() {
        #expect(AutofillMatcher.host(from: "") == nil)
    }
}

@Suite("Identity mapping")
struct IdentityMappingTests {
    @Test func mapsOnlyTilesWithDomainAndUsername() {
        let tiles = [
            MemberTile(id: "c1", displayName: "Bank", sortIndex: 1,
                       domain: "bank.example.com", username: "grandma@example.com"),
            MemberTile(id: "c2", displayName: "NoDomain", sortIndex: 2,
                       domain: nil, username: "user"),
            MemberTile(id: "c3", displayName: "NoUser", sortIndex: 3,
                       domain: "electric.example.com", username: nil),
        ]
        let identities = CredentialIdentityRegistrar.identities(from: tiles)
        #expect(identities.count == 1)
        let identity = identities[0]
        #expect(identity.serviceIdentifier.identifier == "bank.example.com")
        #expect(identity.serviceIdentifier.type == .domain)
        #expect(identity.user == "grandma@example.com")
        #expect(identity.recordIdentifier == "c1")
    }
}
