# Landing Page SEO Optimization

## Date: 2026-04-15

## What was done

### 1. Enhanced Meta Tags (index.html)
- **Title**: Changed from generic to keyword-rich: "Speechy — AI Speech to Text for macOS | Offline Voice Recognition"
- **Description**: Expanded to ~160 chars with key features, language count, and CTA (free trial)
- **Keywords**: Expanded from 8 to 12 keywords including long-tail terms
- **Added**: `robots` meta (index, follow), `author` meta, `canonical` link

### 2. Open Graph Improvements
- Added `og:url`, `og:site_name`, `og:locale`
- Added `og:image:width`, `og:image:height`, `og:image:alt`
- Changed `og:image` from relative to absolute URL (`https://speechy.frkn.com.tr/og-image.png`)

### 3. Twitter Card Completion
- Added `twitter:title`, `twitter:description`, `twitter:image:alt`
- Changed image URL from relative to absolute

### 4. JSON-LD Structured Data
- Added `SoftwareApplication` schema with:
  - Application category, OS, price/offer (free trial)
  - Feature list, author, screenshot, version

### 5. Semantic HTML
- Wrapped main content sections in `<main>` tag

### 6. New Files Created
- **robots.txt**: Allow all crawlers, disallow `/api/`, sitemap reference
- **sitemap.xml**: All 3 pages (index, privacy, terms) with priorities and lastmod dates

### 7. Sub-pages SEO (privacy.html, terms.html)
- Added keyword-rich titles with brand suffix
- Enhanced meta descriptions
- Added `canonical`, `robots`, OG tags (`og:title`, `og:description`, `og:url`, `og:type`, `og:site_name`)

### 8. Image Alt Text
- Improved logo alt text to include descriptive keywords

## Files Modified
- `landing/index.html`
- `landing/privacy.html`
- `landing/terms.html`

## Files Created
- `landing/robots.txt`
- `landing/sitemap.xml`
