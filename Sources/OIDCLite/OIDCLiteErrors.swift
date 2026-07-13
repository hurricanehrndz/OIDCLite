//
//  OIDCLiteErrors.swift
//
//
//  Created by Joel Rennich on 1/23/22.
//

import Foundation

public enum OIDCLiteError: Error, Equatable, Sendable, LocalizedError {
    case unableToFindCode
    case stateMismatch
    case unableToLoadEndpoint
    case unableToParseEndpoint
    case missingEndpoint(String)
    case authFailure(String)
    case oauthError(code: String, description: String?, httpStatus: Int)

    public var errorDescription: String? {
        switch self {
        case .unableToFindCode:
            return "Unable to parse code from URL"
        case .stateMismatch:
            return "Authorization response state does not match the login request"
        case .unableToLoadEndpoint:
            return "Unable to load OIDC discovery endpoint"
        case .unableToParseEndpoint:
            return "Unable to parse OIDC discovery endpoint"
        case let .missingEndpoint(endpoint):
            return "Missing OIDC endpoint: \(endpoint)"
        case let .authFailure(message):
            return "Authentication failure: \(message)"
        case let .oauthError(code, description, httpStatus):
            let detail = description.map { ": \($0)" } ?? ""
            return "OAuth error \(code) (HTTP \(httpStatus))\(detail)"
        }
    }
}
