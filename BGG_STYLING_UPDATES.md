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

## Files Modified
- `/Users/joseph.toney/Work/sandbox/bgg_sorter/apps/web/assets/css/app.css`
  - Updated advanced search CSS sections (lines ~874-1165)
  - Cleaned up duplicate/outdated styles
  - Added BGG-specific responsive breakpoints

## Result
The advanced search form now closely matches the authentic BoardGameGeek advanced search interface while maintaining all functional capabilities including:
- Client-side filtering
- URL parameter preservation  
- Form validation
- Responsive mobile design
- Phoenix LiveView integration

## Testing
Visit `http://localhost:7384/collection?advanced_search=true` to see the updated BGG-style advanced search form.
