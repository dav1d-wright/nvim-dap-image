"""Demo script for testing nvim-dap-image with Python debug adapters.

Usage:
  1. Set a breakpoint on the line marked BREAKPOINT below
  2. Start a debug session with <leader>dl
  3. When stopped, place cursor on a variable name and press <leader>di
"""

import cv2
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt


def create_opencv_image():
    """Create a simple OpenCV BGR image with colored rectangles."""
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.rectangle(img, (50, 50), (200, 200), (255, 0, 0), -1)  # Blue
    cv2.rectangle(img, (220, 50), (370, 200), (0, 255, 0), -1)  # Green
    cv2.rectangle(img, (390, 50), (540, 200), (0, 0, 255), -1)  # Red
    cv2.putText(img, "nvim-dap-image", (150, 350), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 255), 3)
    return img


def create_pil_image():
    """Create a PIL image with a gradient."""
    width, height = 640, 480
    pil_img = Image.new("RGB", (width, height))
    for x in range(width):
        for y in range(height):
            r = int(255 * x / width)
            g = int(255 * y / height)
            b = 128
            pil_img.putpixel((x, y), (r, g, b))
    return pil_img


def create_numpy_array():
    """Create a grayscale numpy array."""
    arr = np.zeros((480, 640), dtype=np.uint8)
    for i in range(480):
        arr[i, :] = int(255 * i / 480)
    return arr


def create_matplotlib_figure():
    """Create a matplotlib figure with a simple plot."""
    fig, ax = plt.subplots(figsize=(8, 6))
    x = np.linspace(0, 4 * np.pi, 200)
    ax.plot(x, np.sin(x), label="sin(x)")
    ax.plot(x, np.cos(x), label="cos(x)")
    ax.set_title("nvim-dap-image matplotlib demo")
    ax.legend()
    ax.grid(True)
    return fig


def create_large_image():
    """Create a 1920x1080 BGR image with noise and shapes (6.2MB raw)."""
    large_img = np.random.randint(0, 256, (1080, 1920, 3), dtype=np.uint8)
    cv2.circle(large_img, (960, 540), 300, (0, 255, 0), 5)
    cv2.putText(large_img, "1920x1080", (700, 540), cv2.FONT_HERSHEY_SIMPLEX, 3, (255, 255, 255), 5)
    return large_img


def create_4k_image():
    """Create a 3840x2160 BGR image (24.9MB raw)."""
    img_4k = np.zeros((2160, 3840, 3), dtype=np.uint8)
    for i in range(2160):
        img_4k[i, :, 0] = int(255 * i / 2160)
        img_4k[i, :, 2] = 255 - int(255 * i / 2160)
    cv2.putText(img_4k, "4K", (1700, 1100), cv2.FONT_HERSHEY_SIMPLEX, 5, (255, 255, 255), 10)
    return img_4k


def main():
    cv_img = create_opencv_image()
    pil_img = create_pil_image()
    np_arr = create_numpy_array()
    fig = create_matplotlib_figure()
    large_img = create_large_image()
    img_4k = create_4k_image()

    not_an_image = 42

    # BREAKPOINT: Set breakpoint here and try <leader>di on each variable
    print("All images created. Set breakpoint on this line.")  # noqa: T201
    print(f"cv_img: {cv_img.shape}, large_img: {large_img.shape}, img_4k: {img_4k.shape}")  # noqa: T201


if __name__ == "__main__":
    main()
