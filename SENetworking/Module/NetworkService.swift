//
//  NetworkService.swift
//  App
//
//  Created by Oleh Kudinov on 01.10.18.
//

import Foundation

public enum NetworkError: Error {
    case error(statusCode: Int, data: Data?)
    case notConnected
    case cancelled
    case generic(Error)
    case urlGeneration
}

public protocol NetworkCancellable {
    func cancel()
}

extension URLSessionTask: NetworkCancellable { }

public protocol NetworkService {
    typealias CompletionHandler = (Result<Data?, NetworkError>) -> Void
    
    func request(endpoint: Requestable, completion: @escaping CompletionHandler) -> NetworkCancellable?
}

public protocol NetworkSessionManager {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    
    func request(_ request: URLRequest,
                 completion: @escaping CompletionHandler) -> NetworkCancellable
}

public protocol NetworkErrorLogger {
    func log(request: URLRequest)
    func log(responseData data: Data?, response: URLResponse?)
    func log(error: Error)
}

// MARK: - Implementation

public final class DefaultNetworkService {
    
    private let config: NetworkConfigurable
    private let sessionManager: NetworkSessionManager
    private let logger: NetworkErrorLogger
    
    public init(config: NetworkConfigurable,
                sessionManager: NetworkSessionManager = DefaultNetworkSessionManager(),
                logger: NetworkErrorLogger = DefaultNetworkErrorLogger()) {
        self.sessionManager = sessionManager
        self.config = config
        self.logger = logger
    }
    
    private func request(request: URLRequest, completion: @escaping CompletionHandler) -> NetworkCancellable {
        
        let sessionDataTask = sessionManager.request(request) { data, response, requestError in
            
            if let requestError = requestError {
                var error: NetworkError
                if let response = response as? HTTPURLResponse {
                    error = .error(statusCode: response.statusCode, data: data)
                } else {
                    error = self.resolve(error: requestError)
                }
                
                self.logger.log(error: error)
                completion(.failure(error))
            } else {
                self.logger.log(responseData: data, response: response)
                completion(.success(data))
            }
        }
    
        logger.log(request: request)

        return sessionDataTask
    }
    
    private func resolve(error: Error) -> NetworkError {
        let code = URLError.Code(rawValue: (error as NSError).code)
        switch code {
        case .notConnectedToInternet: return .notConnected
        case .cancelled: return .cancelled
        default: return .generic(error)
        }
    }
}

extension DefaultNetworkService: NetworkService {
    
    public func request(endpoint: Requestable, completion: @escaping CompletionHandler) -> NetworkCancellable? {
        do {
            let urlRequest = try endpoint.urlRequest(with: config)
            return request(request: urlRequest, completion: completion)
        } catch {
            completion(.failure(.urlGeneration))
            return nil
        }
    }
}

// MARK: - Default Network Session Manager
// Note: If authorization is needed NetworkSessionManager can be implemented by using,
// for example, Alamofire SessionManager with its RequestAdapter and RequestRetrier.
// And it can be incjected into NetworkService instead of default one.

public class DefaultNetworkSessionManager: NetworkSessionManager {
    public init() {}
    public func request(_ request: URLRequest,
                        completion: @escaping CompletionHandler) -> NetworkCancellable {
        let task = URLSession.shared.dataTask(with: request, completionHandler: completion)
        task.resume()
        return task
    }
}

// MARK: - Logger
extension String {
    func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
}

public final class DefaultNetworkErrorLogger: NetworkErrorLogger {
    public init() { }
    
    private func printJSONData(text: String, prefix: String) {
        guard let decodedString = text.removingPercentEncoding else {
            printIfDebug("☎️ body: \(String(describing: text))")
            return
        }
        let jsonString = decodedString.deletingPrefix(prefix)
        printIfDebug("☎️ body: \(String(describing: jsonString))")
    }

    public func log(request: URLRequest) {
        print("☎️ -------------")
        print("☎️ request: \(request.url!)")
        print("☎️ headers: \(request.allHTTPHeaderFields!)")
        print("☎️ method: \(request.httpMethod!)")
        if let httpBody = request.httpBody {
            let jsonPrefix = "jsonComponent="
            let dataPrefix = "data="
            if let text: String = String(data: httpBody, encoding: .utf8), text.starts(with: jsonPrefix) {
//                printJSONData(text: text, prefix: jsonPrefix)
            } else if let text: String = String(data: httpBody, encoding: .utf8), text.starts(with: dataPrefix) {
//                printJSONData(text: text, prefix: dataPrefix)
            } else {
                do {
                    let newResult = try JSONSerialization.jsonObject(with: httpBody, options: []) as? [String: AnyObject]
                    let result = newResult as [String: AnyObject]??
                    printIfDebug("☎️ body: \(String(describing: result))")
                } catch {
                    dump("error: \(String(describing: error))")
                }
            }
        } else {
            if
                let httpBody = request.httpBody,
                let resultString = String(data: httpBody, encoding: .utf8) {
                printIfDebug("☎️ body: \(String(describing: resultString))")
            }
        }
    }

    public func log(responseData data: Data?, response: URLResponse?) {
        guard let data = data else { return }
        printIfDebug("☎️ responseData: \(String(data: data, encoding: .utf8) ?? "")")
    }

    public func log(error: Error) {
        printIfDebug("☎️ \(error)")
    }
}

// MARK: - NetworkError extension

extension NetworkError {
    public var isNotFoundError: Bool { return hasStatusCode(404) }
    
    public func hasStatusCode(_ codeError: Int) -> Bool {
        switch self {
        case let .error(code, _):
            return code == codeError
        default: return false
        }
    }
}

func printIfDebug(_ string: String) {
    #if DEBUG
    print(string)
    #endif
}
