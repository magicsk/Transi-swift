//
//  Fetch.swift
//  Transi
//
//  Created by magic_sk on 18/02/2024.
//

import Foundation

let USER_AGENT = "ProdProd/204 CFNetwork/3826.600.41 Darwin/24.6.0"

func fetchData<T: Decodable>(request: URLRequest, type: T.Type, completion: @escaping (Result<T, Error>) -> ()) {
    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error {
            completion(.failure(error))
            return
        }

        guard let data = data else {
            completion(.failure(NSError(domain: "fetchData", code: -3, userInfo: ["message": "No data received!"])))
            return
        }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let stops = try jsonDecoder.decode(type, from: data)
            DispatchQueue.main.async {
                completion(.success(stops))
            }
        } catch {
            completion(.failure(error))
        }
    }
    .resume()
}

func fetchMagicApi<T: Decodable>(endpoint: String, type: T.Type, completion: @escaping (Result<T, Error>) -> ()) {
    let request = URLRequest(url: URL(string: "\(GlobalController.magicApiBaseUrl)\(endpoint)")!)
    fetchData(request: request, type: type, completion: completion)
}

func fetchBApiPost<T: Decodable>(endpoint: String, jsonBody: Data, type: T.Type, completion: @escaping (Result<T, Error>) -> ()) {
    var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)\(endpoint)")!)
    request.httpMethod = "POST"
    request.setValue("\(String(describing: jsonBody.count))", forHTTPHeaderField: "Content-Length")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(USER_AGENT, forHTTPHeaderField: "User-Agent")
    request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
    request.httpBody = jsonBody
    
    fetchData(request: request, type: type, completion: completion)
}

func fetchBApi<T: Decodable>(endpoint: String, type: T.Type, completion: @escaping (Result<T, Error>) -> ()) {
    print(endpoint)
    var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)\(endpoint)")!)
    request.setValue(USER_AGENT, forHTTPHeaderField: "User-Agent")
    request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
    
    fetchData(request: request, type: type, completion: completion)
}

func fetchRApiPost<T: Decodable>(endpoint: String, jsonBody: Data, type: T.Type, completion: @escaping (Result<T, Error>) -> ()) {
    var request = URLRequest(url: URL(string: "\(GlobalController.rApiBaseUrl)\(endpoint)")!)
    request.httpMethod = "POST"
    request.setValue("\(String(describing: jsonBody.count))", forHTTPHeaderField: "Content-Length")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(USER_AGENT, forHTTPHeaderField: "User-Agent")
    request.setValue(GlobalController.rApiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
    request.httpBody = jsonBody
    
    fetchData(request: request, type: type, completion: completion)
}
