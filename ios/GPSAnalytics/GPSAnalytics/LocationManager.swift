import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var collectionTimer: Timer?
    
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var status = "Waiting for location permission"
    @Published var pointsCollected = 0
    
    private var latestLocation: CLLocation?
    
    private var savedPoints: [GPSPoint] = []
    @Published private var pendingUploads: [GPSPoint] = []
    private let apiURL = URL(string: "https://gps-analytics-api.onrender.com/gps/batch")!
    private var uploadTimer: Timer?
    private var isUploading = false
    private let maxStoredPoints = 100_000
    private var storageURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("gps_points.json")
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = kCLDistanceFilterNone
        
        loadPoints()
        loadPendingUploads()
        uploadTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            self?.uploadPoints()
        }
    }
    
    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Location Services are disabled"
            return
        }
        
        manager.startUpdatingLocation()
        status = "Waiting for GPS. . ."
    }
    
    func startCollection() {
        guard collectionTimer == nil else { return }
        
        collectionTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
            )
        {[weak self] _ in
            self?.collectLocationPoint()
        }
        
        status = "Collecting a point every 5 seconds"
    }
    
    func stopCollection() {
        collectionTimer?.invalidate()
        collectionTimer = nil
        status = "Collection stopped"
    }
    
    private func collectLocationPoint() {
        guard let location = latestLocation else {
            status = "Waiting for a GPS location. . ."
            return
        }
        
        let point = GPSPoint(location: location)
        storePoint(point)
        
        latitude = point.latitude
        longitude = point.longitude
        
        let timestamp = ISO8601DateFormatter().string(from: point.timestamp)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            status = "Location permission granted"
            startTracking()
            startCollection()
        case .denied, .restricted:
            status = "Location permission denied"
        default:
            status = "Waiting for local permission"
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
    
        guard location.horizontalAccuracy >= 0 else {
            return
        }
        latestLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError,
           locationError.code == .locationUnknown {
            return
        }
        
        status = "Location Error: \(error.localizedDescription)"
    }
    
    private func loadPoints() {
        do {
            let data = try Data(contentsOf: storageURL)
            savedPoints = try JSONDecoder().decode([GPSPoint].self, from: data)
            pointsCollected = savedPoints.count
        } catch {
            savedPoints = []
        }
    }
    
    private func savePoints() {
        do {
            let data = try JSONEncoder().encode(savedPoints)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            status = "Failed to save GPS data: \(error.localizedDescription)"
        }
    }
    
    private func storePoint(_ point: GPSPoint) {
        savedPoints.append(point)
        pendingUploads.append(point)
        savePendingUploads()
        
        if savedPoints.count > maxStoredPoints {
            savedPoints.removeFirst(savedPoints.count - maxStoredPoints)
        }
        
        pointsCollected = savedPoints.count
        savePoints()
    }
    
    private func uploadPoints() {
        guard !isUploading, !pendingUploads.isEmpty else { return }
        isUploading = true
        
        let batch = Array(pendingUploads.prefix(1000))
        
        let points = batch.map { point in
            [
                "device_id": "my-iphone",
                "recorded_at": ISO8601DateFormatter().string(from: point.timestamp),
                "latitude": point.latitude,
                "longitude": point.longitude,
                "accuracy_m": point.horizontalAccuracy
            ] as [String: Any]
        }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["points": points]
            )
        } catch {
            isUploading = false
            print("Could not encode GPS batch:", error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer { self.isUploading = false }
                
                if let error = error {
                    print("GPS upload failed:", error.localizedDescription)
                    return
                }
                
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    print("GPS upload returned an unsuccessful status")
                    return
                }
                
                let uploadedIDs = Set(batch.map { $0.id })
                self.pendingUploads.removeAll { uploadedIDs.contains($0.id) }
                self.savePendingUploads()
                
                print("GPS batch uploaded successfully:", batch.count)
            }
        }.resume()
    }
    
    private func savePendingUploads() {
        do {
            let data = try JSONEncoder().encode(pendingUploads)
            let url = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("pending_uploads.json")
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save pending uploads:", error)
        }
    }
    
    private func loadPendingUploads() {
        let url = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("pending_uploads.json")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            pendingUploads = try JSONDecoder().decode(
                [GPSPoint].self,
                from: data
            )
        } catch {
            print("Failed to load pending uploads:", error)
        }
    }
}

