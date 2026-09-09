import 'dart:math';

/// WGS84(GPS原始坐标) → GCJ02(火星坐标/高德坐标) 转换。
/// 高德地图、腾讯地图使用 GCJ02，手机 GPS 返回 WGS84，
/// 直接混用会偏移 300~600 米。水印坐标、地址反查、点位导航统一用 GCJ02。
(double lat, double lng) wgs84ToGcj02(double lat, double lng) {
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  bool outOfChina(double la, double lo) =>
      lo < 72.004 || lo > 137.8347 || la < 0.8293 || la > 55.8271;

  if (outOfChina(lat, lng)) return (lat, lng);

  double transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
        0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }

  final dLat = transformLat(lng - 105.0, lat - 35.0);
  final dLon = transformLon(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * pi;
  var magic = sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = sqrt(magic);
  final mgLat = lat + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
  final mgLon = lng + (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * pi);
  return (mgLat, mgLon);
}
