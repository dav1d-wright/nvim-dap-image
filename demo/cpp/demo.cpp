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

int main() {
    // Create a BGR image with colored rectangles
    cv::Mat img = cv::Mat::zeros(480, 640, CV_8UC3);
    cv::rectangle(img, cv::Point(50, 50), cv::Point(200, 200), cv::Scalar(255, 0, 0), -1);
    cv::rectangle(img, cv::Point(220, 50), cv::Point(370, 200), cv::Scalar(0, 255, 0), -1);
    cv::rectangle(img, cv::Point(390, 50), cv::Point(540, 200), cv::Scalar(0, 0, 255), -1);
    cv::putText(img, "nvim-dap-image", cv::Point(150, 350),
                cv::FONT_HERSHEY_SIMPLEX, 1.5, cv::Scalar(255, 255, 255), 3);

    // Create a grayscale gradient
    cv::Mat gray(480, 640, CV_8UC1);
    for (int i = 0; i < 480; ++i) {
        gray.row(i).setTo(static_cast<uchar>(255 * i / 480));
    }

    // Large image (1920x1080 BGR, ~6MB)
    cv::Mat large = cv::Mat::zeros(1080, 1920, CV_8UC3);
    cv::circle(large, cv::Point(960, 540), 400, cv::Scalar(0, 165, 255), -1);
    cv::putText(large, "1920x1080", cv::Point(700, 560),
                cv::FONT_HERSHEY_SIMPLEX, 3.0, cv::Scalar(255, 255, 255), 5);

    // 4K image (3840x2160 BGR, ~24MB)
    cv::Mat img_4k = cv::Mat::zeros(2160, 3840, CV_8UC3);
    cv::rectangle(img_4k, cv::Point(100, 100), cv::Point(3740, 2060), cv::Scalar(80, 40, 20), -1);
    cv::circle(img_4k, cv::Point(1920, 1080), 800, cv::Scalar(0, 120, 255), -1);
    cv::putText(img_4k, "3840x2160", cv::Point(1400, 1120),
                cv::FONT_HERSHEY_SIMPLEX, 5.0, cv::Scalar(255, 255, 255), 8);

    // BGRA image (4-channel)
    cv::Mat bgra;
    cv::cvtColor(img, bgra, cv::COLOR_BGR2BGRA);

    int not_an_image = 42;

    // BREAKPOINT: Set breakpoint here and try <leader>di on img, gray, large, img_4k, bgra, not_an_image
    std::cout << "img: " << img.rows << "x" << img.cols << " channels=" << img.channels() << std::endl;
    std::cout << "gray: " << gray.rows << "x" << gray.cols << " channels=" << gray.channels() << std::endl;

    // Write images to disk for manual verification
    cv::imwrite("/tmp/nvim_dap_image_demo_img.png", img);
    cv::imwrite("/tmp/nvim_dap_image_demo_gray.png", gray);

    return 0;
}
