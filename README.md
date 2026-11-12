# Ski PDF

A complete PDF toolkit for iPhone and iPad. Everything runs on the device.

**PDF:** Merge, Split, Compress, PDF to Images, Images to PDF
**Organize:** Reorder, Rotate, Delete, Extract pages, Print Studio (page ranges, pages per sheet, B&W, two-sided)
**Convert:** HTML / web page to PDF, Scan to PDF (with OCR), Doc to PDF (Word, Excel, PowerPoint, Pages, Numbers, Keynote, RTF, text), OCR, Extract Text
**Security:** Lock, Unlock, Watermark, Sign (draw or type, saved signatures, date stamp), Fill Forms, Flatten
**Image tools:** Compress, Resize, Convert (JPEG/PNG/HEIC), Strip Metadata
**View & Export:** PDF viewer (search, highlight, underline, strike-out, notes, form filling, print), Page Numbers, Metadata viewer/editor

Files you make are in the Files tab and in the Files app under On My iPhone › Ski PDF. PDFs can be opened in Ski PDF from other apps.

## Install (TestFlight)

Every push to `main` builds, signs and uploads the app to TestFlight.

One-time setup:
1. This repo › Settings › Secrets and variables › Actions › New repository secret — add the same four secrets used for Ski Steps:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (full text of the .p8 key), `APPLE_TEAM_ID`.
2. After the first TestFlight run registers the app ID, create the app: App Store Connect › Apps › **+** › New App, bundle ID `com.skistudio.pdf`. Then re-run the TestFlight workflow.

## Project

SwiftUI + PDFKit + Vision + VisionKit + PencilKit. The Xcode project is generated from `project.yml` with XcodeGen.
