import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

// Windows API bindings
final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');

// GetSystemMetrics
typedef _GetSystemMetricsC = Int32 Function(Int32 nIndex);
typedef _GetSystemMetricsDart = int Function(int nIndex);
final _getSystemMetrics = _user32.lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>('GetSystemMetrics');

// GetDC / ReleaseDC
typedef _GetDCC = IntPtr Function(IntPtr hWnd);
typedef _GetDCDart = int Function(int hWnd);
final _getDC = _user32.lookupFunction<_GetDCC, _GetDCDart>('GetDC');

typedef _ReleaseDCC = Int32 Function(IntPtr hWnd, IntPtr hDC);
typedef _ReleaseDCDart = int Function(int hWnd, int hDC);
final _releaseDC = _user32.lookupFunction<_ReleaseDCC, _ReleaseDCDart>('ReleaseDC');

// CreateCompatibleDC / DeleteDC
typedef _CreateCompatibleDCC = IntPtr Function(IntPtr hdc);
typedef _CreateCompatibleDCDart = int Function(int hdc);
final _createCompatibleDC = _gdi32.lookupFunction<_CreateCompatibleDCC, _CreateCompatibleDCDart>('CreateCompatibleDC');

typedef _DeleteDCC = Int32 Function(IntPtr hdc);
typedef _DeleteDCDart = int Function(int hdc);
final _deleteDC = _gdi32.lookupFunction<_DeleteDCC, _DeleteDCDart>('DeleteDC');

// CreateCompatibleBitmap
typedef _CreateCompatibleBitmapC = IntPtr Function(IntPtr hdc, Int32 cx, Int32 cy);
typedef _CreateCompatibleBitmapDart = int Function(int hdc, int cx, int cy);
final _createCompatibleBitmap = _gdi32.lookupFunction<_CreateCompatibleBitmapC, _CreateCompatibleBitmapDart>('CreateCompatibleBitmap');

// SelectObject / DeleteObject
typedef _SelectObjectC = IntPtr Function(IntPtr hdc, IntPtr h);
typedef _SelectObjectDart = int Function(int hdc, int h);
final _selectObject = _gdi32.lookupFunction<_SelectObjectC, _SelectObjectDart>('SelectObject');

typedef _DeleteObjectC = Int32 Function(IntPtr ho);
typedef _DeleteObjectDart = int Function(int ho);
final _deleteObject = _gdi32.lookupFunction<_DeleteObjectC, _DeleteObjectDart>('DeleteObject');

// BitBlt
typedef _BitBltC = Int32 Function(IntPtr hdc, Int32 x, Int32 y, Int32 cx, Int32 cy, IntPtr hdcSrc, Int32 x1, Int32 y1, Uint32 rop);
typedef _BitBltDart = int Function(int hdc, int x, int y, int cx, int cy, int hdcSrc, int x1, int y1, int rop);
final _bitBlt = _gdi32.lookupFunction<_BitBltC, _BitBltDart>('BitBlt');

// GetDIBits
typedef _GetDIBitsC = Int32 Function(IntPtr hdc, IntPtr hbm, Uint32 start, Uint32 cLines, Pointer<Void> lpvBits, Pointer<_BITMAPINFO> lpbmi, Uint32 usage);
typedef _GetDIBitsDart = int Function(int hdc, int hbm, int start, int cLines, Pointer<Void> lpvBits, Pointer<_BITMAPINFO> lpbmi, int usage);
final _getDIBits = _gdi32.lookupFunction<_GetDIBitsC, _GetDIBitsDart>('GetDIBits');

// GetCursorPos
typedef _GetCursorPosC = Int32 Function(Pointer<_POINT> lpPoint);
typedef _GetCursorPosDart = int Function(Pointer<_POINT> lpPoint);
final _getCursorPos = _user32.lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');

// GetCursorInfo
typedef _GetCursorInfoC = Int32 Function(Pointer<_CURSORINFO> pci);
typedef _GetCursorInfoDart = int Function(Pointer<_CURSORINFO> pci);
final _getCursorInfo = _user32.lookupFunction<_GetCursorInfoC, _GetCursorInfoDart>('GetCursorInfo');

// DrawIconEx
typedef _DrawIconExC = Int32 Function(IntPtr hdc, Int32 xLeft, Int32 yTop, IntPtr hIcon, Int32 cxWidth, Int32 cyWidth, Uint32 istepIfAniCur, IntPtr hbrFlickerFreeDraw, Uint32 diFlags);
typedef _DrawIconExDart = int Function(int hdc, int xLeft, int yTop, int hIcon, int cxWidth, int cyWidth, int istepIfAniCur, int hbrFlickerFreeDraw, int diFlags);
final _drawIconEx = _user32.lookupFunction<_DrawIconExC, _DrawIconExDart>('DrawIconEx');

// Structs
final class _POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _CURSORINFO extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int flags;
  @IntPtr()
  external int hCursor;
  external _POINT ptScreenPos;
}

final class _BITMAPINFOHEADER extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

final class _BITMAPINFO extends Struct {
  external _BITMAPINFOHEADER bmiHeader;
  // bmiColors follows but we don't need it for 32-bit
}

// Constants
const int _SM_CXSCREEN = 0;
const int _SM_CYSCREEN = 1;
const int _SRCCOPY = 0x00CC0020;
const int _BI_RGB = 0;
const int _DIB_RGB_COLORS = 0;
const int _DI_NORMAL = 0x0003;
const int _CURSOR_SHOWING = 0x00000001;

/// 截屏结果
class ScreenCaptureResult {
  final Uint8List imageData;
  final int cursorX;
  final int cursorY;
  final int screenWidth;
  final int screenHeight;

  ScreenCaptureResult({
    required this.imageData,
    required this.cursorX,
    required this.cursorY,
    required this.screenWidth,
    required this.screenHeight,
  });
}

/// PC端截屏服务
class ScreenCaptureService {
  static bool get isSupported => Platform.isWindows;

  /// 截取屏幕（包含鼠标光标）
  /// [quality] JPEG压缩质量 1-100，默认50
  /// [scale] 缩放比例 0.1-1.0，默认0.5
  static Future<ScreenCaptureResult?> capture({
    int quality = 50,
    double scale = 0.5,
  }) async {
    if (!isSupported) return null;

    try {
      // 获取屏幕尺寸
      final screenWidth = _getSystemMetrics(_SM_CXSCREEN);
      final screenHeight = _getSystemMetrics(_SM_CYSCREEN);

      // 获取屏幕DC
      final hdcScreen = _getDC(0);
      if (hdcScreen == 0) return null;

      // 创建兼容DC和位图
      final hdcMem = _createCompatibleDC(hdcScreen);
      final hBitmap = _createCompatibleBitmap(hdcScreen, screenWidth, screenHeight);
      final hOldBitmap = _selectObject(hdcMem, hBitmap);

      // 复制屏幕内容
      _bitBlt(hdcMem, 0, 0, screenWidth, screenHeight, hdcScreen, 0, 0, _SRCCOPY);

      // 获取鼠标位置和绘制光标
      final cursorInfo = calloc<_CURSORINFO>();
      cursorInfo.ref.cbSize = sizeOf<_CURSORINFO>();
      int cursorX = 0, cursorY = 0;
      
      if (_getCursorInfo(cursorInfo) != 0) {
        cursorX = cursorInfo.ref.ptScreenPos.x;
        cursorY = cursorInfo.ref.ptScreenPos.y;
        
        // 如果光标可见，绘制到位图上
        if ((cursorInfo.ref.flags & _CURSOR_SHOWING) != 0 && cursorInfo.ref.hCursor != 0) {
          _drawIconEx(hdcMem, cursorX, cursorY, cursorInfo.ref.hCursor, 0, 0, 0, 0, _DI_NORMAL);
        }
      }
      calloc.free(cursorInfo);

      // 获取位图数据
      final bmi = calloc<_BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<_BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = screenWidth;
      bmi.ref.bmiHeader.biHeight = -screenHeight; // 负值表示从上到下
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = _BI_RGB;

      final pixelDataSize = screenWidth * screenHeight * 4;
      final pixelData = calloc<Uint8>(pixelDataSize);

      _getDIBits(hdcMem, hBitmap, 0, screenHeight, pixelData.cast(), bmi, _DIB_RGB_COLORS);

      // 转换为Dart Uint8List (BGRA -> RGBA)
      final pixels = pixelData.asTypedList(pixelDataSize);
      final rgbaPixels = Uint8List(pixelDataSize);
      for (var i = 0; i < pixelDataSize; i += 4) {
        rgbaPixels[i] = pixels[i + 2];     // R
        rgbaPixels[i + 1] = pixels[i + 1]; // G
        rgbaPixels[i + 2] = pixels[i];     // B
        rgbaPixels[i + 3] = 255;           // A
      }

      // 清理资源
      calloc.free(pixelData);
      calloc.free(bmi);
      _selectObject(hdcMem, hOldBitmap);
      _deleteObject(hBitmap);
      _deleteDC(hdcMem);
      _releaseDC(0, hdcScreen);

      // 使用image包处理图像
      final image = img.Image.fromBytes(
        width: screenWidth,
        height: screenHeight,
        bytes: rgbaPixels.buffer,
        numChannels: 4,
      );

      // 缩放
      final scaledWidth = (screenWidth * scale).round();
      final scaledHeight = (screenHeight * scale).round();
      final scaledImage = img.copyResize(image, width: scaledWidth, height: scaledHeight);

      // 编码为JPEG
      final jpegData = img.encodeJpg(scaledImage, quality: quality);

      return ScreenCaptureResult(
        imageData: Uint8List.fromList(jpegData),
        cursorX: (cursorX * scale).round(),
        cursorY: (cursorY * scale).round(),
        screenWidth: scaledWidth,
        screenHeight: scaledHeight,
      );
    } catch (e) {
      return null;
    }
  }
}
