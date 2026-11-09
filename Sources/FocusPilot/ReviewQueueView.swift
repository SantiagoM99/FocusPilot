import FocusPilotCore
import SwiftUI

/// The Review queue: finished results nobody has reviewed, in the same list
/// and inspector as In flight.
struct ReviewQueueView: View {
    let model: AppModel

    var body: some View {
        InFlightList(model: model, sections: [
            .init(title: nil, titleColor: .secondaryText, dot: .amber, rows: model.inFlightBoard.results),
        ])
    }
}
