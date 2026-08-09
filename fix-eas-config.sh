#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

MOBILE="$ROOT/coin-rice-mill-map/coin-rice-mill-map/apps/mobile"
if [ ! -d "$MOBILE" ]; then
  MOBILE="$ROOT/coin-rice-mill-map/apps/mobile"
fi

if [ ! -d "$MOBILE" ]; then
  echo "ERROR: apps/mobile was not found under the expected extracted project paths." >&2
  exit 1
fi

cd "$MOBILE"

echo "Using mobile app directory: $MOBILE"

if [ -f app.config.ts ]; then
  BACKUP="app.config.ts.before-eas-fix.$(date +%Y%m%d%H%M%S)"
  cp app.config.ts "$BACKUP"
  mv app.config.ts app.config.ts.disabled
  echo "Backed up original config to: $BACKUP"
  echo "Moved original config to: app.config.ts.disabled"
fi

cat > app.config.js <<'EOF'
const APP_IDENTIFIERS = {
  projectName: 'coin-rice-mill-map',
  displayName: 'コイン精米マップ',
  scheme: 'coinricemillmap',
  bundleId: process.env.EXPO_PUBLIC_IOS_BUNDLE_ID || 'jp.neumann.coinricemillmap',
  androidPackage:
    process.env.EXPO_PUBLIC_ANDROID_PACKAGE || 'jp.neumann.coinricemillmap',
};

const AD_CONFIG = {
  iosAppId: process.env.EXPO_PUBLIC_ADMOB_IOS_APP_ID || '',
  androidAppId: process.env.EXPO_PUBLIC_ADMOB_ANDROID_APP_ID || '',
};

module.exports = ({ config }) => ({
  ...config,
  owner: 'takzin1',
  name: APP_IDENTIFIERS.displayName,
  slug: APP_IDENTIFIERS.projectName,
  scheme: APP_IDENTIFIERS.scheme,
  version: '0.1.0',
  runtimeVersion: { policy: 'appVersion' },
  orientation: 'default',
  userInterfaceStyle: 'automatic',
  icon: './assets/icon.png',
  assetBundlePatterns: ['**/*'],

  ios: {
    bundleIdentifier: APP_IDENTIFIERS.bundleId,
    supportsTablet: true,
    config: { usesNonExemptEncryption: false },
    infoPlist: {
      NSLocationWhenInUseUsageDescription:
        '現在地の周辺にあるコイン精米機を表示するために使用します。バックグラウンドでは取得しません。',
      NSCameraUsageDescription:
        'コイン精米機の写真を撮影して投稿するために使用します。',
      NSPhotoLibraryUsageDescription:
        '保存済みの写真からコイン精米機の写真を選んで投稿するために使用します。',
      ...(AD_CONFIG.iosAppId
        ? { GADApplicationIdentifier: AD_CONFIG.iosAppId }
        : {}),
    },
    privacyManifests: {
      NSPrivacyTracking: false,
      NSPrivacyAccessedAPITypes: [
        {
          NSPrivacyAccessedAPIType:
            'NSPrivacyAccessedAPICategoryUserDefaults',
          NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
        },
        {
          NSPrivacyAccessedAPIType:
            'NSPrivacyAccessedAPICategoryFileTimestamp',
          NSPrivacyAccessedAPITypeReasons: ['C617.1', '0A2A.1', '3B52.1'],
        },
        {
          NSPrivacyAccessedAPIType:
            'NSPrivacyAccessedAPICategorySystemBootTime',
          NSPrivacyAccessedAPITypeReasons: ['35F9.1'],
        },
        {
          NSPrivacyAccessedAPIType:
            'NSPrivacyAccessedAPICategoryDiskSpace',
          NSPrivacyAccessedAPITypeReasons: ['E174.1', '85F4.1'],
        },
      ],
    },
  },

  android: {
    package: APP_IDENTIFIERS.androidPackage,
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#1C2B2D',
    },
    permissions: [
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.CAMERA',
      'com.android.vending.BILLING',
    ],
    blockedPermissions: [
      'android.permission.ACCESS_BACKGROUND_LOCATION',
      'android.permission.RECORD_AUDIO',
      'android.permission.SYSTEM_ALERT_WINDOW',
    ],
  },

  plugins: [
    'expo-router',
    ['expo-secure-store', { faceIDPermission: false }],
    [
      'expo-splash-screen',
      {
        image: './assets/splash.png',
        resizeMode: 'contain',
        backgroundColor: '#FBFAF6',
        dark: { backgroundColor: '#1C2B2D' },
      },
    ],
    [
      'expo-location',
      {
        locationWhenInUsePermission:
          '現在地の周辺にあるコイン精米機を表示するために使用します。バックグラウンドでは取得しません。',
        locationAlwaysPermission: false,
        locationAlwaysAndWhenInUsePermission: false,
        motionUsagePermission: false,
        isAndroidBackgroundLocationEnabled: false,
        isIosBackgroundLocationEnabled: false,
      },
    ],
    [
      'expo-image-picker',
      {
        photosPermission:
          '投稿する写真を選ぶために写真へのアクセスを許可してください。',
        cameraPermission:
          'コイン精米機の写真を撮影するためにカメラを使用します。',
        microphonePermission: false,
      },
    ],
    [
      'expo-build-properties',
      {
        android: {
          compileSdkVersion: 36,
          targetSdkVersion: 36,
          minSdkVersion: 24,
        },
        ios: { deploymentTarget: '16.4' },
      },
    ],
    ...(AD_CONFIG.iosAppId && AD_CONFIG.androidAppId
      ? [
          [
            'react-native-google-mobile-ads',
            {
              iosAppId: AD_CONFIG.iosAppId,
              androidAppId: AD_CONFIG.androidAppId,
              delayAppMeasurementInit: true,
            },
          ],
        ]
      : []),
  ],

  extra: {
    environment: process.env.EXPO_PUBLIC_ENVIRONMENT || 'development',
    eas: {
      projectId:
        process.env.EAS_PROJECT_ID ||
        '16e2a949-9e22-4710-81a4-03221638bc08',
    },
  },

  updates: {
    checkAutomatically: 'ON_LOAD',
    fallbackToCacheTimeout: 0,
  },

  experiments: { typedRoutes: true },
});
EOF

echo "Created: $MOBILE/app.config.js"
echo "Checking Expo config..."

npx expo config --type public >/tmp/crmm-expo-config.json

echo "Expo config OK. Key values:"
grep -E '"owner"|"slug"|"projectId"' /tmp/crmm-expo-config.json || true

echo
echo "Checking EAS project link..."
eas project:info
