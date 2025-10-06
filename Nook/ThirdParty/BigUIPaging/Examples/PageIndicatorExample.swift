import SwiftUI

/// Several examples of how to configure and use an indicator. 
@available(macOS, unavailable)
struct PageIndicatorExample: View {
    
    @State private var selection = 0
    @State private var total = 10
    @State private var selectedColor: Color = .purple
    @State private var unselectedColor: Color = .purple.opacity(0.5)
    @State private var tapInteraction = true
    @State private var continuousInteraction = true

    var body: some View {
        Form {
            Section {
                GroupBox {
                    PageIndicator(selection: $selection, total: total)
                        .pageIndicatorBackgroundStyle(.prominent)
                        .singlePageVisibility(.hidden)
                        .padding()
                        .disabled(!tapInteraction)
                }
       
                LabeledContent("Pages") {
                    Stepper(value: $total) {
                        Text("\(total)")
                    }
                }
                LabeledContent("Current Page") {
                    Stepper(value: $selection) {
                        Text("\(selection)")
                    }
                }
                Toggle(isOn: $continuousInteraction) {
                    Text("Continuous Interaction (Drag)")
                }
                Toggle(isOn: $tapInteraction) {
                    Text("Tap Interaction")
                }
            } header: {
                Text("Configure")
            }
            
            Section {
                GroupBox {
                    PageIndicator(selection: $selection, total: total)
                        .pageIndicatorColor(unselectedColor)
                        .pageIndicatorCurrentColor(selectedColor)
                        .padding()
                        .disabled(!tapInteraction)
                    ColorPicker("Selected Color", selection: $selectedColor)
                    ColorPicker("Color", selection: $unselectedColor)
                }
                GroupBox {
                    PageIndicator(selection: $selection, total: total)
                        .pageIndicatorBackgroundStyle(.prominent)
                        .colorScheme(.dark)
                        .padding()
                        .disabled(!tapInteraction)
                    Text("Prominent Background")
                }
                GroupBox {
                    PageIndicator(selection: $selection, total: total) { (page, selected) in
                        if page == 0 {
                            Image(systemName: "location.fill")
                        }
                    }
                    .padding()
        
                    PageIndicator(selection: $selection, total: total) { (page, selected) in
                        if selected {
                            Image(systemName: "folder.fill")
                        } else {
                            Image(systemName: "folder")
                        }
                    }
                    .pageIndicatorCurrentColor(.blue)
                    .padding()
                 
                    Text("Custom Icons")
                }
                .pageIndicatorBackgroundStyle(.prominent)
                .disabled(!tapInteraction)
            } header: {
                Text("Style")
            }
            .listRowSeparator(.hidden)
            
            if #available(iOS 17.0, *) {
                Section {
                    PageIndicator(
                        selection: $selection,
                        total: total
                    )
                    .pageIndicatorDuration(3.0)
                    .padding()
                } header: {
                    Text("Progress")
                }
            }
        }
        .headerProminence(.increased)
        .allowsContinuousInteraction(continuousInteraction)
    }
}

@available(macOS, unavailable)
struct PageIndicatorExample_Previews: PreviewProvider {
    static var previews: some View {
        PageIndicatorExample()
    }
}

