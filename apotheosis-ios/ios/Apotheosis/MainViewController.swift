import UIKit
import WebKit

/// Apotheosis: the band39-live care app (care/web, unchanged) with the Apotheosis design layer, in one WKWebView.
/// Navigation follows Band39Care: a native tab bar switches roles — Margaret (her screen), Lisa (the caregiver app),
/// Band (connect band 39 or the pretend band, and "Try it without a band") with a gear for the server address.
/// All tabs are views of the same page, so they share one live state.
/// No server set: the page loads from the app bundle (apotheosis://app/), and motion, the pretend band, the safe card
/// and the demo buttons work offline. Server set: the page loads from the server, so its api/ calls work too.
final class MainViewController: UIViewController, UITabBarDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Role: Int { case margaret = 0, lisa = 1, band = 2 }

    static let serverKey = "apotheosisServerURL"
    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }

    private var webView: WKWebView!
    private let tabBar = UITabBar()
    private let topBar = UIView()
    private let gear = UIButton(type: .system)
    private let bridge = BLEBridge()
    private let haptics = UINotificationFeedbackGenerator()

    private var role: Role = .margaret
    private var lisaBadge = 0
    private var webTopToView: NSLayoutConstraint!
    private var webTopToBar: NSLayoutConstraint!

    private static let ground = UIColor(white: 0.925, alpha: 1)          // #ECECEC
    private static let ink = UIColor(white: 0.08, alpha: 1)              // #141414
    private static let muted = UIColor(white: 0.42, alpha: 1)            // #6B6B6B
    private static let alertRed = UIColor(red: 0.761, green: 0.157, blue: 0.231, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        setvbuf(stdout, nil, _IONBF, 0)
        #endif
        view.backgroundColor = Self.ground
        if let tab = Self.arg("-tab") { role = tab == "lisa" ? .lisa : tab == "band" ? .band : .margaret }
        buildWebView()
        buildTopBar()
        buildTabBar()
        layout()
        applyChrome()
        loadPage()
        #if DEBUG
        scheduleSnapshotIfAsked()
        #endif
    }

    // MARK: - building

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.userContentController.add(bridge, name: "vexoBle")
        config.userContentController.add(self, name: "apotheosis")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        installUserScripts(config.userContentController)

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never   // the page pads for the notch with env(safe-area-inset-*)
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        view.addSubview(webView)
        bridge.webView = webView
    }

    /// Before any page script: the design layer (as a <style>, so it also applies when the page comes from a server),
    /// the tab to show, the Bluetooth transport; after load: a watcher that tells the native tab bar about Lisa's badge.
    private func installUserScripts(_ ucc: WKUserContentController) {
        ucc.removeAllUserScripts()
        var css = ""
        if let url = Bundle.main.url(forResource: "apotheosis", withExtension: "css", subdirectory: "web/apotheosis"),
           let text = try? String(contentsOf: url, encoding: .utf8) { css = text }
        let cssLiteral = Self.jsString(css)
        let boot = """
        (function () {
          var d = document.documentElement;
          d.classList.add('apo');
          d.dataset.apoView = \(Self.jsString(pageView(for: role)));
          var s = document.createElement('style'); s.id = 'apotheosis-css'; s.textContent = \(cssLiteral);
          d.appendChild(s);
        })();
        """
        ucc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let url = Bundle.main.url(forResource: "native-ble", withExtension: "js"), let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let watch = """
        (function () {
          var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.apotheosis; if (!h) return;
          var b = document.getElementById('tabBadge'), last = null;
          function tell() { var n = parseInt((b && b.textContent || '').replace(/[^0-9]/g, ''), 10) || ((b && b.textContent.trim()) ? 1 : 0); if (n !== last) { last = n; h.postMessage({ badge: n }); } }
          if (b) new MutationObserver(tell).observe(b, { childList: true, characterData: true, subtree: true });
          tell();
        })();
        """
        ucc.addUserScript(WKUserScript(source: watch, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    private func loadPage() {
        let server = Self.serverURL
        if !server.isEmpty, let url = URL(string: server.hasSuffix("/") ? server : server + "/") {
            webView.load(URLRequest(url: url))
        } else {
            webView.load(URLRequest(url: URL(string: "\(BundleSchemeHandler.scheme)://app/index.html")!))
        }
    }

    /// Band tab only: a title and the server gear, like Band39Care's simulator bar.
    private func buildTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = Self.ground
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Apotheosis"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = Self.ink
        let sub = UILabel()
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = Self.muted
        sub.tag = 77
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.setImage(UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        gear.tintColor = Self.ink
        gear.backgroundColor = .white
        gear.layer.cornerRadius = 22
        gear.accessibilityLabel = "Server settings"
        gear.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        topBar.addSubview(title); topBar.addSubview(sub); topBar.addSubview(gear)
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 6),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: gear.leadingAnchor, constant: -10),
            sub.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            gear.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            gear.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            gear.widthAnchor.constraint(equalToConstant: 44),
            gear.heightAnchor.constraint(equalToConstant: 44),
        ])
        updateServerLabel()
    }

    private func updateServerLabel() {
        (topBar.viewWithTag(77) as? UILabel)?.text = Self.serverURL.isEmpty ? "Offline · no server set" : "Server · \(Self.serverURL)"
    }

    private func buildTabBar() {
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        let look = UITabBarAppearance()
        look.configureWithOpaqueBackground()
        look.backgroundColor = .white
        look.shadowColor = UIColor(white: 0, alpha: 0.06)
        for item in [look.stackedLayoutAppearance, look.inlineLayoutAppearance, look.compactInlineLayoutAppearance] {
            item.normal.iconColor = Self.muted
            item.normal.titleTextAttributes = [.foregroundColor: Self.muted]
            item.selected.iconColor = Self.ink
            item.selected.titleTextAttributes = [.foregroundColor: Self.ink, .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
            item.normal.badgeBackgroundColor = Self.alertRed
        }
        tabBar.standardAppearance = look
        if #available(iOS 15.0, *) { tabBar.scrollEdgeAppearance = look }
        let items = [
            UITabBarItem(title: "Margaret", image: UIImage(systemName: "person"), selectedImage: UIImage(systemName: "person.fill")),
            UITabBarItem(title: "Lisa", image: UIImage(systemName: "person.2"), selectedImage: UIImage(systemName: "person.2.fill")),
            UITabBarItem(title: "Band", image: UIImage(systemName: "applewatch.radiowaves.left.and.right"), selectedImage: UIImage(systemName: "applewatch.radiowaves.left.and.right")),
        ]
        for (i, item) in items.enumerated() { item.tag = i }
        items[0].accessibilityHint = "Margaret’s screen"
        items[1].accessibilityHint = "Lisa’s app"
        items[2].accessibilityHint = "Connect band 39, or try it without a band"
        tabBar.items = items
        view.addSubview(tabBar)
    }

    private func layout() {
        webTopToView = webView.topAnchor.constraint(equalTo: view.topAnchor)
        webTopToBar = webView.topAnchor.constraint(equalTo: topBar.bottomAnchor)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -49),
        ])
    }

    private func applyChrome() {
        let band = role == .band
        topBar.isHidden = !band
        webTopToBar.isActive = band
        webTopToView.isActive = !band
        tabBar.selectedItem = tabBar.items?[role.rawValue]
        tabBar.items?[Role.lisa.rawValue].badgeValue = (role != .lisa && lisaBadge > 0) ? String(lisaBadge) : nil
    }

    private func pageView(for r: Role) -> String { r == .lisa ? "lisa" : r == .band ? "band" : "margaret" }

    // MARK: - switching roles

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let r = Role(rawValue: item.tag) else { return }
        show(r)
    }

    /// Sets the view on the page and presses the page's own Margaret / Lisa tab, so the original app's tab logic runs.
    private func show(_ r: Role) {
        role = r
        applyChrome()
        let v = pageView(for: r)
        let pageTab = r == .lisa ? "lisa" : "margaret"
        webView.evaluateJavaScript("""
        (function () {
          document.documentElement.dataset.apoView = '\(v)';
          var t = document.querySelector('.tabs [data-tab="\(pageTab)"]'); if (t) t.click();
          if ('\(v)' === 'band') { var d = document.getElementById('demo'); if (d) d.open = true; }
          window.scrollTo(0, 0);
        })();
        """, completionHandler: nil)
    }

    @objc private func openSettings() {
        let vc = SettingsViewController(current: Self.serverURL) { [weak self] url in
            Self.serverURL = url
            self?.updateServerLabel()
            self?.loadPage()
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    // MARK: - page messages and navigation

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let n = body["badge"] as? Int else { return }
        if n > lisaBadge { haptics.notificationOccurred(.warning) }
        lisaBadge = n
        tabBar.items?[Role.lisa.rawValue].badgeValue = (role != .lisa && n > 0) ? String(n) : nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        show(role)
        #if DEBUG
        webView.evaluateJavaScript("[document.documentElement.dataset.apoView, !!document.getElementById('apotheosis-css'), document.querySelector('.m-greet') && document.querySelector('.m-greet').textContent].join(' | ')") { r, _ in
            print("page loaded:", r ?? "nil")
        }
        #endif
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        print("web content process terminated")
        #endif
        webView.reload()
    }

    /// Stripe Checkout and other outside links open in Safari; the care app stays put.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        let ours = url.scheme == BundleSchemeHandler.scheme || (!Self.serverURL.isEmpty && url.absoluteString.hasPrefix(Self.serverURL))
        if !ours, url.scheme?.hasPrefix("http") == true, navigationAction.targetFrame?.isMainFrame != false {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    /// window.open (Stripe Checkout in a new tab) → Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    // MARK: - helpers

    static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]), let lit = String(data: data, encoding: .utf8) else { return "\"\"" }
        return lit
    }

    static func arg(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    #if DEBUG
    /// `-snapshot /path.png` renders the window to a PNG a few seconds after launch, then quits.
    private func scheduleSnapshotIfAsked() {
        guard let out = Self.arg("-snapshot") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, let window = self.view.window else { return }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try? image.pngData()?.write(to: URL(fileURLWithPath: out))
            print("snapshot written to \(out)")
            exit(0)
        }
    }
    #endif
}
