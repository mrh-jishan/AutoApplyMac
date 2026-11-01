# AutoApply Pro for macOS 🚀

**AutoApply Pro** is a native, privacy-first macOS desktop application designed to discover, track, and automatically submit job applications across major applicant tracking systems (Greenhouse, Workday, Ashby, Lever, LinkedIn, and Google Jobs).

Built with **SwiftUI**, **WebKit**, and an **embedded SQLite relational database**, AutoApply Pro pairs a high-performance interactive foreground browser with background scraping powered by **Lightpanda** and intelligent resume extraction via **local AI agents** (`agy`, `claude`, `codex`) or direct **Gemini API**.

---

## ✨ Key Features

- **Universal Multi-Profession Support:** Works out of the box for any candidate in any industry—Software Engineering, Healthcare & Nursing, Corporate Finance, Sales & BD, Legal & Compliance, Digital Marketing, and more.
- **AI-Powered Resume Analysis:** Parses PDF resumes dynamically using your local terminal AI agents (`agy`, `claude`, `codex`) or the Gemini API, automatically extracting contact details, seniority, skills, and target roles.
- **Dynamic Multi-Resume Matching:** Upload multiple tailored resumes (e.g., Leadership, Specialist, Technical). AutoApply dynamically selects the best matching resume for each specific job opening.
- **Full-Page Profile & Settings Workspace:** No cramped modals or tiny popups. Candidate profile editing, multi-resume management, AI agent configurations, and SQLite database settings all live in an expansive full-screen workspace.
- **Multi-Portal Discovery Daemon:** Automatically crawls **Ashby**, **Greenhouse**, **LinkedIn**, **Workday**, and **Lever** for 100% remote roles matching your background.
- **Company Grouped Listings with Hyperlink Styling:** Job listings are organized into collapsible company sections with role counts (e.g. *NVIDIA (15 roles)*, *Rover (34 roles)*, *Affirm (2 roles)*). Job titles are styled as crisp clickable hyperlinks with external link indicators.
- **Embedded ATS Iframe Resolver:** Seamlessly detects cross-origin embedded Greenhouse, Ashby, and Lever forms (e.g. `axiomlaw.com?gh_jid=...`) and provides direct form navigation with 100% autofill and silent resume attachment.
- **Interactive WebKit Foreground Browser:** Seamlessly review application forms before submission with automated form pre-filling and silent file attachment via native `WKUIDelegate`.
- **Zero-Dependency Portability:** Bundles the high-speed `lightpanda` headless browser daemon inside the application bundle—no manual browser installations or node/npm runtimes required.
- **100% On-Device & Private:** All resumes, job history, application confirmations, and candidate profiles are stored locally in SQLite on your Mac (`~/Library/Application Support/AutoApplyPro/`). No cloud tracking.
- **Friendly Setup Wizard:** Step-by-step onboarding designed for both non-technical users and power users.

---

## 🖥️ System Requirements

- **Operating System:** macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- **Architecture:** Apple Silicon (M1/M2/M3/M4) or Intel x86_64
- **Dependencies:** None. Self-contained application bundle.
- **Optional AI Agents:** Google Antigravity CLI (`agy`), Claude Code CLI (`claude`), Codex CLI (`codex`), or a free Gemini API key.

---

## 🚀 Quick Start Guide

### 1. Launching the App
Double-click `AutoApply.app` located on your Desktop.

### 2. First-Time Setup Wizard (Non-Technical Users)
When you first launch the app, a friendly 4-step wizard will appear:
1. **Resume Upload:** Click **"Choose PDF Resume..."** to select your existing resume from Finder. AutoApply's AI agent will instantly analyze the document.
2. **Review Extracted Info:** Confirm your name, email, phone number, and location.
3. **Set Job Targets:** Enter your preferred job titles (e.g., *Clinical Specialist*, *Senior Growth Lead*, *Staff Engineer*) and toggle remote preferences.
4. **Launch:** Click **"Launch AutoApply Pro"** to enter the main workspace.

### 3. Discovering Jobs
- Click **"Find Jobs"** in the top toolbar to automatically query Ashby, Greenhouse, and career portals for positions matching your profile.
- Discoveries are automatically deduplicated and queued in your **Pending Queue**.

### 4. Applying with 1-Click Form Autofill
- Select any job from the queue list.
- Click **"Open in WebKit Browser"**.
- Click **"Autofill"** (or the magic wand icon in the inspector). AutoApply fills your name, email, phone, LinkedIn profile, work authorization toggles, and attaches the matching resume PDF.
- Review the form and click **Submit**.

---

## 🤖 AI Engine Configuration

AutoApply Pro supports multiple AI backends, configurable in **Settings > AI Engine**:

| Mode | Description | How It Works |
|---|---|---|
| **Auto-Detect (Default)** | Detects local CLI agents or Gemini API key automatically. | Checks for `agy`, `claude`, `codex`, or `GEMINI_API_KEY`. |
| **Antigravity CLI (`agy`)** | Uses Google Antigravity terminal agent. | Executes `agy -p` in non-interactive batch mode. |
| **Claude Code (`claude`)** | Uses Anthropic Claude CLI. | Executes `claude -p` in non-interactive mode. |
| **Codex CLI (`codex`)** | Uses OpenAI Codex CLI. | Executes `codex exec` in non-interactive mode. |
| **Google Gemini API** | Direct cloud REST API call. | Enter your API key from Google AI Studio. |
| **Offline Native** | Zero network or AI requirements. | Uses Apple `PDFKit` and built-in heuristic pattern matchers. |

---

## 🛠️ Developer & Build Instructions

If you are modifying or compiling AutoApply Pro from source:

### Clone & Build
```bash
cd AutoApplyMac

# Build debug binary
swift build

# Run unit tests
swift test
```

### Packaging Self-Contained `.app` Bundle
Run the packaging script to generate the production-ready universal macOS bundle with icons and helper daemons:
```bash
./package_app.sh
```
This produces `/Users/<you>/Desktop/AutoApply.app` containing:
- `Contents/MacOS/AutoApply`
- `Contents/Resources/AppIcon.icns`
- `Contents/Helpers/lightpanda`
- `Contents/Info.plist`

---

## 📂 File & Storage Locations

All application state is kept cleanly separated from system folders:

- **SQLite Database:** `~/Library/Application Support/AutoApplyPro/database/autoapply.sqlite`
- **Managed Resumes:** `~/Library/Application Support/AutoApplyPro/resumes/`
- **Application Receipts:** `~/Library/Application Support/AutoApplyPro/screenshots/`
- **Execution Logs:** `~/Library/Application Support/AutoApplyPro/logs/`

---

## 📄 License & Attribution

Copyright © 2026 AutoApply Pro. Built with Apple Swift, SwiftUI, and WebKit.
Lightpanda binary bundled under the Lightpanda Browser Open Source License.
