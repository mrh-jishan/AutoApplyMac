# AutoApply Pro - Technical Architecture & Specifications

**Document Version:** 2.0.0  
**Target Platform:** macOS 14.0+ (Universal Apple Silicon & Intel)  
**Primary Frameworks:** SwiftUI, WebKit, SQLite3, PDFKit, Process Subprocesses  
**Binary Output:** `AutoApply.app`

---

## 1. System Architecture Overview

AutoApply Pro is divided into four distinct architectural layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                       │
│    (SwiftUI 3-Pane NavigationSplitView, SetupWizardView,    │
│            WebBrowserView, SettingsView, InspectorView)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────┐
│                    Automation & AI Layer                    │
│   ┌───────────────────────────┐  ┌────────────────────────┐ │
│   │    WebKitCoordinator      │  │  AIAssistantService    │ │
│   │ (WKUIDelegate file attach,│  │(CLI agy/claude/codex,  │ │
│   │ DOM input automation)     │  │ Gemini API, PDFKit)    │ │
│   └───────────────────────────┘  └────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────┐
│                  Daemon & Crawler Services                  │
│   ┌───────────────────────────┐  ┌────────────────────────┐ │
│   │    LightpandaService      │  │     ResumeMatcher      │ │
│   │ (Bundled headless browser,│  │(Dynamic role scoring,  │ │
│   │ multi-portal API scraper) │  │ semantic AI matching)  │ │
│   └───────────────────────────┘  └────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────┐
│                   Data Persistence Layer                    │
│     SQLite 3 Engine (WAL Mode) @ ~/Library/Application      │
│                Support/AutoApplyPro/database/               │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Persistence Layer: SQLite Relational Schema

AutoApply Pro maintains a robust, local SQLite database configured with `PRAGMA journal_mode = WAL` (Write-Ahead Logging) for high-concurrency read/write operations without locking the UI.

### 2.1 Schema Definition

```sql
-- Companies and Saturation Guard
CREATE TABLE IF NOT EXISTS companies (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    domain TEXT,
    careers_portal TEXT,
    application_count INTEGER DEFAULT 0,
    max_allowed INTEGER DEFAULT 2,
    is_blocked INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Discovered Job Postings
CREATE TABLE IF NOT EXISTS job_postings (
    id TEXT PRIMARY KEY,
    portal_source TEXT NOT NULL,
    external_job_id TEXT,
    company_name TEXT NOT NULL,
    title TEXT NOT NULL,
    url TEXT NOT NULL UNIQUE,
    location_raw TEXT,
    is_remote INTEGER DEFAULT 1,
    salary_min REAL,
    salary_max REAL,
    description_text TEXT,
    matched_resume TEXT,
    status TEXT DEFAULT 'discovered',
    discard_reason TEXT,
    discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Verified Application Audit Ledger
CREATE TABLE IF NOT EXISTS applications (
    id TEXT PRIMARY KEY,
    company_name TEXT NOT NULL,
    job_title TEXT NOT NULL,
    req_id TEXT,
    url TEXT NOT NULL,
    resume_path TEXT NOT NULL,
    status TEXT NOT NULL,
    confirmation_url TEXT,
    confirmation_text TEXT,
    review_screenshot TEXT,
    submitted_screenshot TEXT,
    evidence TEXT,
    submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Recruiter Outreach Campaigns
CREATE TABLE IF NOT EXISTS outreach_campaigns (
    id TEXT PRIMARY KEY,
    company_name TEXT NOT NULL,
    recruiter_name TEXT NOT NULL,
    recruiter_title TEXT,
    recruiter_email TEXT,
    linkedin_url TEXT,
    role_targeted TEXT,
    resume_attached TEXT NOT NULL,
    email_status TEXT DEFAULT 'pending',
    linkedin_status TEXT DEFAULT 'pending',
    sent_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Candidate Profile
CREATE TABLE IF NOT EXISTS candidate_profile (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    address TEXT,
    city TEXT,
    state TEXT,
    postal_code TEXT,
    country TEXT DEFAULT 'United States',
    is_us_citizen INTEGER DEFAULT 1,
    requires_sponsorship INTEGER DEFAULT 0,
    linkedin_url TEXT,
    github_url TEXT,
    portfolio_url TEXT,
    profession TEXT,
    target_titles TEXT,
    only_remote INTEGER DEFAULT 1,
    require_approval INTEGER DEFAULT 1,
    resumes_json TEXT,
    eeoc_gender TEXT,
    eeoc_race TEXT,
    eeoc_veteran TEXT,
    eeoc_disability TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for zero-latency queries
CREATE INDEX IF NOT EXISTS idx_postings_status ON job_postings(status);
CREATE INDEX IF NOT EXISTS idx_postings_portal ON job_postings(portal_source);
CREATE INDEX IF NOT EXISTS idx_applications_company ON applications(company_name);
```

---

## 3. Automation Layer

### 3.1 WebKit Foreground Browser (`WebKitCoordinator`)
- **Interactive UI:** Hosts a custom-configured `WKWebView` with modern Safari user-agent masking.
- **Silent Resume Attachment:** Implements `WKUIDelegate`:
  ```swift
  func webView(_ webView: WKWebView,
               runOpenPanelWith parameters: WKOpenPanelParameters,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping ([URL]?) -> Void)
  ```
  Intercepts standard HTML `<input type="file">` dialogs and fulfills them programmatically using `activeResumePath` without user file picker intervention.
- **Embedded ATS Iframe Detection & Auto-Resolution:** Pages embedding Greenhouse, Ashby, or Lever within cross-origin iframes (e.g., `axiomlaw.com` embedding `job-boards.greenhouse.io`) are detected dynamically. When Autofill is invoked, `WebKitCoordinator` navigates directly to the unconstrained ATS form URL, mounts React/Remix components natively, and performs full autofill.
- **React/Angular Autofill Injection:** Injects JavaScript targeting common ATS selectors (Workday, Greenhouse, Lever, Ashby) setting properties via `Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set.call(input, val)` and dispatching `input` and `change` bubbling events to notify reactive frontends. Separates First Name and Last Name automatically.

### 3.2 Multi-Portal Crawling Engine (`LightpandaService`)
- High-speed headless automation and direct ATS discovery daemon.
- **LinkedIn Jobs Crawler:**
  - Connects to LinkedIn's public guest search endpoint (`https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search`).
  - Automatically queries remote positions (`f_WT=2`) using the candidate's target job titles.
  - Parses job cards: title, company name, direct job view URL, and location.
- **Workday Jobs Crawler:**
  - Queries Workday CXS (Candidate Experience Services) public JSON endpoints across enterprise companies (NVIDIA, Adobe, Target, Broadcom, Autodesk, etc.).
  - Sends structured search payloads (`appliedFacets: {}, limit: 20, searchText: ...`).
  - Constructs direct application URLs: `https://{company}.myworkdayjobs.com/en-US/{board}/job/{externalPath}`.
- **Lever Jobs Crawler:**
  - Connects to Lever's public postings API (`https://api.lever.co/v0/postings/{company}?mode=json`).
  - Automatically queries remote postings across top Lever boards (Palantir, Spotify, Rover, Wealthfront, Kinsta).
  - Retrieves clean job title, direct application URL, and remote classification.
- **Greenhouse & Ashby Crawlers:**
  - Direct REST board scraping across top remote employers.
- **Dynamic Crawl Filtering:** Evaluates postings against `ProfileService.shared.profile.targetJobTitles` and profession metadata rather than static keyword sets. Enforces company saturation guard (maximum 2 submissions per company).

---

## 4. AI Engine Architecture (`AIAssistantService`)

AutoApply Pro is designed to work both connected and completely air-gapped:

### 4.1 CLI Agent Integration (Non-Interactive Process Dispatch)
The app dynamically checks the host machine's environment using login shell wrappers (`/bin/zsh -l -c`) to inherit user path variables and authentication credentials:
- **`agy` (Google Antigravity):** Invocations via `agy -p "<prompt>"`.
- **`claude` (Anthropic Claude Code):** Invocations via `claude -p "<prompt>"`.
- **`codex` (OpenAI Codex):** Invocations via `codex exec "<prompt>"`.

### 4.2 Direct Gemini REST API
Direct HTTPS POST requests to `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={API_KEY}` with strict `responseMimeType: application/json` enforcement.

### 4.3 Offline Fallback (`PDFKit` Pattern Engine)
If no AI agent CLI is detected and no network API key is configured, `ResumeParser` falls back to high-fidelity offline text analysis using `PDFKit` and regular expression heuristics.

---

## 5. Security, Privacy & Sandboxing

1. **Local-First Design:** No candidate credentials, passwords, or resumes ever leave the local machine.
2. **Path Sanitization:** No absolute usernames or host paths are hardcoded. All file references use `FileManager.default.homeDirectoryForCurrentUser` or `AppPaths.shared.appSupportDir`.
3. **App Transport Security:** Secure HTTPS connections enforced across all portal endpoints.
