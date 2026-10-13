import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Downloads Management & Actions
    @objc func toggleDownloadsPopover() {
        if let pop = downloadsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showDownloadsPopover()
    }
    
    func showDownloadsPopover() {
        downloadsButton.hasUnseenFinished = false
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 360))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Header (44px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let titleLabel = NSTextField(labelWithString: "Downloads")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white
        header.addSubview(titleLabel)
        
        let openFolderBtn = NavIconButton(iconName: "folder", tooltip: "Open Downloads Folder", target: self, action: #selector(openDownloadsFolder))
        header.addSubview(openFolderBtn)
        
        let clearBtn = NavIconButton(iconName: "trash", tooltip: "Clear Downloads List", target: self, action: #selector(clearDownloadsList))
        header.addSubview(clearBtn)
        clearBtn.isEnabled = !downloads.isEmpty
        
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(sep)
        
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            clearBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            clearBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            openFolderBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -4),
            openFolderBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            sep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
        
        if downloads.isEmpty {
            let emptyView = NSView()
            emptyView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(emptyView)
            
            let emptyIcon = NSImageView()
            emptyIcon.translatesAutoresizingMaskIntoConstraints = false
            if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
                emptyIcon.image = img.withSymbolConfiguration(cfg)
                emptyIcon.contentTintColor = NSColor(white: 1.0, alpha: 0.22)
            }
            emptyView.addSubview(emptyIcon)
            
            let emptyTitle = NSTextField(labelWithString: "No Downloads")
            emptyTitle.translatesAutoresizingMaskIntoConstraints = false
            emptyTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            emptyTitle.textColor = NSColor(white: 0.60, alpha: 1.0)
            emptyView.addSubview(emptyTitle)
            
            let emptySub = NSTextField(labelWithString: "Files you download will appear here.")
            emptySub.translatesAutoresizingMaskIntoConstraints = false
            emptySub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptySub.textColor = NSColor(white: 0.40, alpha: 1.0)
            emptyView.addSubview(emptySub)
            
            NSLayoutConstraint.activate([
                emptyView.topAnchor.constraint(equalTo: header.bottomAnchor),
                emptyView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                emptyView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                emptyView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                
                emptyIcon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptyIcon.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -16),
                emptyIcon.widthAnchor.constraint(equalToConstant: 40),
                emptyIcon.heightAnchor.constraint(equalToConstant: 40),
                
                emptyTitle.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptyTitle.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 10),
                
                emptySub.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                emptySub.topAnchor.constraint(equalTo: emptyTitle.bottomAnchor, constant: 4)
            ])
        } else {
            let scrollView = NSScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.autohidesScrollers = true
            container.addSubview(scrollView)
            
            let rowsStack = NSStackView()
            rowsStack.translatesAutoresizingMaskIntoConstraints = false
            rowsStack.orientation = .vertical
            rowsStack.spacing = 4
            rowsStack.alignment = .leading
            
            for item in downloads {
                let row = OnyxDownloadRowView(item: item)
                row.onShowInFinder = {
                    if let dest = item.destinationURL {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                }
                row.onOpenFile = {
                    if let dest = item.destinationURL {
                        NSWorkspace.shared.open(dest)
                    }
                }
                row.onCancel = { [weak self] in
                    item.download?.cancel { _ in }
                    item.state = .cancelled
                    self?.updateDownloadsState()
                    self?.showDownloadsPopover()
                }
                rowsStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            }
            
            let clip = FlippedClipView()
            clip.drawsBackground = false
            clip.documentView = rowsStack
            scrollView.contentView = clip
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                
                rowsStack.topAnchor.constraint(equalTo: clip.topAnchor),
                rowsStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                rowsStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor)
            ])
        }
        
        let controller = NSViewController()
        controller.view = container
        popover.contentViewController = controller
        
        let anchor = (downloadsButton.isHidden || downloadsButton.window == nil) ? extensionsButton! : downloadsButton!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
        downloadsPopover = popover
    }
    
    @objc func openDownloadsFolder() {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        NSWorkspace.shared.open(downloadsDir)
    }
    
    @objc func clearDownloadsList() {
        downloads.removeAll { item in
            if case .downloading = item.state { return false }
            return true
        }
        updateDownloadsState()
        downloadsPopover?.performClose(nil)
    }
    
    func registerDownload(download: WKDownload, sourceURL: URL?) {
        let filename = sourceURL?.lastPathComponent.isEmpty == false ? sourceURL!.lastPathComponent : "download"
        let item = OnyxDownloadItem(download: download, filename: filename, sourceURL: sourceURL)
        activeDownloads[download] = item
        downloads.insert(item, at: 0)
        
        updateDownloadsState()
        startDownloadProgressTimer()
    }
    
    func updateDownloadDestination(download: WKDownload, url: URL, filename: String) {
        guard let item = activeDownloads[download] else { return }
        item.destinationURL = url
        item.filename = filename
    }
    
    func handleDownloadFinished(download: WKDownload) {
        guard let item = activeDownloads[download] else { return }
        item.state = .completed
        item.finishDate = Date()
        activeDownloads.removeValue(forKey: download)
        
        downloadsButton.hasUnseenFinished = true
        downloadsButton.triggerBounce()
        NSSound(named: "Glass")?.play()
        
        showDownloadCompleteHUD(item: item)
        updateDownloadsState()
    }
    
    func handleDownloadFailed(download: WKDownload, error: Error) {
        guard let item = activeDownloads[download] else { return }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            item.state = .cancelled
        } else {
            item.state = .failed
            item.errorMessage = error.localizedDescription
        }
        activeDownloads.removeValue(forKey: download)
        updateDownloadsState()
    }
    
    func startDownloadProgressTimer() {
        if downloadProgressTimer == nil {
            downloadProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.pollDownloadProgress()
            }
        }
    }
    
    func pollDownloadProgress() {
        if activeDownloads.isEmpty {
            downloadProgressTimer?.invalidate()
            downloadProgressTimer = nil
            updateDownloadsState()
            return
        }
        
        var totalFraction: Double = 0.0
        for (download, item) in activeDownloads {
            let prog = download.progress
            item.progressFraction = prog.fractionCompleted
            item.receivedBytes = prog.completedUnitCount
            item.totalBytes = prog.totalUnitCount
            totalFraction += prog.fractionCompleted
        }
        
        let avgFraction = totalFraction / Double(activeDownloads.count)
        downloadsButton.progress = avgFraction
        downloadsButton.toolTip = "Downloading... (\(Int(avgFraction * 100))%)"
    }
    
    func updateDownloadsState() {
        let isDownloading = !activeDownloads.isEmpty
        downloadsButton.isDownloading = isDownloading
        if !isDownloading && !downloadsButton.hasUnseenFinished {
            downloadsButton.toolTip = "Downloads (⌘J)"
        }
    }
    
    func showDownloadCompleteHUD(item: OnyxDownloadItem) {
        guard let dest = item.destinationURL, let contentView = self.window?.contentView else { return }
        
        activeDownloadHUD?.dismiss()
        let hud = DownloadNotificationHUD(filename: item.filename, fileURL: dest)
        activeDownloadHUD = hud
        contentView.addSubview(hud)
        
        NSLayoutConstraint.activate([
            hud.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            hud.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            hud.widthAnchor.constraint(equalToConstant: 320),
            hud.heightAnchor.constraint(equalToConstant: 48)
        ])
        
        hud.animateIn()
    }
    
    @objc func openLocalFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a file to open in Onyx"
        
        if let win = self.window {
            panel.beginSheetModal(for: win) { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.loadURL(url)
                }
            }
        } else {
            panel.begin { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.loadURL(url)
                }
            }
        }
    }
    
    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let cleanName: String
        if !suggestedFilename.isEmpty {
            cleanName = suggestedFilename
        } else if let urlName = response.url?.lastPathComponent, !urlName.isEmpty {
            cleanName = urlName
        } else {
            cleanName = "download"
        }
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        
        if activeDownloads[download]?.asksForLocation == true {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = cleanName
            panel.directoryURL = downloadsDir
            panel.canCreateDirectories = true
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    completionHandler(nil)   // cancels the download; it is listed as cancelled
                    return
                }
                // The panel already confirmed "Replace"; WebKit refuses to write over a file.
                try? FileManager.default.removeItem(at: url)
                self?.updateDownloadDestination(download: download, url: url, filename: url.lastPathComponent)
                completionHandler(url)
            }
            if let win = window {
                panel.beginSheetModal(for: win, completionHandler: finish)
            } else {
                finish(panel.runModal())
            }
            return
        }
        
        var targetURL = downloadsDir.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let ext = targetURL.pathExtension
            let baseName = targetURL.deletingPathExtension().lastPathComponent
            var counter = 1
            repeat {
                let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                targetURL = downloadsDir.appendingPathComponent(newName)
                counter += 1
            } while FileManager.default.fileExists(atPath: targetURL.path)
        }
        
        updateDownloadDestination(download: download, url: targetURL, filename: targetURL.lastPathComponent)
        completionHandler(targetURL)
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        handleDownloadFinished(download: download)
    }
    
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        handleDownloadFailed(download: download, error: error)
    }
}
