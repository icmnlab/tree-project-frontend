import os
from PIL import Image

def add_padding(input_path, output_path, padding_ratio=0.3):
    try:
        img = Image.open(input_path).convert("RGBA")
        width, height = img.size
        
        # Calculate new size for the logo (shrink it)
        # If we want more white space, we shrink the logo and place it on a white background of the original size.
        # padding_ratio of 0.3 means the logo will be 70% of the original size (1 - 0.3)
        
        new_logo_width = int(width * (1 - padding_ratio))
        new_logo_height = int(height * (1 - padding_ratio))
        
        resized_img = img.resize((new_logo_width, new_logo_height), Image.Resampling.LANCZOS)
        
        # Create a new white background image of the original size
        new_img = Image.new("RGBA", (width, height), (255, 255, 255, 255))
        
        # Calculate position to center the resized logo
        x_offset = (width - new_logo_width) // 2
        y_offset = (height - new_logo_height) // 2
        
        # Paste the resized logo onto the white background
        # Use the resized image itself as the mask if it has transparency
        new_img.paste(resized_img, (x_offset, y_offset), resized_img)
        
        new_img.save(output_path)
        print(f"Successfully created padded icon at {output_path}")
        
    except Exception as e:
        print(f"Error processing image: {e}")

if __name__ == "__main__":
    input_icon = "assets/icons/app_icon_2.png"
    output_icon = "assets/icons/android_adaptive_icon.png"
    
    # Check if input exists
    if os.path.exists(input_icon):
        add_padding(input_icon, output_icon, padding_ratio=0.35) # 35% padding to be safe for adaptive icons
    else:
        print(f"Input file not found: {input_icon}")
