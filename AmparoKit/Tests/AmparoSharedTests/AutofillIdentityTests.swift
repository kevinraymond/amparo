import AuthenticationServices
import Foundation
import Testing
@testable import AmparoShared

@Suite("Autofill matcher")
struct AutofillMatcherTests {
    @Test(arguments: [
        ("banco.example.com", "banco.example.com", true),
        ("https://banco.example.com/login", "banco.example.com", true),
        ("www.banco.example.com", "banco.example.com", true),          // sub → stored
        ("banco.example.com", "www.banco.example.com", true),          // stored → sub
        ("HTTPS://BANCO.EXAMPLE.COM", "banco.example.com", true),
        ("luz.example.com", "banco.example.com", false),
        ("notbanco.example.com", "banco.example.com", false),          // no partial-label match
        ("banco.example.com", "", false),
    ])
    func matching(identifier: String, domain: String, expected: Bool) {
        #expect(AutofillMatcher.matches(serviceIdentifier: identifier, domain: domain) == expected)
    }

    @Test func nilDomainNeverMatches() {
        #expect(!AutofillMatcher.matches(serviceIdentifier: "banco.example.com", domain: nil))
    }

    @Test(arguments: [
        ("https://banco.example.com/login?x=1", "banco.example.com"),
        ("banco.example.com", "banco.example.com"),
        ("  Banco.Example.Com  ", "banco.example.com"),
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
            MemberTile(id: "c1", displayName: "Banco", sortIndex: 1,
                       domain: "banco.example.com", username: "vovo@example.com"),
            MemberTile(id: "c2", displayName: "SemDominio", sortIndex: 2,
                       domain: nil, username: "user"),
            MemberTile(id: "c3", displayName: "SemUsuario", sortIndex: 3,
                       domain: "luz.example.com", username: nil),
        ]
        let identities = CredentialIdentityRegistrar.identities(from: tiles)
        #expect(identities.count == 1)
        let identity = identities[0]
        #expect(identity.serviceIdentifier.identifier == "banco.example.com")
        #expect(identity.serviceIdentifier.type == .domain)
        #expect(identity.user == "vovo@example.com")
        #expect(identity.recordIdentifier == "c1")
    }
}
