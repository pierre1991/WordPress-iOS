import Foundation
import UIKit
import RxSwift
import WordPressComAnalytics

func AccountSettingsViewController(account account: WPAccount) -> ImmuTableViewController {    
    let service = AccountSettingsService(userID: account.userID.integerValue, api: account.restApi)
    return AccountSettingsViewController(service: service)
}

func AccountSettingsViewController(service service: AccountSettingsService) -> ImmuTableViewController {
    let controller = AccountSettingsController(service: service)
    let viewController = ImmuTableViewController(controller: controller)
    return viewController
}

private struct AccountSettingsController: SettingsController {
    let title = NSLocalizedString("Account Settings", comment: "Account Settings Title");

    var immuTableRows: [ImmuTableRow.Type] {
        return [
            TextRow.self,
            EditableTextRow.self
        ]
    }

    // MARK: - Initialization

    let service: AccountSettingsService

    init(service: AccountSettingsService) {
        self.service = service
    }
    
    // MARK: - ImmuTableViewController

    func tableViewModelWithPresenter(presenter: ImmuTablePresenter) -> Observable<ImmuTable> {
        return service.settings.map({ settings in
            self.mapViewModel(settings, service: self.service, presenter: presenter)
        })
    }

    var refreshStatusMessage: Observable<String?> {
        return service.refresh
            // replace errors with .Failed status
            .catchErrorJustReturn(.Failed)
            // convert status to string
            .map({ $0.errorMessage })
    }

    var emailNoticeMessage: Observable<String?> {
        return service.settings.map {
            return self.noticeForAccountSettings($0)
        }
    }
    
    var noticeMessage: Observable<String?> {
        return Observable.combineLatest(refreshStatusMessage, emailNoticeMessage) { refresh, email -> String? in
            return refresh ?? email
        }
    }

    
    // MARK: - Model mapping

    func mapViewModel(settings: AccountSettings?, service: AccountSettingsService, presenter: ImmuTablePresenter) -> ImmuTable {
        let primarySiteName = settings.flatMap { service.primarySiteNameForSettings($0) }
        
        let username = TextRow(
            title: NSLocalizedString("Username", comment: "Account Settings Username label"),
            value: settings?.username ?? "")
        
        let email = EditableTextRow(
            title: NSLocalizedString("Email", comment: "Account Settings Email label"),
            value: settings?.emailForDisplay ?? "",
            action: presenter.prompt(editEmailAddress(settings, service: service))
        )
        
        let primarySite = EditableTextRow(
            title: NSLocalizedString("Primary Site", comment: "Primary Web Site"),
            value: primarySiteName ?? "",
            action: presenter.present(insideNavigationController(editPrimarySite(settings, service: service)))
        )
        
        let webAddress = EditableTextRow(
            title: NSLocalizedString("Web Address", comment: "Account Settings Web Address label"),
            value: settings?.webAddress ?? "",
            action: presenter.prompt(editWebAddress(service))
        )
        
        return ImmuTable(sections: [
            ImmuTableSection(
                rows: [
                    username,
                    email,
                    primarySite,
                    webAddress
                ])
            ])
    }
    
    
    // MARK: - Actions
    
    func editEmailAddress(settings: AccountSettings?, service: AccountSettingsService) -> ImmuTableRow -> SettingsTextViewController {
        return { row in
            let editableRow = row as! EditableTextRow
            let hint = NSLocalizedString("Will not be publicly displayed.", comment: "Help text when editing email address")
            let settingsViewController =  self.controllerForEditableText(editableRow,
                                                                         changeType: AccountSettingsChange.Email,
                                                                         hint: hint,
                                                                         service: service)
            settingsViewController.mode = .Email
            settingsViewController.notice = self.noticeForAccountSettings(settings)
            settingsViewController.displaysActionButton = settings?.emailPendingChange ?? false
            settingsViewController.actionText = NSLocalizedString("Revert Pending Change", comment: "Cancels a pending Email Change")
            settingsViewController.onActionPress = {
                let change = AccountSettingsChange.EmailPendingChange(false)
                service.saveChange(change)
            }
            
            return settingsViewController
        }
    }
    
    func editWebAddress(service: AccountSettingsService) -> ImmuTableRow -> SettingsTextViewController {
        let hint = NSLocalizedString("Shown publicly when you comment on blogs.", comment: "Help text when editing web address")
        return editText(AccountSettingsChange.WebAddress, hint: hint, service: service)
    }
    
    func editPrimarySite(settings: AccountSettings?, service: AccountSettingsService) -> ImmuTableRowControllerGenerator {
        return {
            row in

            let selectorViewController = BlogSelectorViewController(selectedBlogDotComID: settings?.primarySiteID,
                successHandler: { (dotComID : NSNumber!) in
                    let change = AccountSettingsChange.PrimarySite(dotComID as Int)
                    service.saveChange(change)
                },
                dismissHandler: nil)

            selectorViewController.title = NSLocalizedString("Primary Site", comment: "Primary Site Picker's Title");
            selectorViewController.displaysOnlyDefaultAccountSites = true
            selectorViewController.displaysCancelButton = true
            selectorViewController.dismissOnCompletion = true
            selectorViewController.dismissOnCancellation = true
            
            return selectorViewController
        }
    }
    
    
    // MARK: - Private Helpers
    
    private func noticeForAccountSettings(settings: AccountSettings?) -> String? {
        guard let pendingAddress = settings?.emailPendingAddress where settings?.emailPendingChange == true else {
            return nil
        }
        
        return NSLocalizedString("There is a pending change of your email to \(pendingAddress). Please check your inbox for a confirmation link.",
                                 comment: "Displayed when there's a pending Email Change")
    }
}