# Camera Permissions Setup

To use the camera feature in the demo app, you need to add the camera usage description to your app's Info.plist:

## For Xcode Projects

Add the following key to your Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera to capture images for real-time U-Net visualization.</string>
```

## For Swift Packages

If running the demo from a Swift Package, you may need to:

1. Create a wrapper Xcode project that imports the package
2. Add the camera permission to that project's Info.plist
3. Or run the app on a physical device where permissions can be requested dynamically

## Testing

The camera feature requires:
- iOS device or simulator with camera support
- Camera permissions granted when prompted
- Sufficient processing power for real-time inference (physical devices recommended)