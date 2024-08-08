//
//  HLSVideoView.swift
//
//  Created by Aline Borges on 31/07/24.
//  Copyright © 2024 Harbor.co. All rights reserved.
//

import Foundation
import SwiftUI
import AVKit
import GCDWebServer

struct HLSVideoPlayer: View {
  @StateObject var viewModel = HLSPlayerViewModel()

  var body: some View {
    VideoPlayer(player: viewModel.player)
      .onAppear {
        viewModel.start()
      }.onDisappear {
        viewModel.stop()
      }
  }

}

class HLSPlayerViewModel: ObservableObject {

  @Published var player = AVPlayer()

  private let proxy: HLSVideoProxy
  private let webServer = GCDWebServer()
  private let testVideoURL = "https://mtoczko.github.io/hls-test-streams/test-vtt-fmp4-segments/playlist.m3u8"

  init() {
    // Replace with your custom URLSession
    let service = CustomHSLService(urlSession: URLSession.shared)
    self.proxy = HLSVideoProxy(server: webServer, service: service)
    setup()
  }

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

  func start() {
    proxy.start()
  }

  func stop() {
    proxy.stop()
  }

}


#Preview {
  HLSVideoPlayer()
}
