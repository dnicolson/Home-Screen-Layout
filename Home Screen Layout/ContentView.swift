import SwiftUI

struct AppGridView: View {
    let apps = Array(repeating: "", count: 18)

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
            ForEach(0..<apps.count, id: \.self) { index in
                AppIconView(isTopRow: index < 6)
            }
        }
        .padding(.horizontal, 200)
        .padding(.top, 100)
    }
}

struct AppIconView: View {
    var isTopRow: Bool
    
    var body: some View {
        VStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 200, height: 120)
        }
        .background(isTopRow ? Color.white.opacity(0.5) : Color.gray.opacity(0.2))
        .cornerRadius(20)
    }
}

struct ContentView: View {
    @EnvironmentObject var serverManager: Server
    
    var body: some View {
        VStack {
            AppGridView()

            Spacer()

            if (serverManager.hostname.count != 0) {
                Text("To edit the tvOS home screen layout, navigate to:\nhttp://\(serverManager.hostname):8080/")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding(.bottom, 20)
                    .multilineTextAlignment(.center)
                    .lineSpacing(20)
            }

            Spacer()
            
            HStack {
                Button(action: {
                    exit(0)
               }) {
                   Text("Quit")
               }
               .frame(minWidth: 60, minHeight: 30)
            }
            .padding(.bottom, 50)
        }
        .alert(isPresented: $serverManager.showAlert) {
            Alert(title: Text(serverManager.alertTitle),
                  message: Text(serverManager.alertMessage),
                  dismissButton: .default(Text("OK")))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
