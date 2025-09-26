import SwiftUI

/// An example of how to use page view inside a NavigationStack.
struct PageViewWithNavigationStackExample: View {
    
    var body: some View {
        NavigationStack {
            RootView()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        PageViewNavigationButton()
                            .pageViewOrientation(.vertical)
                    }
                }
        }
        #if os(macOS)
        .pageViewStyle(.bookStack)
        #else
        .pageViewStyle(.scroll)
        #endif
        .pageContentBackground(.visible)
        .pageViewEnvironment()
    }
    
    struct RootView: View {
        
        @State private var items: [MyItem]
        @State private var selection: MyItem.ID
        
        init() {
            let items = MyItem.makeItems()
            self._items = State(wrappedValue: items)
            self._selection = State(wrappedValue: items[0].id)
        }

        var body: some View {
            VStack {
                #if os(macOS)
                PageViewNavigationButton()
                    .padding()
                #endif
                PageView(selection: $selection) {
                    ForEach(items) { item in
                        ContentView(id: item.id)
                    }
                }
                .ignoresSafeArea()
                .navigationTitle("Message \(selection)")
            }
        }
    }
    
    struct ContentView: View {
    
        let id: Int
        
        var body: some View {
            ScrollView {
                VStack(alignment: .leading) {
                    #if os(macOS)
                    Text("Message \(id)")
                        .font(.title.weight(.semibold))
                        .padding(.bottom)
                    #endif
                    Text(String.corporateIpsum)
                }
                .scenePadding()
            }
            .background(.background)
        }
    }
}

// MARK: - Preview

struct PageViewWithNavigationStackExample_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewWithNavigationStackExample()
    }
}

// MARK: - Content

struct MyItem: Identifiable {
    var id: Int
    
    static func makeItems(_ limit: Int = 100) -> [MyItem] {
        (1...limit).map {
            MyItem(id: $0)
        }
    }
}

extension String {
    
    static let corporateIpsum = """
    We need to leverage our synergies this proposal is a win-win situation which will cause a stellar paradigm shift, and produce a multi-fold increase in deliverables, nor race without a finish line, yet can you champion this, and root-and-branch review currying favour, so imagineer.\n\nWe need to leverage our synergies everyone thinks the soup tastes better after they've in it, can we parallel path hit the ground running.\n\nPrethink window-licker can you champion this let's take this conversation offline big picture. Productize we need to leverage our synergies all hands on deck the last person we talked to said this would be ready pushback. In this space gain traction. Per my previous email work, or pass the mayo, appeal to the client, sue the vice president. Proceduralize high performance keywords we need to harvest synergy effects, nor run it up the flagpole, ping the boss and circle back can you run this by clearance? hot johnny coming through.\n\nMy capacity is full cannibalize, for streamline. Cross functional teams enable out of the box brainstorming goalposts. Productize we need a recap by eod, cob or whatever comes first a set of certitudes based on deductions founded on false premise. Get all your ducks in a row get six alpha pups in here for a focus group, and what the, that's not on the roadmap create spaces to explore what's next beef up, nor organic growth. But what's the real problem we're trying to solve here?.\n\nMumbo jumbo prairie dogging, nor low hanging fruit to be inspired is to become creative, innovative and energized we want this philosophy to trickle down to all our stakeholders i'm sorry i replied to your emails after only three weeks, but can the site go live tomorrow anyway?. Nail jelly to the hothouse wall drill down, but show pony, yet crank this out goalposts. Minimize backwards overflow timeframe, yet at the end of the day.
    """
}
