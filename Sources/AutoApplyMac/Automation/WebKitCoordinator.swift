import Foundation
import WebKit
import AppKit

public final class WebKitCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, ObservableObject {
    public static let shared = WebKitCoordinator()
    
    @Published public var currentURL: String = ""
    @Published public var pageTitle: String = ""
    @Published public var isLoading: Bool = false
    @Published public var estimatedProgress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var detectedDirectIframeURL: String? = nil
    @Published public var detectedDirectApplyURL: String? = nil
    @Published public var detectedJobCompany: String? = nil
    @Published public var detectedJobTitle: String? = nil
    @Published public var detectedJobPlatform: String? = nil
    @Published public var pendingAutofillAfterNavigation: Bool = false
    
    public var activeResumePath: String? = nil
    public weak var webView: WKWebView?
    
    private override init() {
        super.init()
    }
    
    public func createConfiguredWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        
        self.webView = wv
        return wv
    }
    
    public func load(url string: String) {
        guard let url = URL(string: string) else { return }
        statusMessage = "Loading \(url.host ?? string)..."
        webView?.load(URLRequest(url: url))
    }
    
    // MARK: - WKUIDelegate (Silent File Attachment & Popup Redirection)
    
    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
            print("WKUIDelegate: popup / target=_blank navigation redirected to active view: \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    public func webView(_ webView: WKWebView,
                        runOpenPanelWith parameters: WKOpenPanelParameters,
                        initiatedByFrame frame: WKFrameInfo,
                        completionHandler: @escaping ([URL]?) -> Void) {
        var targetResume = activeResumePath
        if targetResume == nil || !FileManager.default.fileExists(atPath: targetResume!) {
            targetResume = ProfileService.shared.profile.resumes.first(where: { $0.isDefault })?.filePath
                ?? ProfileService.shared.profile.resumes.first?.filePath
        }
        
        if let resume = targetResume, FileManager.default.fileExists(atPath: resume) {
            print("WKUIDelegate: silently providing resume URL: \(resume)")
            statusMessage = "Attached resume: \(URL(fileURLWithPath: resume).lastPathComponent)"
            completionHandler([URL(fileURLWithPath: resume)])
        } else {
            completionHandler(nil)
        }
    }
    
    public func webView(_ webView: WKWebView,
                        runJavaScriptAlertPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo,
                        completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    public func webView(_ webView: WKWebView,
                        runJavaScriptConfirmPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo,
                        completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    public func webView(_ webView: WKWebView,
                        runJavaScriptTextInputPanelWithPrompt prompt: String,
                        defaultText: String?,
                        initiatedByFrame frame: WKFrameInfo,
                        completionHandler: @escaping (String?) -> Void) {
        completionHandler(defaultText)
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                print("WKNavigationDelegate: opening popup / new window link in active tab: \(url.absoluteString)")
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURL = webView.url?.absoluteString ?? ""
        pageTitle = webView.title ?? ""
        statusMessage = "Page loaded: \(pageTitle)"
        
        // Scan page for embedded ATS iframes (Greenhouse, Lever, Ashby)
        detectEmbeddedATSIframe()
        
        // Scan page for LinkedIn job postings and resolve direct ATS application link
        if currentURL.contains("linkedin.com/jobs/view") {
            resolveLinkedInJobDirectApply()
        } else {
            detectedDirectApplyURL = nil
            detectedJobCompany = nil
            detectedJobTitle = nil
            detectedJobPlatform = nil
        }
        
        // If an automatic redirect occurred, auto-run autofill
        if pendingAutofillAfterNavigation {
            pendingAutofillAfterNavigation = false
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second for React hydration
                _ = await executeFormAutofill(candidate: ProfileService.shared.profile)
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        statusMessage = "Failed to load: \(error.localizedDescription)"
    }
    
    // MARK: - Embedded ATS Detection
    
    public func detectEmbeddedATSIframe() {
        guard let wv = webView else { return }
        let script = """
        (() => {
            const iframe = document.querySelector('iframe#grnhse_iframe, iframe[src*="greenhouse.io"], iframe[src*="lever.co"], iframe[src*="ashbyhq.com"]');
            if (iframe && iframe.src) {
                return iframe.src;
            }
            const params = new URLSearchParams(window.location.search);
            const jid = params.get('gh_jid') || params.get('job');
            if (jid && window.Grnhse && window.Grnhse.Settings && window.Grnhse.Settings.applicationURI) {
                return window.Grnhse.Settings.applicationURI + '&token=' + jid;
            }
            return null;
        })()
        """
        
        wv.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                if let directURL = result as? String, !directURL.isEmpty {
                    self?.detectedDirectIframeURL = directURL
                    print("Detected embedded ATS form at: \(directURL)")
                } else {
                    self?.detectedDirectIframeURL = nil
                }
            }
        }
    }
    
    // MARK: - LinkedIn Direct ATS Application Resolver
    
    public func resolveLinkedInJobDirectApply() {
        guard let wv = webView else { return }
        
        let extractScript = """
        (() => {
            let company = '';
            let title = '';
            const ldScript = document.querySelector('script[type="application/ld+json"]');
            if (ldScript) {
                try {
                    const data = JSON.parse(ldScript.innerText);
                    if (data.hiringOrganization && data.hiringOrganization.name) {
                        company = data.hiringOrganization.name;
                    }
                    if (data.title) {
                        title = data.title;
                    }
                } catch(e) {}
            }
            if (!company) {
                const compEl = document.querySelector('.topcard__org-name-link, .topcard__flavor, a[data-tracking-control-name="public_jobs_topcard-org-name"], .sub-nav-cta__optional-url');
                if (compEl) company = compEl.innerText.trim();
            }
            if (!title) {
                const titleEl = document.querySelector('.top-card-layout__title, .topcard__title, h1');
                if (titleEl) title = titleEl.innerText.trim();
            }
            return { company: company, title: title };
        })()
        """
        
        wv.evaluateJavaScript(extractScript) { [weak self] res, _ in
            guard let self = self,
                  let dict = res as? [String: String],
                  let company = dict["company"], !company.isEmpty,
                  let title = dict["title"], !title.isEmpty else {
                return
            }
            
            DispatchQueue.main.async {
                self.detectedJobCompany = company
                self.detectedJobTitle = title
                self.statusMessage = "Analyzing job: \(company) — \(title)..."
            }
            
            Task {
                if let directMatch = await self.findDirectATSApplication(company: company, title: title) {
                    await MainActor.run {
                        self.detectedDirectApplyURL = directMatch.url
                        self.detectedJobPlatform = directMatch.platform
                        self.statusMessage = "Direct \(directMatch.platform) apply form found for \(company)!"
                        self.wireUpLinkedInApplyButtons(directUrl: directMatch.url, platform: directMatch.platform)
                    }
                } else {
                    await MainActor.run {
                        self.wireUpLinkedInFallbackModal()
                    }
                }
            }
        }
    }
    
    private func wireUpLinkedInApplyButtons(directUrl: String, platform: String) {
        guard let wv = webView else { return }
        let js = """
        (() => {
            const directUrl = "\(escapeJS(directUrl))";
            const platform = "\(escapeJS(platform))";
            const btns = document.querySelectorAll('.top-card-layout__cta--primary, #topbar-apply, [data-modal*="apply"], button.sign-up-modal__outlet');
            btns.forEach(btn => {
                if (btn.innerText && btn.innerText.toLowerCase().includes('apply')) {
                    btn.innerHTML = 'Apply on ' + platform + ' ↗';
                    btn.style.backgroundColor = '#007A5A';
                    btn.style.color = '#FFFFFF';
                    btn.style.borderColor = '#007A5A';
                    btn.style.cursor = 'pointer';
                    btn.onclick = (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        window.location.href = directUrl;
                        return false;
                    };
                }
            });
        })()
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func wireUpLinkedInFallbackModal() {
        guard let wv = webView else { return }
        let js = """
        (() => {
            const btns = document.querySelectorAll('.top-card-layout__cta--primary, #topbar-apply');
            btns.forEach(btn => {
                btn.addEventListener('click', () => {
                    setTimeout(() => {
                        const overlay = document.querySelector('.modal__overlay');
                        if (overlay) {
                            overlay.classList.remove('invisible', 'pointer-events-none', 'opacity-0');
                            overlay.style.opacity = '1';
                            overlay.style.visibility = 'visible';
                            overlay.style.pointerEvents = 'auto';
                        }
                    }, 80);
                });
            });
        })()
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }
    
    public func findDirectATSApplication(company: String, title: String) async -> (url: String, platform: String)? {
        let cleanComp = company.lowercased()
            .replacingOccurrences(of: "\\b(inc|llc|corp|corporation|ltd|company|technologies)\\b\\.?", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let slug = cleanComp.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        guard !slug.isEmpty else { return nil }
        
        // 1. Greenhouse
        if let gh = await searchGreenhouse(slug: slug, title: title) {
            return (gh.url, "Greenhouse")
        }
        
        // 2. Ashby
        if let ashby = await searchAshby(slug: slug, title: title) {
            return (ashby.url, "Ashby")
        }
        
        // 3. Lever
        if let lever = await searchLever(slug: slug, title: title) {
            return (lever.url, "Lever")
        }
        
        return nil
    }
    
    private func searchGreenhouse(slug: String, title: String) async -> (url: String, name: String)? {
        guard let url = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(slug)/jobs") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 4.0
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else {
            return nil
        }
        
        var bestMatch: (url: String, title: String, score: Double)? = nil
        for job in jobs {
            if let jobTitle = job["title"] as? String,
               let jobURL = job["absolute_url"] as? String {
                let score = titleScore(candidate: jobTitle, target: title)
                if score >= 0.65 && score > (bestMatch?.score ?? 0.0) {
                    bestMatch = (jobURL, jobTitle, score)
                }
            }
        }
        if let best = bestMatch {
            return (best.url, best.title)
        }
        return nil
    }
    
    private func searchAshby(slug: String, title: String) async -> (url: String, name: String)? {
        guard let url = URL(string: "https://api.ashbyhq.com/posting-api/job-board/\(slug)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 4.0
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else {
            return nil
        }
        
        var bestMatch: (url: String, title: String, score: Double)? = nil
        for job in jobs {
            if let jobTitle = job["title"] as? String {
                let score = titleScore(candidate: jobTitle, target: title)
                if score >= 0.65 && score > (bestMatch?.score ?? 0.0) {
                    let jobURL = (job["jobUrl"] as? String) ?? (job["applyUrl"] as? String) ?? "https://jobs.ashbyhq.com/\(slug)"
                    bestMatch = (jobURL, jobTitle, score)
                }
            }
        }
        if let best = bestMatch {
            return (best.url, best.title)
        }
        return nil
    }
    
    private func searchLever(slug: String, title: String) async -> (url: String, name: String)? {
        guard let url = URL(string: "https://api.lever.co/v0/postings/\(slug)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 4.0
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let postings = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var bestMatch: (url: String, title: String, score: Double)? = nil
        for post in postings {
            if let postTitle = post["text"] as? String {
                let score = titleScore(candidate: postTitle, target: title)
                if score >= 0.65 && score > (bestMatch?.score ?? 0.0) {
                    let jobURL = (post["hostedUrl"] as? String) ?? (post["applyUrl"] as? String) ?? ""
                    if !jobURL.isEmpty {
                        bestMatch = (jobURL, postTitle, score)
                    }
                }
            }
        }
        if let best = bestMatch {
            return (best.url, best.title)
        }
        return nil
    }
    
    private func titleScore(candidate: String, target: String) -> Double {
        let words1 = normalizeTitle(candidate)
        let words2 = normalizeTitle(target)
        if words1.joined(separator: " ") == words2.joined(separator: " ") { return 1.0 }
        
        let set1 = Set(words1)
        let set2 = Set(words2)
        guard !set1.isEmpty && !set2.isEmpty else { return 0.0 }
        
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        return Double(intersection.count) / Double(union.count)
    }
    
    private func normalizeTitle(_ s: String) -> [String] {
        let stopWords: Set<String> = ["at", "the", "a", "an", "in", "and", "&", "remote", "hybrid", "full-time", "fulltime"]
        var cleaned = s.lowercased()
        cleaned = cleaned.replacingOccurrences(of: "[\\(\\)\\[\\],\\-–—|/]", with: " ", options: .regularExpression)
        return cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !stopWords.contains($0) && !$0.isEmpty }
    }
    
    // MARK: - Snapshot Capture
    
    public func captureSnapshot(saveTo path: String) async -> Bool {
        guard let wv = webView else { return false }
        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            wv.takeSnapshot(with: config) { image, error in
                guard let img = image, error == nil else {
                    continuation.resume(returning: false)
                    return
                }
                if let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Script Injection & Autofill
    
    public func executeFormAutofill(candidate: CandidateProfile) async -> [String: Any] {
        guard let wv = webView else { return ["success": false, "error": "No webView"] }
        
        let fullName = escapeJS(candidate.fullName)
        let email = escapeJS(candidate.email)
        let phone = escapeJS(candidate.phone)
        let address = escapeJS(candidate.address)
        let linkedin = escapeJS(candidate.linkedinURL)
        let github = escapeJS(candidate.githubURL)
        let portfolio = escapeJS(candidate.portfolioURL)
        
        let fillScript = """
        (() => {
            const results = { filled: [], errors: [], requiresRedirect: false, directUrl: null };
            
            // Check if this page embeds a cross-origin Greenhouse/Lever/Ashby form
            const atsIframe = document.querySelector('iframe#grnhse_iframe, iframe[src*="greenhouse.io"], iframe[src*="lever.co"], iframe[src*="ashbyhq.com"]');
            if (atsIframe && atsIframe.src && !window.location.href.includes('job-boards.greenhouse.io') && !window.location.href.includes('boards.greenhouse.io')) {
                results.requiresRedirect = true;
                results.directUrl = atsIframe.src;
                return results;
            }
            
            const params = new URLSearchParams(window.location.search);
            const jid = params.get('gh_jid') || params.get('job');
            if (jid && window.Grnhse && window.Grnhse.Settings && window.Grnhse.Settings.applicationURI && !window.location.href.includes('job-boards.greenhouse.io')) {
                results.requiresRedirect = true;
                results.directUrl = window.Grnhse.Settings.applicationURI + '&token=' + jid;
                return results;
            }
            
            // Helper for native React / Angular setter
            const setNativeValue = (el, value) => {
                if (!el || !value) return;
                const proto = el instanceof HTMLInputElement ? window.HTMLInputElement.prototype : window.HTMLTextAreaElement.prototype;
                const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
                if (descriptor && descriptor.set) {
                    descriptor.set.call(el, value);
                } else {
                    el.value = value;
                }
                el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
                el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
                el.dispatchEvent(new Event('blur', { bubbles: true, composed: true }));
            };
            
            // 1. First & Last Name splitting
            const rawFullName = '\(fullName)'.trim();
            const nameParts = rawFullName.split(/\\s+/);
            const firstName = nameParts[0] || '';
            const lastName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : nameParts[0] || '';
            
            const firstInput = document.querySelector('#first_name, input[name*=\"first_name\" i], input[autocomplete=\"given-name\"], input[aria-label*=\"first name\" i]');
            if (firstInput && firstName) {
                setNativeValue(firstInput, firstName);
                results.filled.push('First Name');
            }
            
            const lastInput = document.querySelector('#last_name, input[name*=\"last_name\" i], input[autocomplete=\"family-name\"], input[aria-label*=\"last name\" i]');
            if (lastInput && lastName) {
                setNativeValue(lastInput, lastName);
                results.filled.push('Last Name');
            }
            
            if (!firstInput && !lastInput && rawFullName) {
                const fullInput = document.querySelector('input[name*=\"name\" i], #_systemfield_name, input[autocomplete=\"name\"], input[placeholder*=\"full name\" i]');
                if (fullInput) {
                    setNativeValue(fullInput, rawFullName);
                    results.filled.push('Full Name');
                }
            }
            
            // 2. Email Address
            const emailInput = document.querySelector('#email, input[type=\"email\"], #_systemfield_email, input[autocomplete=\"email\"], input[name*=\"email\" i]');
            if (emailInput && '\(email)') {
                setNativeValue(emailInput, '\(email)');
                results.filled.push('Email');
            }
            
            // 3. Phone Number
            const phoneInput = document.querySelector('#phone, input[type=\"tel\"], input[autocomplete=\"tel\"], input[name*=\"phone\" i], input[aria-label*=\"phone\" i]');
            if (phoneInput && '\(phone)') {
                setNativeValue(phoneInput, '\(phone)');
                results.filled.push('Phone');
            }
            
            // 4. Address & Location
            const addressInput = document.querySelector('#job_application_location, input[name*=\"location\" i], input[name*=\"address\" i], input[autocomplete=\"address-line1\"], input[placeholder*=\"address\" i]');
            if (addressInput && '\(address)') {
                setNativeValue(addressInput, '\(address)');
                results.filled.push('Location');
            }
            
            // 5. LinkedIn / GitHub / Website
            const linkedinInput = document.querySelector('input[name*=\"linkedin\" i], input[placeholder*=\"linkedin\" i], input[id*=\"linkedin\" i], input[aria-label*=\"linkedin\" i]');
            if (linkedinInput && '\(linkedin)') {
                setNativeValue(linkedinInput, '\(linkedin)');
                results.filled.push('LinkedIn');
            }
            
            const githubInput = document.querySelector('input[name*=\"github\" i], input[placeholder*=\"github\" i], input[id*=\"github\" i]');
            if (githubInput && '\(github)') {
                setNativeValue(githubInput, '\(github)');
                results.filled.push('GitHub');
            }
            
            const websiteInput = document.querySelector('input[name*=\"website\" i], input[placeholder*=\"website\" i], input[name*=\"portfolio\" i]');
            if (websiteInput && '\(portfolio)') {
                setNativeValue(websiteInput, '\(portfolio)');
                results.filled.push('Website');
            }
            
            // 6. Work Authorization & Sponsorship Toggles (Buttons & Radios)
            document.querySelectorAll('button').forEach(btn => {
                const text = btn.innerText.trim().toLowerCase();
                const parent = (btn.closest('div') ? btn.closest('div').innerText : '').toLowerCase();
                if (parent.includes('authorized') && text === 'yes') {
                    btn.click();
                    results.filled.push('Auth:Yes');
                }
                if (parent.includes('sponsorship') && text === 'no') {
                    btn.click();
                    results.filled.push('Sponsorship:No');
                }
            });
            
            // 7. Equal Opportunity Demographic Radios
            document.querySelectorAll('input[type=\"radio\"], input[type=\"checkbox\"]').forEach(inp => {
                const label = (inp.labels && inp.labels[0] ? inp.labels[0].innerText : '').toLowerCase();
                if (label.includes('male') || label.includes('asian') || label.includes('decline') || label.includes('i do not have a disability') || label.includes('not a protected veteran') || label.includes('agree') || label.includes('confirm')) {
                    if (!inp.checked) {
                        inp.click();
                        results.filled.push('Option: ' + label);
                    }
                }
            });
            
            // 8. Auto-Trigger Resume File Dialog
            const fileInput = document.querySelector('input[type=\"file\"], #resume, input[name*=\"resume\" i]');
            if (fileInput) {
                fileInput.click();
                results.filled.push('Resume Triggered');
            }
            
            return results;
        })()
        """
        
        do {
            let res = try await wv.evaluateJavaScript(fillScript)
            guard let dict = res as? [String: Any] else {
                statusMessage = "Form auto-filled successfully"
                return ["success": true]
            }
            
            // Handle cross-origin iframe redirection automatically
            if let requiresRedirect = dict["requiresRedirect"] as? Bool, requiresRedirect,
               let directUrl = dict["directUrl"] as? String, !directUrl.isEmpty {
                statusMessage = "Navigating to embedded Greenhouse application form..."
                pendingAutofillAfterNavigation = true
                load(url: directUrl)
                return ["success": true, "redirected": directUrl]
            }
            
            let filledList = dict["filled"] as? [String] ?? []
            if !filledList.isEmpty {
                statusMessage = "Auto-filled: \(filledList.joined(separator: ", "))"
            } else {
                statusMessage = "Form checked. No matching standard fields found."
            }
            return dict
        } catch {
            statusMessage = "Autofill error: \(error.localizedDescription)"
            return ["success": false, "error": error.localizedDescription]
        }
    }
    
    private func escapeJS(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
