# HLS-AVPlayer-URLSession

Swift iOS example of changing the URLSession to play an m3u8 HLS video playlist and (ts or mp4) to respond to AuthChallenges using an embedded reverse proxy server.

Based on:
- https://github.com/StyleShare/HLSCachingReverseProxyServer
- https://github.com/garynewby/HLS-video-offline-caching

## Dependencies

* [GCDWebServer](https://github.com/swisspol/GCDWebServer)

## Usage

```swift
let service = CustomHSLService(urlSession: URLSession.shared)
self.proxy = HLSVideoProxy(server: webServer, service: service)

func setup() {
  guard let url = URL(string: testVideoURL) else {
    print("Invalid URL")
    return
  }

  guard let videoURL = proxy.reverseProxyURL(from: url) else {
    print("Invalid url format")
    return
  }

  let playerItem = AVPlayerItem(url: videoURL)
  self.player.replaceCurrentItem(with: playerItem)
  self.proxy.start()
}
```