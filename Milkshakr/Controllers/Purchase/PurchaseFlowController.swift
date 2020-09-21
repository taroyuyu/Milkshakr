//
//  PurchaseFlowController.swift
//  Milkshakr
//
//  Created by Guilherme Rambo on 10/06/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import UIKit
import MilkshakrKit
import PassKit
import IntentsUI

protocol PurchaseFlowControllerDelegate: class {
    func purchaseFlowControllerDidPresentSuccessScreen(_ controller: PurchaseFlowController)
}

final class PurchaseFlowController: NSObject {

    weak var delegate: PurchaseFlowControllerDelegate?

    enum PurchaseError: Error {
        case applePayNotAvailable

        var localizedDescription: String {
            switch self {
            case .applePayNotAvailable:
                return NSLocalizedString("Apple Pay is not available", comment: "Error presented when a purchase fails because Apple Pay is not available")
            }
        }
    }

    weak var presenter: UIViewController?

    let viewModel: PurchaseViewModel
    let accountStore: AccountStore

    init(from presenter: UIViewController, with products: [Product], accountStore: AccountStore) {
        self.presenter = presenter
        self.viewModel = PurchaseViewModel(products: products)
        self.accountStore = accountStore

        super.init()
    }

    func start() {
        let request = PKPaymentRequest(with: viewModel.purchase)

        guard let paymentController = PKPaymentAuthorizationViewController(paymentRequest: request) else {
            self.presentError(PurchaseError.applePayNotAvailable)
            return
        }

        paymentController.delegate = self

        presenter?.present(paymentController, animated: true, completion: nil)
    }

    func presentSuccessScreen() {
        storePurchase()

        let success = PurchaseSuccessViewController(viewModel: viewModel)
        success.delegate = self

        presenter?.present(success, animated: true) { [unowned self] in
            self.delegate?.purchaseFlowControllerDidPresentSuccessScreen(self)
            self.donateInteraction(with: viewModel)
        }

        registerPurchaseSuggestion()

        NotificationManager.shared.scheduleNotification(for: viewModel)
    }

    private func registerPurchaseSuggestion() {
        guard let suggestion = INShortcut(intent: viewModel.intent) else { return }

        // Register shortcut suggestions in the background to avoid UI hang on iOS 14.
        DispatchQueue.global(qos: .utility).async {
            INVoiceShortcutCenter.shared.setShortcutSuggestions([suggestion])
        }
    }

    private func donateInteraction(with viewModel: PurchaseViewModel) {
        viewModel.interaction.donate { error in
            guard let error = error else { return }

            NSLog("Interaction donation error: \(String(describing: error))")
        }
    }

    func presentError(_ error: Error) {

    }

    private func storePurchase() {
        accountStore.store(viewModel.purchase)
    }

}

// MARK: - PKPaymentAuthorizationViewControllerDelegate

extension PurchaseFlowController: PKPaymentAuthorizationViewControllerDelegate {

    func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        let result = PKPaymentAuthorizationResult(status: .success, errors: nil)

        completion(result)
    }

    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true) { [unowned self] in
            self.presentSuccessScreen()
        }
    }

}

// MARK: - PurchaseSuccessViewControllerDelegate

extension PurchaseFlowController: PurchaseSuccessViewControllerDelegate {

    func purchaseSuccessViewControllerDidSelectAddToSiri(_ controller: PurchaseSuccessViewController) {
        guard let shortcut = INShortcut(intent: viewModel.intent) else { return }

        let controller = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        controller.delegate = self

        presenter?.presentedViewController?.present(controller, animated: true, completion: nil)
    }

    func purchaseSuccessViewControllerDidSelectEnableNotifications(_ controller: PurchaseSuccessViewController) {
        NotificationManager.shared.requestAuthorization(provisional: false)
    }

}

@available(iOS 12.0, *)
extension PurchaseFlowController: INUIAddVoiceShortcutViewControllerDelegate {

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }

}
