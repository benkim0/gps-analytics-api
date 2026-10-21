import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 55))
                .foregroundStyle(.blue)
            
            Text("GPS Analytics")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(locationManager.status)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Points Collected: \(locationManager.pointsCollected)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let latitude = locationManager.latitude,
               let longitude = locationManager.longitude {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Latitude: \(latitude)")
                    Text("Longitude: \(longitude)")
                }
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button("Request Location Permission") {
                locationManager.requestPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
