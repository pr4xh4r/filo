import os
from PIL import Image, ImageDraw, ImageFilter

def create_filo_icon(size):
    # Create RGBA canvas
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Scale factor
    s = size / 1024.0

    # Draw rounded squircle background with rich gradient
    # Deep midnight to cobalt blue
    bg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    
    # Rounded rectangle
    radius = int(224 * s)
    margin = int(24 * s)
    rect_box = [margin, margin, size - margin, size - margin]
    
    # Draw gradient inside rounded box
    corner_mask = Image.new('L', (size, size), 0)
    cm_draw = ImageDraw.Draw(corner_mask)
    cm_draw.rounded_rectangle(rect_box, radius=radius, fill=255)
    
    gradient = Image.new('RGBA', (size, size))
    g_draw = ImageDraw.Draw(gradient)
    for y in range(size):
        ratio = y / float(size)
        # Deep sapphire (#0F172A) to Cobalt (#1D4ED8 to #2563EB)
        r = int(15 * (1 - ratio) + 37 * ratio)
        g = int(23 * (1 - ratio) + 99 * ratio)
        b = int(42 * (1 - ratio) + 235 * ratio)
        g_draw.line([(0, y), (size, y)], fill=(r, g, b, 255))
        
    img.paste(gradient, (0, 0), corner_mask)

    # Vault Shield / Cloud Geometry
    fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    fg_draw = ImageDraw.Draw(fg)

    # Outer shield polygon
    cx, cy = size / 2, size / 2
    shield_w = int(400 * s)
    shield_h = int(460 * s)
    
    shield_points = [
        (cx - shield_w/2, cy - shield_h/2.2),
        (cx + shield_w/2, cy - shield_h/2.2),
        (cx + shield_w/2, cy + shield_h/6),
        (cx, cy + shield_h/2),
        (cx - shield_w/2, cy + shield_h/6),
    ]
    
    fg_draw.polygon(shield_points, fill=(255, 255, 255, 235))

    # Inner cutout (Keyhole / Safe core)
    core_r = int(64 * s)
    core_cy = cy - int(20 * s)
    fg_draw.ellipse(
        [cx - core_r, core_cy - core_r, cx + core_r, core_cy + core_r],
        fill=(15, 23, 42, 255)
    )
    
    # Keyhole slot
    slot_w = int(44 * s)
    slot_h = int(90 * s)
    slot_points = [
        (cx - slot_w/2, core_cy),
        (cx + slot_w/2, core_cy),
        (cx + slot_w * 0.7, core_cy + slot_h),
        (cx - slot_w * 0.7, core_cy + slot_h),
    ]
    fg_draw.polygon(slot_points, fill=(15, 23, 42, 255))

    img = Image.alpha_composite(img, fg)
    return img

def main():
    os.makedirs('assets/icon', exist_ok=True)
    
    # Master 1024x1024 icon
    master = create_filo_icon(1024)
    master.save('assets/icon/app_icon.png')
    print("Generated master assets/icon/app_icon.png")

    # Android mipmaps
    android_sizes = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    }

    for path, sz in android_sizes.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        icon = master.resize((sz, sz), Image.Resampling.LANCZOS)
        icon.save(path)
        print(f"Generated Android icon: {path} ({sz}x{sz})")

    # iOS AppIcon assets
    ios_base = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    os.makedirs(ios_base, exist_ok=True)

    ios_sizes = {
        'Icon-App-1024x1024@1x.png': 1024,
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
    }

    for filename, sz in ios_sizes.items():
        filepath = os.path.join(ios_base, filename)
        icon = master.resize((sz, sz), Image.Resampling.LANCZOS)
        icon.save(filepath)
        print(f"Generated iOS icon: {filepath} ({sz}x{sz})")

    # SVG Asset
    svg_content = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="filoGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#0F172A"/>
      <stop offset="100%" stop-color="#2563EB"/>
    </linearGradient>
  </defs>
  <rect x="24" y="24" width="976" height="976" rx="224" fill="url(#filoGrad)"/>
  <path d="M312 300 H712 V580 L512 730 L312 580 Z" fill="#F8FAFC"/>
  <circle cx="512" cy="490" r="64" fill="#0F172A"/>
  <polygon points="490,490 534,490 542,580 482,580" fill="#0F172A"/>
</svg>'''
    with open('assets/icon/app_icon.svg', 'w') as f:
        f.write(svg_content)
    print("Generated vector assets/icon/app_icon.svg")

if __name__ == '__main__':
    main()
