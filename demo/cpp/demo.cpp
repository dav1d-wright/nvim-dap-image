/// Demo program for testing nvim-dap-image with C++ debug adapters.
///
/// Usage:
///   1. Build with: bazel build -c dbg //:demo
///   2. Set a breakpoint on the line marked BREAKPOINT below
///   3. Start a debug session with <leader>dl (or bazel-tools debug)
///   4. When stopped, place cursor on a variable name and press <leader>di

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <iostream>

/// Create a BGR image with colored rectangles.
cv::Mat create_opencv_image() {
    cv::Mat img = cv::Mat::zeros(480, 640, CV_8UC3);
    cv::rectangle(img, cv::Point(50, 50), cv::Point(200, 200), cv::Scalar(255, 0, 0), -1);   // Blue
    cv::rectangle(img, cv::Point(220, 50), cv::Point(370, 200), cv::Scalar(0, 255, 0), -1);  // Green
    cv::rectangle(img, cv::Point(390, 50), cv::Point(540, 200), cv::Scalar(0, 0, 255), -1);  // Red
    cv::putText(img, "nvim-dap-image", cv::Point(150, 350),
                cv::FONT_HERSHEY_SIMPLEX, 1.5, cv::Scalar(255, 255, 255), 3);
    return img;
}

/// Create a grayscale gradient image.
cv::Mat create_grayscale_image() {
    cv::Mat gray(480, 640, CV_8UC1);
    for (int i = 0; i < 480; ++i) {
        gray.row(i).setTo(static_cast<uchar>(255 * i / 480));
    }
    return gray;
}

/// Create a BGRA (4-channel) image from the base opencv image.
cv::Mat create_bgra_image() {
    cv::Mat bgra;
    cv::cvtColor(create_opencv_image(), bgra, cv::COLOR_BGR2BGRA);
    return bgra;
}

/// Create a 1920x1080 BGR image (~6MB raw).
cv::Mat create_large_image() {
    cv::Mat large = cv::Mat::zeros(1080, 1920, CV_8UC3);
    cv::circle(large, cv::Point(960, 540), 400, cv::Scalar(0, 165, 255), -1);
    cv::putText(large, "1920x1080", cv::Point(700, 560),
                cv::FONT_HERSHEY_SIMPLEX, 3.0, cv::Scalar(255, 255, 255), 5);
    return large;
}

/// Create an image with text then return a cropped submatrix that cuts through
/// the text mid-word. The submatrix has step[0] == parent's row stride (640*3),
/// while cols == 430, so step > cols * channels. Tests non-contiguous memory.
cv::Mat create_cropped_image() {
    cv::Mat base = cv::Mat::zeros(480, 640, CV_8UC3);
    cv::putText(base, "cropped image", cv::Point(50, 260),
                cv::FONT_HERSHEY_SIMPLEX, 2.0, cv::Scalar(100, 200, 255), 4);
    // Crop so "image" is cut off mid-word.
    // The returned submatrix has step[0] == 640*3 (parent stride) while cols == 430,
    // so step > cols * channels -- tests non-contiguous memory handling.
    cv::Mat cropped = base(cv::Rect(0, 190, 430, 120));
    return cropped;
}

/// Create a 3840x2160 BGR image (~24MB raw).
cv::Mat create_4k_image() {
    cv::Mat img_4k = cv::Mat::zeros(2160, 3840, CV_8UC3);
    cv::rectangle(img_4k, cv::Point(100, 100), cv::Point(3740, 2060), cv::Scalar(80, 40, 20), -1);
    cv::circle(img_4k, cv::Point(1920, 1080), 800, cv::Scalar(0, 120, 255), -1);
    cv::putText(img_4k, "3840x2160", cv::Point(1400, 1120),
                cv::FONT_HERSHEY_SIMPLEX, 5.0, cv::Scalar(255, 255, 255), 8);
    return img_4k;
}

int main() {
    cv::Mat cv_img = create_opencv_image();
    cv::Mat gray = create_grayscale_image();
    cv::Mat bgra = create_bgra_image();
    cv::Mat large_img = create_large_image();
    cv::Mat img_4k = create_4k_image();
    cv::Mat cropped = create_cropped_image();

    int not_an_image = 42;

    // BREAKPOINT: Set breakpoint here and try <leader>di on each variable
    std::cout << "All images created. Set breakpoint on this line." << std::endl;
    std::cout << "cv_img: " << cv_img.rows << "x" << cv_img.cols
              << ", large_img: " << large_img.rows << "x" << large_img.cols
              << ", img_4k: " << img_4k.rows << "x" << img_4k.cols << std::endl;

    return 0;
}
