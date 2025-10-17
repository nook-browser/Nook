#!/bin/bash
# Create simple SVG icons and convert to PNG

# Create 16x16 icon
cat > icon16.svg << 'SVGEOF'
<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg">
  <rect width="16" height="16" rx="3" fill="#667eea"/>
  <text x="8" y="12" font-family="Arial" font-size="12" font-weight="bold" fill="white" text-anchor="middle">P1</text>
</svg>
SVGEOF

# Create 48x48 icon
cat > icon48.svg << 'SVGEOF'
<svg width="48" height="48" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="48" height="48" rx="8" fill="url(#grad)"/>
  <text x="24" y="32" font-family="Arial" font-size="24" font-weight="bold" fill="white" text-anchor="middle">P1</text>
</svg>
SVGEOF

# Create 128x128 icon
cat > icon128.svg << 'SVGEOF'
<svg width="128" height="128" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="128" height="128" rx="20" fill="url(#grad)"/>
  <text x="64" y="85" font-family="Arial" font-size="48" font-weight="bold" fill="white" text-anchor="middle">P1</text>
  <text x="64" y="108" font-family="Arial" font-size="16" fill="white" text-anchor="middle" opacity="0.8">TEST</text>
</svg>
SVGEOF

echo "SVG icons created"
