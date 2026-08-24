import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Custom look for the block screen shown over shielded noise apps.
class ShieldConfigExtension: ShieldConfigurationDataSource {

    private func makeConfiguration() -> ShieldConfiguration {
        let reason = ShieldController.activeReasons().first
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: UIColor.systemRed,
            icon: UIImage(systemName: "hand.raised.fill"),
            title: ShieldConfiguration.Label(text: "STOP.", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: reason?.explanation ?? "This app is blocked. You know why.",
                color: .white
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Fine. Leaving.", color: .systemRed),
            primaryButtonBackgroundColor: .white
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }
}
