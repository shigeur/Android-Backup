import os
import json
from PIL import Image, ImageDraw, ImageFilter, ImageOps

source_path = '/Users/ekopr/.gemini/antigravity/brain/85fcc6dc-5b6f-4689-8103-5fcbeec639ea/.user_uploaded/media__1784283865096.jpg'
output_dir = 'Assets.xcassets/AppIcon.appiconset'

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

# Load the source image
img = Image.open(source_path).convert("RGBA")
# Make sure it's square
size = min(img.size)
img = img.crop((0, 0, size, size))
img = img.resize((1024, 1024), Image.Resampling.LANCZOS)

# macOS icons are squircles. 
# A rough approximation for a 1024x1024 macOS icon squircle has a corner radius of about 22.5% of the size (230px).
# We also want to leave a little padding for a drop shadow if we were to add one, but let's just make the squircle.
mask = Image.new('L', (1024, 1024), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle((0, 0, 1024, 1024), radius=230, fill=255)

# Apply mask
squircle_img = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
squircle_img.paste(img, (0, 0), mask)

def generate_variant(base_img, variant_name=""):
    sizes = [
        ("16x16", 1, 16),
        ("16x16", 2, 32),
        ("32x32", 1, 32),
        ("32x32", 2, 64),
        ("64x64", 1, 64),
        ("64x64", 2, 128),
        ("128x128", 1, 128),
        ("128x128", 2, 256),
        ("256x256", 1, 256),
        ("256x256", 2, 512),
        ("512x512", 1, 512),
        ("512x512", 2, 1024),
    ]
    
    images_json = []
    
    for size_name, scale, px_size in sizes:
        resized = base_img.resize((px_size, px_size), Image.Resampling.LANCZOS)
        filename = f"icon_{size_name}@{scale}x{variant_name}.png"
        resized.save(os.path.join(output_dir, filename))
        
        img_entry = {
            "idiom": "mac",
            "size": size_name,
            "scale": f"{scale}x",
            "filename": filename
        }
        
        if variant_name == "_dark":
            img_entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        elif variant_name == "_tinted":
            # For tinted, we often provide a template or specific rendering, but let's just use dark for now.
            pass
            
        images_json.append(img_entry)
        
    return images_json

# Standard
contents = generate_variant(squircle_img)

# Dark Mode (slightly darker)
dark_img = ImageOps.coloroplot(squircle_img.convert('RGB'), ImageOps.autocontrast(squircle_img.convert('RGB'))) # just dim it
dark_enhancer = ImageEnhance.Brightness(squircle_img)
dark_img = dark_enhancer.enhance(0.8)
# Add dark appearances manually later if we want, but standard macOS usually just uses one app icon.
# We'll just generate the standard ones and add them to Contents.json.

contents_json = {
    "images": contents,
    "info": {
        "version": 1,
        "author": "xcode"
    }
}

with open(os.path.join(output_dir, 'Contents.json'), 'w') as f:
    json.dump(contents_json, f, indent=2)

print("Icons generated.")
