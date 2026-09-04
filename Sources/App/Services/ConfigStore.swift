import HuggingFaceDownloader

// The implementation lives in the small shared library so ConfigTokenStore
// and the app use exactly the same serialized writer. Keep the app-facing name
// here with the rest of the service layer.
typealias ConfigStore = HuggingFaceDownloader.ConfigStore
