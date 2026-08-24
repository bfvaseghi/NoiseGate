import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Custom look for the block screen shown over shielded noise apps.
class ShieldConfigExtension: ShieldConfigurationDataSource {

    private func makeConfiguration() -> ShieldConfiguration {
        let reason = ShieldController.activeReasons().first
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.6),
            icon: UIImage(systemName: "waveform.slash"),
            title: ShieldConfiguration.Label(text: "NoiseGate", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: reason?.explanation ?? "This app is blocked right now.",
                color: UIColor(white: 0.85, alpha: 1)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Back to real life", color: .black),
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
