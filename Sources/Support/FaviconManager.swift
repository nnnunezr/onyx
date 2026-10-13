import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Favicon Manager (High-Performance Memory & Disk Cache for Tab Favicons)
class FaviconManager {
    static let shared = FaviconManager()
    
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDir: URL?
    private let session: URLSession
    private var inFlightCompletions: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = cachesURL.appendingPathComponent("com.company.onyx/favicons", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            self.cacheDir = dir
        } else {
            self.cacheDir = nil
        }
        
        memoryCache.countLimit = 250
    }
    
    func cachedFavicon(for host: String) -> NSImage? {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return nil }
        
        let key = cleanHost as NSString
        if let mem = memoryCache.object(forKey: key) {
            mem.isTemplate = false
            return mem
        }
        if let dir = cacheDir {
            let safeName = cleanHost.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            let fileURL = dir.appendingPathComponent("\(safeName).png")
            if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                img.isTemplate = false
                memoryCache.setObject(img, forKey: key)
                return img
            }
        }
        return nil
    }
    
    func storeFavicon(_ image: NSImage, for host: String) {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return }
        
        image.isTemplate = false
        let key = cleanHost as NSString
        memoryCache.setObject(image, forKey: key)
        
        if let dir = cacheDir,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let safeName = cleanHost.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            let fileURL = dir.appendingPathComponent("\(safeName).png")
            try? png.write(to: fileURL)
        }
    }
    
    func fetchFirstValidFavicon(from urls: [URL], forHost host: String, completion: @escaping (NSImage?) -> Void) {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        lock.lock()
        if inFlightCompletions[cleanHost] != nil {
            inFlightCompletions[cleanHost]?.append(completion)
            lock.unlock()
            return
        }
        inFlightCompletions[cleanHost] = [completion]
        lock.unlock()
        
        func finish(_ image: NSImage?) {
            self.lock.lock()
            let callbacks = self.inFlightCompletions.removeValue(forKey: cleanHost) ?? []
            self.lock.unlock()
            for cb in callbacks {
                cb(image)
            }
        }
        
        func tryNext(index: Int) {
            guard index < urls.count else {
                finish(nil)
                return
            }
            let targetURL = urls[index]
            var req = URLRequest(url: targetURL)
            req.setValue(UserAgent.full, forHTTPHeaderField: "User-Agent")
            
            session.dataTask(with: req) { [weak self] (data, response, error) in
                guard let self = self else { return }
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let data = data, data.count > 32,
                   let image = NSImage(data: data), image.isValid {
                    let processed = self.prepareRetinaFavicon(image)
                    self.storeFavicon(processed, for: cleanHost)
                    finish(processed)
                } else {
                    tryNext(index: index + 1)
                }
            }.resume()
        }
        
        tryNext(index: 0)
    }
    
    private func prepareRetinaFavicon(_ source: NSImage) -> NSImage {
        let targetSize = NSSize(width: 16, height: 16)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = targetSize
            NSGraphicsContext.saveGraphicsState()
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current = ctx
            ctx?.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            let result = NSImage(size: targetSize)
            result.addRepresentation(rep)
            result.isTemplate = false
            return result
        }
        source.size = targetSize
        source.isTemplate = false
        return source
    }
}
