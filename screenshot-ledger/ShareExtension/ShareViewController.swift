import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.973, green: 0.957, blue: 0.933, alpha: 1)
        statusLabel.text = "正在接收截图…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = UIColor(red: 0.145, green: 0.125, blue: 0.102, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        importSharedImage()
    }

    private func importSharedImage() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish(message: "没有收到图片")
            return
        }
        let type = UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else {
            finish(message: "请分享一张图片")
            return
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
            let data = Self.imageData(from: item)
            DispatchQueue.main.async {
                guard error == nil, let data, !data.isEmpty else {
                    self.finish(message: "读取截图失败")
                    return
                }
                do {
                    _ = try AppGroup.savePending(data)
                    self.openHostApp()
                    self.extensionContext?.completeRequest(returningItems: nil)
                } catch {
                    self.finish(message: "无法交给主 App。请打开截屏记账，从相册选择这张截图。")
                }
            }
        }
    }

    private static func imageData(from item: NSSecureCoding?) -> Data? {
        if let data = item as? Data { return data }
        if let data = item as? NSData { return data as Data }
        if let image = item as? UIImage {
            return image.jpegData(compressionQuality: 0.9) ?? image.pngData()
        }
        if let url = item as? URL { return try? Data(contentsOf: url) }
        return nil
    }

    private func openHostApp() {
        guard let url = URL(string: "snapledger://import") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    private func finish(message: String) {
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            self.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
