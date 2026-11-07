# Portrait camera capture — build 22

Front/back capture and retakes now use the same AVFoundation driver as the scanner. Photo, video detection, and preview connections explicitly use a 90-degree rotation for the portrait phone interface. Retakes are manual, show a portrait viewfinder, and let the collector review, accept, or retake a photo before replacing a saved side. Opening detailed capture pauses the underlying scanner so two sessions do not compete for the camera.

Camera output goes straight from `AVCapturePhoto.fileDataRepresentation()` to `CardPhotoEncoding.jpeg`. ImageIO applies EXIF orientation and mirroring to the pixels before the new JPEG is encoded with upright orientation and no inherited GPS metadata. The old retake path encoded a `UIImage` before normalization. Imports and scanner captures share the same tested encoder. Images are neither stretched nor cropped to force portrait dimensions; genuine landscape imports keep their content and orientation.

Existing saved photos are unchanged. This fix applies to new captures, retakes, and imports. Model routing, paid-search restrictions, and CardSight quotas are unchanged.

Validation: 104 core tests, 103 passed and one optional live-cache test skipped. New asymmetric image tests cover all eight EXIF rotation/mirroring settings, output dimensions, quadrant colors, upright metadata, GPS removal, repeat encoding, and invalid input. Physical capture and camera-preview behavior still require a human camera check; build/install success does not establish that check.
