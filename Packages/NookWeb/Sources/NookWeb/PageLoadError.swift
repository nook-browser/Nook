// Licensed under GPL-3.0. See LICENSE.
//
//  PageLoadError.swift
//  Nook
//
//  A main-frame load that failed before anything committed, sorted for Nook's error page.
//

import Foundation

public struct PageLoadError: Equatable {
    public enum Kind: Equatable {
        case offline, hostNotFound, noAnswer, certificate, other
    }

    public let url: URL
    public let kind: Kind
    public let message: String

    /// Nil for failures that get no error page: cancelled loads, downloads and ad-blocked pages.
    public init?(error: Error, attempted: URL) {
        let error = error as NSError
        if error.domain == "WebKitErrorDomain", error.code == 102 || error.code == 104 { return nil }
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return nil }

        url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? attempted
        message = error.localizedDescription
        guard error.domain == NSURLErrorDomain else { kind = .other; return }
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
            kind = .offline
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            kind = .hostNotFound
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            kind = .noAnswer
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid:
            kind = .certificate
        default:
            kind = .other
        }
    }
}
