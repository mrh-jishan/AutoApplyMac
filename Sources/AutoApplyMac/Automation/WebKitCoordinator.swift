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
    
    public var isWorkdayURL: Bool {
        return currentURL.contains("myworkdayjobs.com") || currentURL.contains("myworkday.com")
    }
    
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
    
    // MARK: - Workday Automation Helpers
    
    public func workdayStartApply() async -> Bool {
        guard let wv = webView else { return false }
        let script = """
        (() => {
            // 1. If apply options modal is already open, click "Autofill with Resume"
            const resumeBtn = document.querySelector('[data-automation-id="autofillWithResume"], [data-automation-id="applyWithResume"]');
            if (resumeBtn) {
                resumeBtn.click();
                return { action: 'clicked_autofill_with_resume' };
            }
            
            // 2. Otherwise click "Apply" button on job posting
            const applyBtn = document.querySelector('[data-automation-id="adventureButton"], [data-automation-id="applyButton"], a[href*="/apply/"], button[aria-label*="Apply" i]');
            if (applyBtn) {
                applyBtn.click();
                setTimeout(() => {
                    const modalOption = document.querySelector('[data-automation-id="autofillWithResume"]');
                    if (modalOption) modalOption.click();
                }, 600);
                return { action: 'clicked_apply_button' };
            }
            return { action: 'none_found' };
        })()
        """
        do {
            _ = try await wv.evaluateJavaScript(script)
            statusMessage = "Workday: Starting application flow..."
            return true
        } catch {
            statusMessage = "Workday error: \(error.localizedDescription)"
            return false
        }
    }
    
    public func workdayAdvanceStep() async -> Bool {
        guard let wv = webView else { return false }
        let script = """
        (() => {
            const nextBtn = document.querySelector('[data-automation-id="bottom-navigation-next-button"], button[data-automation-id*="next" i], button[data-automation-id="page-footer-next"]');
            if (nextBtn && !nextBtn.disabled) {
                nextBtn.click();
                return true;
            }
            const altNext = Array.from(document.querySelectorAll('button')).find(b => {
                const t = b.innerText.trim().toLowerCase();
                return t === 'next' || t === 'continue' || t === 'save and continue';
            });
            if (altNext && !altNext.disabled) {
                altNext.click();
                return true;
            }
            return false;
        })()
        """
        do {
            if let res = try await wv.evaluateJavaScript(script) as? Bool, res {
                statusMessage = "Workday: Advanced to next step"
                return true
            } else {
                statusMessage = "Workday: Next button not found or disabled"
                return false
            }
        } catch {
            statusMessage = "Workday navigation error: \(error.localizedDescription)"
            return false
        }
    }
    
    public func triggerResumeUpload() async -> Bool {
        guard let wv = webView else { return false }
        let script = """
        (() => {
            const fileInput = document.querySelector('input[type="file"], input[data-automation-id*="upload" i]');
            if (fileInput) {
                fileInput.click();
                return true;
            }
            const dropZone = document.querySelector('[data-automation-id="file-upload-drop-zone"], [data-automation-id*="file" i]');
            if (dropZone) {
                dropZone.click();
                return true;
            }
            return false;
        })()
        """
        do {
            let res = try await wv.evaluateJavaScript(script) as? Bool ?? false
            if res {
                statusMessage = "Workday: Resume upload dialog triggered"
            }
            return res
        } catch {
            return false
        }
    }
    
    // MARK: - Script Injection & Autofill
    
    public func executeFormAutofill(candidate: CandidateProfile) async -> [String: Any] {
        guard let wv = webView else { return ["success": false, "error": "No webView"] }
        
        let fullName = escapeJS(candidate.fullName)
        let email = escapeJS(candidate.email)
        let phone = escapeJS(candidate.phone)
        let address = escapeJS(candidate.address)
        let city = escapeJS(candidate.city)
        let state = escapeJS(candidate.state)
        let postalCode = escapeJS(candidate.postalCode)
        let country = escapeJS(candidate.country)
        let linkedin = escapeJS(candidate.linkedinURL)
        let github = escapeJS(candidate.githubURL)
        let portfolio = escapeJS(candidate.portfolioURL)
        let isUSCitizen = candidate.isUSCitizen
        let requiresSponsorship = candidate.requiresSponsorship
        let eeocGender = escapeJS(candidate.eeocGender)
        let eeocRace = escapeJS(candidate.eeocRace)
        let eeocVeteran = escapeJS(candidate.eeocVeteran)
        let eeocDisability = escapeJS(candidate.eeocDisability)
        
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
            
            // Helper for native React / Angular setter to update Virtual DOM fibers
            const setNativeValue = (el, value) => {
                if (!el || value === undefined || value === null) return;
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
            
            const fillInput = (selectors, val, label) => {
                if (!val) return false;
                for (const sel of selectors) {
                    const el = document.querySelector(sel);
                    if (el && !el.disabled) {
                        setNativeValue(el, val);
                        results.filled.push(label);
                        return true;
                    }
                }
                return false;
            };
            
            // 1. First & Last Name splitting
            const rawFullName = '\(fullName)'.trim();
            const nameParts = rawFullName.split(/\\s+/);
            const firstName = nameParts[0] || '';
            const lastName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : nameParts[0] || '';
            
            fillInput([
                'input[data-automation-id="legalNameSection_firstName"]',
                'input[data-automation-id*="firstName" i]',
                '#first_name',
                'input[name*="first_name" i]',
                'input[name="firstName"]',
                'input[autocomplete="given-name"]',
                'input[aria-label*="first name" i]'
            ], firstName, 'First Name');
            
            fillInput([
                'input[data-automation-id="legalNameSection_lastName"]',
                'input[data-automation-id*="lastName" i]',
                '#last_name',
                'input[name*="last_name" i]',
                'input[name="lastName"]',
                'input[autocomplete="family-name"]',
                'input[aria-label*="last name" i]'
            ], lastName, 'Last Name');
            
            // If separate first/last name didn't match, try full name input
            if (!document.querySelector('input[data-automation-id="legalNameSection_firstName"]') && !document.querySelector('#first_name')) {
                fillInput([
                    'input[name*="name" i]',
                    '#_systemfield_name',
                    'input[autocomplete="name"]',
                    'input[placeholder*="full name" i]'
                ], rawFullName, 'Full Name');
            }
            
            // 2. Email Address
            fillInput([
                'input[data-automation-id="email"]',
                'input[data-automation-id*="email" i]',
                '#email',
                'input[type="email"]',
                '#_systemfield_email',
                'input[autocomplete="email"]',
                'input[name*="email" i]'
            ], '\(email)', 'Email');
            
            // 3. Phone Number
            fillInput([
                'input[data-automation-id="phone-number"]',
                'input[data-automation-id*="phone" i]',
                '#phone',
                'input[type="tel"]',
                'input[autocomplete="tel"]',
                'input[name*="phone" i]',
                'input[aria-label*="phone" i]'
            ], '\(phone)', 'Phone');
            
            // 4. Address Components
            let derivedAddress = '\(address)';
            let derivedCity = '\(city)';
            let derivedState = '\(state)';
            let derivedZip = '\(postalCode)';
            
            if ((!derivedCity || !derivedState || !derivedZip) && derivedAddress.includes(',')) {
                const parts = derivedAddress.split(',').map(s => s.trim());
                if (parts.length >= 3) {
                    if (!derivedCity) derivedCity = parts[1];
                    const stateZip = parts[2].split(/\\s+/);
                    if (!derivedState && stateZip.length > 0) derivedState = stateZip[0];
                    if (!derivedZip && stateZip.length > 1) derivedZip = stateZip[1];
                }
            }
            
            fillInput([
                'input[data-automation-id="addressSection_addressLine1"]',
                'input[data-automation-id*="addressLine1" i]',
                '#job_application_location',
                'input[name*="location" i]',
                'input[name*="address" i]',
                'input[autocomplete="address-line1"]',
                'input[placeholder*="address" i]'
            ], derivedAddress, 'Address');
            
            fillInput([
                'input[data-automation-id="addressSection_city"]',
                'input[data-automation-id*="city" i]',
                'input[autocomplete="address-level2"]',
                'input[name*="city" i]',
                '#city'
            ], derivedCity, 'City');
            
            fillInput([
                'input[data-automation-id="addressSection_postalCode"]',
                'input[data-automation-id*="postalCode" i]',
                'input[autocomplete="postal-code"]',
                'input[name*="zip" i]',
                'input[name*="postal" i]',
                '#postal_code',
                '#zip_code'
            ], derivedZip, 'Postal Code');
            
            fillInput([
                'input[data-automation-id="addressSection_countryRegion"]',
                'input[autocomplete="address-level1"]',
                'input[name*="state" i]',
                '#state'
            ], derivedState, 'State');
            
            // 5. Workday Dropdown Selectors
            const phoneDeviceBtn = document.querySelector('button[data-automation-id="phone-device-type"]');
            if (phoneDeviceBtn) {
                phoneDeviceBtn.click();
                setTimeout(() => {
                    const mobileOpt = Array.from(document.querySelectorAll('[role="option"], [data-automation-id*="promptOption"]'))
                        .find(el => el.innerText && el.innerText.toLowerCase().includes('mobile'));
                    if (mobileOpt) mobileOpt.click();
                }, 200);
                results.filled.push('Phone Type: Mobile');
            }
            
            const sourceBtn = document.querySelector('button[data-automation-id="sourceDropdown"]');
            if (sourceBtn) {
                sourceBtn.click();
                setTimeout(() => {
                    const opt = Array.from(document.querySelectorAll('[role="option"], [data-automation-id*="promptOption"]'))
                        .find(el => el.innerText && (el.innerText.toLowerCase().includes('linkedin') || el.innerText.toLowerCase().includes('career site') || el.innerText.toLowerCase().includes('job board')));
                    if (opt) opt.click();
                }, 200);
                results.filled.push('Source: Career Site/LinkedIn');
            }
            
            const countryBtn = document.querySelector('button[data-automation-id="countryDropdown"]');
            if (countryBtn && '\(country)') {
                countryBtn.click();
                setTimeout(() => {
                    const opt = Array.from(document.querySelectorAll('[role="option"], [data-automation-id*="promptOption"]'))
                        .find(el => el.innerText && el.innerText.toLowerCase().includes('\(country)'.toLowerCase()));
                    if (opt) opt.click();
                }, 200);
                results.filled.push('Country: \(country)');
            }
            
            // Prior Employee (select "No")
            document.querySelectorAll('fieldset, [data-automation-id*="previousWorker" i], [data-automation-id*="priorEmployee" i]').forEach(fs => {
                const radios = fs.querySelectorAll('input[type="radio"], [role="radio"]');
                radios.forEach(r => {
                    const label = (r.labels && r.labels[0] ? r.labels[0].innerText : r.parentElement ? r.parentElement.innerText : '').toLowerCase();
                    if (label.includes('no')) {
                        r.click();
                        results.filled.push('Prior Employee: No');
                    }
                });
            });
            
            // 6. LinkedIn / GitHub / Website
            fillInput([
                'input[data-automation-id*="linkedin" i]',
                'input[name*="linkedin" i]',
                'input[placeholder*="linkedin" i]',
                'input[id*="linkedin" i]',
                'input[aria-label*="linkedin" i]'
            ], '\(linkedin)', 'LinkedIn');
            
            fillInput([
                'input[data-automation-id*="github" i]',
                'input[name*="github" i]',
                'input[placeholder*="github" i]',
                'input[id*="github" i]'
            ], '\(github)', 'GitHub');
            
            fillInput([
                'input[data-automation-id="website"]',
                'input[data-automation-id*="website" i]',
                'input[data-automation-id*="url" i]',
                'input[name*="website" i]',
                'input[placeholder*="website" i]',
                'input[name*="portfolio" i]'
            ], '\(portfolio)', 'Website');
            
            // 7. Work Authorization & Sponsorship Toggles (Buttons & Radios)
            const authTarget = \(isUSCitizen) ? 'yes' : 'no';
            const sponsorTarget = \(requiresSponsorship) ? 'yes' : 'no';
            
            document.querySelectorAll('fieldset, div[role="radiogroup"], .wd-form-group, div').forEach(group => {
                const text = (group.innerText || '').toLowerCase();
                if ((text.includes('authorized to work') || text.includes('work authorization') || text.includes('legal right to work')) && !text.includes('sponsorship')) {
                    const radios = group.querySelectorAll('input[type="radio"], button, [role="radio"]');
                    radios.forEach(btn => {
                        const label = (btn.innerText || (btn.labels && btn.labels[0] ? btn.labels[0].innerText : btn.parentElement ? btn.parentElement.innerText : '')).trim().toLowerCase();
                        if (label === authTarget || label.startsWith(authTarget + ' ') || label.startsWith(authTarget + ',')) {
                            btn.click();
                            results.filled.push('Work Auth: ' + authTarget);
                        }
                    });
                }
                if (text.includes('sponsorship') || text.includes('require visa') || text.includes('future require')) {
                    const radios = group.querySelectorAll('input[type="radio"], button, [role="radio"]');
                    radios.forEach(btn => {
                        const label = (btn.innerText || (btn.labels && btn.labels[0] ? btn.labels[0].innerText : btn.parentElement ? btn.parentElement.innerText : '')).trim().toLowerCase();
                        if (label === sponsorTarget || label.startsWith(sponsorTarget + ' ') || label.startsWith(sponsorTarget + ',')) {
                            btn.click();
                            results.filled.push('Sponsorship: ' + sponsorTarget);
                        }
                    });
                }
            });
            
            // 8. Equal Opportunity Demographic Radios
            const eeocTargets = [
                '\(eeocGender)'.toLowerCase(),
                '\(eeocRace)'.toLowerCase(),
                '\(eeocVeteran)'.toLowerCase(),
                '\(eeocDisability)'.toLowerCase(),
                'decline', 'not a protected veteran', 'do not have a disability', 'i do not wish', 'male', 'female'
            ].filter(t => t.length > 0 && !t.includes('decline to self-identify'));
            
            document.querySelectorAll('input[type="radio"], [role="radio"]').forEach(inp => {
                const label = (inp.labels && inp.labels[0] ? inp.labels[0].innerText : inp.parentElement ? inp.parentElement.innerText : '').toLowerCase();
                const matched = eeocTargets.some(target => label.includes(target)) || label.includes('decline') || label.includes('not a protected veteran') || label.includes('do not have a disability');
                if (matched && !inp.checked) {
                    inp.click();
                    results.filled.push('EEOC: ' + label.slice(0, 20));
                }
            });
            
            // 9. Terms & Agreement Checkboxes
            document.querySelectorAll('input[type="checkbox"]').forEach(cb => {
                const label = (cb.labels && cb.labels[0] ? cb.labels[0].innerText : cb.parentElement ? cb.parentElement.innerText : '').toLowerCase();
                if (label.includes('agree') || label.includes('certify') || label.includes('consent') || label.includes('acknowledge') || label.includes('confirm')) {
                    if (!cb.checked) {
                        cb.click();
                        results.filled.push('Terms Accepted');
                    }
                }
            });
            
            // Signature text
            fillInput([
                'input[data-automation-id*="signature" i]',
                'input[aria-label*="signature" i]',
                'input[placeholder*="signature" i]',
                '#signature'
            ], rawFullName, 'Signature');
            
            // 10. Auto-Trigger Resume File Dialog
            const fileInput = document.querySelector('input[type="file"], [data-automation-id="file-upload-drop-zone"], #resume, input[name*="resume" i]');
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
                statusMessage = "Navigating to embedded application form..."
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
