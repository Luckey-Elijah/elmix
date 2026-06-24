import 'dart:convert';

import 'package:elmix_admin/src/generated/admin_assets.g.dart';

/// Version-matched browser assets for the Admin Control Plane.
class AdminControlPlaneAssets {
  /// Returns the asset served for an Admin Control Plane [path].
  ///
  /// Application routes use the app shell so a browser can restore a deep link.
  static AdminControlPlaneAsset? forPath(String path) {
    if (path == '/_/admin') {
      return _asset('index.html');
    }
    const prefix = '/_/admin/';
    if (!path.startsWith(prefix)) {
      return null;
    }

    final assetPath = path.substring(prefix.length);
    if (adminControlPlaneEncodedAssets.containsKey(assetPath)) {
      return _asset(assetPath);
    }
    return assetPath.contains('.') ? null : _asset('index.html');
  }

  static AdminControlPlaneAsset _asset(String path) {
    return AdminControlPlaneAsset(
      utf8.decode(base64Decode(adminControlPlaneEncodedAssets[path]!)),
      adminControlPlaneAssetContentTypes[path]!,
    );
  }
}

/// One browser asset served by the Admin Control Plane.
class AdminControlPlaneAsset {
  /// Creates an asset with [contents] and [contentType].
  const AdminControlPlaneAsset(this.contents, this.contentType);

  /// Asset contents.
  final String contents;

  /// MIME type sent to browsers.
  final String contentType;
}
