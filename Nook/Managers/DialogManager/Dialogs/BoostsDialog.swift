//
//  BoostsDialog.swift
//  Nook
//
//  Created by Jude on 11/11/2025.
//

import SwiftUI

struct BoostsDialog: View {
    @Binding var config: BoostConfig
    let onApplyLive: ((BoostConfig) -> Void)?

    init(
        config: Binding<BoostConfig>,
        onApplyLive: ((BoostConfig) -> Void)? = nil
    ) {
        _config = config
        self.onApplyLive = onApplyLive
    }

    var body: some View {
        BoostUI(
            config: $config,
            onConfigChange: { newConfig in
                onApplyLive?(newConfig)
            }
        )
    }
}

#Preview {
    @Previewable @State var config = BoostConfig()

    return BoostsDialog(
        config: $config,
        onApplyLive: { newConfig in
            print("Boost config updated: \(newConfig)")
        }
    )
    .padding(40)
}
