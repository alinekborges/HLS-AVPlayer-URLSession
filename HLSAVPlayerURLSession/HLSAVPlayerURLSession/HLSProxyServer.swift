//
//  HLSProxyServer.swift
//  HLSAVPlayerURLSession
//
//  Created by Aline Borges on 08/08/24.
//  Based on https://github.com/garynewby/HLS-video-offline-caching
//
//

import Foundation
import GCDWebServer
import Combine

struct HLSResponseItem: Codable {
  let data: Data
  let url: URL
  let mimeType: String
}

enum VideoProxyFormats: String, CaseIterable {
  case m3u8
  case ts
  case mp4
  case m4s
  case m4a
  case m4v
}

final class HLSVideoProxy {

  private let service: HLSService
  private let webServer: GCDWebServer
  private let originURLKey = "__hls_origin_url"
  private let port: UInt = 1234
  private var cancellables = Set<AnyCancellable>()

  init(server: GCDWebServer = GCDWebServer(),
       service: HLSService = CustomHSLService()) {
    self.webServer = GCDWebServer()
    self.service = service

    addPlaylistHandler()
  }

  deinit {
    stop()
  }

  func start() {
    guard !webServer.isRunning else { return }
    webServer.start(withPort: port, bonjourName: nil)
  }

  func stop() {
    guard webServer.isRunning else { return }
    webServer.stop()
  }

  private func originURL(from request: GCDWebServerRequest) -> URL? {
    guard let encodedURLString = request.query?[originURLKey],
          let urlString = encodedURLString.removingPercentEncoding,
          let url = URL(string: urlString) else {
      return nil
    }

    // Check for valid path extension
    guard VideoProxyFormats.init(rawValue: url.pathExtension) != nil else {
      return nil
    }

    return url
  }

  // MARK: - Public functions

  func reverseProxyURL(from originURL: URL) -> URL? {
    guard var components = URLComponents(url: originURL, resolvingAgainstBaseURL: false) else {
      return nil
    }

    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)

    let originURLQueryItem = URLQueryItem(name: originURLKey, value: originURL.absoluteString)
    components.queryItems = (components.queryItems ?? []) + [originURLQueryItem]

    return components.url
  }

  // MARK: - Request Handler

  private func addPlaylistHandler() {
    webServer.addHandler(forMethod: "GET",
                         pathRegex: "^/.*\\.*$",
                         request: GCDWebServerRequest.self) { [weak self] (request: GCDWebServerRequest, completion) in
      guard let self else {
        return completion(GCDWebServerErrorResponse(statusCode: 400))
      }

      guard let originURL = self.originURL(from: request) else {
        return completion(GCDWebServerErrorResponse(statusCode: 400))
      }

      if originURL.pathExtension == VideoProxyFormats.m3u8.rawValue {
        playlistResponse(for: originURL)
          .sink { serverResponse in
            completion(serverResponse)
          }.store(in: &self.cancellables)
      } else {
        self.serverResponse(for: originURL)
          .sink { serverResponse in
            completion(serverResponse)
          }.store(in: &self.cancellables)
      }
    }
  }

  // MARK: - Manipulating Playlist

  private func serverResponse(for url: URL) -> AnyPublisher<GCDWebServerDataResponse, Never> {
    service.dataTaskPublisher(url: url)
      .map { item in
        GCDWebServerDataResponse(data: item.data, contentType: item.mimeType)
      }
      .catch { _ in
        Just(GCDWebServerErrorResponse(statusCode: 500))
      }.eraseToAnyPublisher()
  }

  private func playlistResponse(for url: URL) -> AnyPublisher<GCDWebServerDataResponse, Never> {
    service.dataTaskPublisher(url: url)
      .tryMap { item in
        let playlistData = try self.reverseProxyPlaylist(with: item, forOriginURL: url)
        return GCDWebServerDataResponse(data: playlistData, contentType: item.mimeType)
      }
      .catch { _ in
        Just(GCDWebServerErrorResponse(statusCode: 500))
      }.eraseToAnyPublisher()
  }

  private func reverseProxyPlaylist(with item: HLSResponseItem, forOriginURL originURL: URL) throws -> Data {
    let original = String(data: item.data, encoding: .utf8)
    let parsed = original?
      .components(separatedBy: .newlines)
      .map { line in processPlaylistLine(line, forOriginURL: originURL) }
      .joined(separator: "\n")
    if let data = parsed?.data(using: .utf8) {
      return data
    } else {
      throw URLError(.badServerResponse)
    }
  }

  private func processPlaylistLine(_ line: String, forOriginURL originURL: URL) -> String {
    guard !line.isEmpty else { return line }

    if line.hasPrefix("#") {
      return lineByReplacingURI(line: line, forOriginURL: originURL)
    }

    if let originalSegmentURL = absoluteURL(from: line, forOriginURL: originURL),
       let reverseProxyURL = reverseProxyURL(from: originalSegmentURL) {
      return reverseProxyURL.absoluteString
    }
    return line
  }

  private func lineByReplacingURI(line: String, forOriginURL originURL: URL) -> String {
    guard let uriPattern = try? NSRegularExpression(pattern: "URI=\"([^\"]*)\"") else {
      return ""
    }

    let lineRange = NSRange(location: 0, length: line.count)
    guard let result = uriPattern.firstMatch(in: line, options: [], range: lineRange) else { return line }

    let uri = (line as NSString).substring(with: result.range(at: 1))
    guard let absoluteURL = absoluteURL(from: uri, forOriginURL: originURL) else { return line }
    guard let reverseProxyURL = reverseProxyURL(from: absoluteURL) else { return line }

    let newFile = uriPattern.stringByReplacingMatches(in: line, options: [], range: lineRange, withTemplate: "URI=\"\(reverseProxyURL.absoluteString)\"")
    return newFile
  }

  private func absoluteURL(from line: String, forOriginURL originURL: URL) -> URL? {
    if line.hasPrefix("http://") || line.hasPrefix("https://") {
      return URL(string: line)
    }

    guard let scheme = originURL.scheme,
          let host = originURL.host else {
      return nil
    }

    let path: String
    if line.hasPrefix("/") {
      path = line
    } else {
      path = originURL.deletingLastPathComponent().appendingPathComponent(line).path
    }

    return URL(string: scheme + "://" + host + path)?.standardized
  }
}
