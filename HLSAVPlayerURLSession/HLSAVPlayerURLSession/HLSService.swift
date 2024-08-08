//
//  HLSService.swift
//  HLSAVPlayerURLSession
//
//  Created by Aline Borges on 08/08/24.
//

import Foundation
import Combine

protocol HLSService {
  func dataTaskPublisher(url: URL) -> AnyPublisher<HLSResponseItem, Error>
}

class CustomHSLService: HLSService {

  let urlSession: URLSession

  init(urlSession: URLSession = URLSession.shared) {
    self.urlSession = urlSession
  }

  func dataTaskPublisher(url: URL) -> AnyPublisher<HLSResponseItem, Error> {
    urlSession.dataTaskPublisher(for: url)
      .tryMap(mapResponseCode)
      .tryMap(mapHLSResponseItem)
      .eraseToAnyPublisher()
  }

  private func mapResponseCode(data: Data, response: URLResponse) throws -> (Data, URLResponse) {
    guard let httpResponse = response as? HTTPURLResponse else {
      return (data, response)
    }

    if (200..<300) ~= httpResponse.statusCode {
      // Valid response, no error needed
      return (data, response)
    }

    throw URLError(.badServerResponse)
  }

  private func mapHLSResponseItem(data: Data, response: URLResponse) throws -> HLSResponseItem {
    guard let mimeType = response.mimeType else {
      throw URLError(.fileDoesNotExist)
    }

    guard let url = response.url else {
      throw URLError(.badURL)
    }

    return HLSResponseItem(data: data, url: url, mimeType: mimeType)
  }
}
