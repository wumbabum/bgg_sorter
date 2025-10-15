# BoardGameGeek Advanced Search Styling Updates

## Overview
Updated the advanced search component CSS to closely match the authentic BoardGameGeek advanced search design at https://boardgamegeek.com/advsearch/boardgame.

## Key Changes Made

### 1. Table Structure
- **Border Style**: Changed to `1px solid #cccccc` matching BGG's bordered table
- **Cell Backgrounds**: Label cells use `#f8f8f8` gray background, input cells use `#ffffff`
- **Cell Borders**: Added right borders between cells (`border-right: 1px solid #cccccc`)

### 2. Typography & Fonts
- **Font Family**: Changed to `Verdana, Arial, sans-serif` (BGG's standard font)
- **Font Sizes**: Reduced to 11px for inputs and labels to match BGG's compact design
- **Colors**: Label text changed to `#000000`, help text to `#666666`

### 3. Form Controls
- **Input Styling**: 
  - Padding reduced to `2px 4px`
  - Border color changed to `#666666`
  - Removed border-radius (square corners like BGG)
  - Margins set to 0
- **Input Sizes**: 
  - Size 5 inputs: 50px width
  - Size 35 inputs: 250px width
  - Player select: 100px width

### 4. Button Design
- **BGG-Style Buttons**: 
  - Linear gradient background (`#ffffff` to `#e6e6e6`)
  - `#aaaaaa` borders with square corners
  - 11px Verdana font
  - Compact padding (4px 12px)
- **Button Container**: Left-aligned with gray background matching BGG's form bottom

### 5. Layout & Spacing
- **Collection Header**: 
  - Updated to match BGG's header style
  - Gray background (`#f8f8f8`)
  - Compact 16px title font
  - 11px subtitle font
- **Container**: Removed outer padding/margins to integrate with main content
- **Help Text**: 10px font size with proper BGG styling

### 6. BGG-Specific Details
- **Text Separators**: "to" text between range inputs styled with proper spacing
- **Table Width**: Maintains BGG's 25%/75% column ratio
- **Color Scheme**: Uses BGG's exact gray palette (#f8f8f8, #cccccc, #666666)
- **Responsive Design**: Maintains functionality on mobile while preserving BGG aesthetics

### 7. Advanced Search Toggle (Recent)
- **Smooth Toggle**: Fixed toggle button to properly show/hide advanced search component
- **URL Management**: Corrected URL parameter handling between `/collection` and `/collection?advanced_search=true`
- **No Page Reloads**: Uses `push_patch` instead of `push_navigate` for seamless UX
- **State Persistence**: Advanced search state properly maintained across interactions

### 8. Form Usability Enhancements (Recent)
- **Username Memory**: Added `autocomplete="on"` to all username input fields
- **Password Manager Safe**: Avoids triggering Bitwarden/1Password with semantic autocomplete
- **Consistent Inputs**: Unified autocomplete behavior across header, main search, and advanced search
- **Browser History**: Users can quickly re-enter frequent usernames like "wumbabum"

## Files Modified
- `/Users/joseph.toney/Work/sandbox/bgg_sorter/apps/web/assets/css/app.css`
  - Updated advanced search CSS sections (lines ~874-1165)
  - Cleaned up duplicate/outdated styles
  - Added BGG-specific responsive breakpoints
- `apps/web/lib/web/live/collection_live.ex`
  - Fixed `toggle_advanced_search` handler for no-username case
  - Changed from `push_navigate` to `push_patch` for smoother UX
- `apps/web/lib/web/components/header_component.ex`
  - Added `autocomplete="on"` to username input
- `apps/web/lib/web/components/search_component.ex` 
  - Added `autocomplete="on"` to main search input
- `apps/web/lib/web/components/advanced_search_component.ex`
  - Added `autocomplete="on"` to advanced search username field
- `apps/web/lib/web/components/advanced_search_input_component.ex`
  - Added optional `autocomplete` attribute support

## Current State ✅
The application now features:
- **BGG-Authentic Design**: Visual styling matches BoardGameGeek's interface
- **Smooth Toggle Functionality**: Advanced search shows/hides without page reloads
- **Enhanced Form UX**: Username fields remember previous inputs without password manager interference
- **Complete Functionality**: Client-side filtering, URL state preservation, responsive design
- **Production Ready**: All styling and UX improvements deployed and functional

## Testing
- Visit `/collection` and test advanced search toggle (should be smooth without page reload)
- Test username autocomplete in any search field (should remember "wumbabum" etc.)
- Verify BGG visual consistency across all components
