import AmparoShared
import AuthenticationServices
import SwiftUI
import UIKit

/// §8 — the AutoFill Credential Provider. Three entry points:
///
/// - QuickType tap → `provideCredentialWithoutUserInteraction`: keychain
///   read fires the system Face ID sheet, credential returned with no
///   extension UI. Keychain-level failures escalate to
///   `.userInteractionRequired`.
/// - Escalation → `prepareInterfaceToProvideCredential`: minimal unlock UI,
///   same fill.
/// - Password-field "…" picker → `prepareCredentialList`: big-tile picker,
///   same visual language as the app, filtered by the requesting service.
///
/// The extension never syncs — it reads the app-group snapshot + shared
/// keychain only (D20).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let vault = VaultStore.makeShared()

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard credentialRequest.type == .password,
              let recordId = credentialRequest.credentialIdentity.recordIdentifier else {
            cancel(.credentialIdentityNotFound)
            return
        }
        Task { await fill(recordId: recordId) }
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard let recordId = credentialRequest.credentialIdentity.recordIdentifier else {
            cancel(.credentialIdentityNotFound)
            return
        }
        host(UnlockAndFillView(
            attempt: { [vault] in
                guard let secrets = try await vault.secrets(forCipher: recordId),
                      let password = secrets.password else { return nil }
                return ASPasswordCredential(user: secrets.username ?? "", password: password)
            },
            onFilled: { [weak self] credential in self?.complete(credential) },
            onCancel: { [weak self] in self?.cancel(.userCanceled) }
        ))
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        host(CredentialPickerView(
            vault: vault,
            serviceIdentifiers: serviceIdentifiers.map(\.identifier),
            onPick: { [weak self] credential in self?.complete(credential) },
            onCancel: { [weak self] in self?.cancel(.userCanceled) }
        ))
    }

    // MARK: Plumbing

    private func fill(recordId: String) async {
        do {
            guard let secrets = try await vault.secrets(forCipher: recordId),
                  let password = secrets.password else {
                cancel(.credentialIdentityNotFound)
                return
            }
            complete(ASPasswordCredential(user: secrets.username ?? "", password: password))
        } catch is KeychainError {
            // Face ID unavailable/cancelled/locked: let the system re-enter
            // through the interactive path.
            cancel(.userInteractionRequired)
        } catch {
            cancel(.failed)
        }
    }

    private func complete(_ credential: ASPasswordCredential) {
        extensionContext.completeRequest(withSelectedCredential: credential)
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: ASExtensionError(code))
    }

    private func host(_ rootView: some View) {
        let controller = UIHostingController(rootView: rootView)
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }
}
