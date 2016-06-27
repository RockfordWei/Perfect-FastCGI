//
//  FastCGIServer.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 7/6/15.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PerfectNet
import PerfectThread
import PerfectLib

#if os(Linux)
import SwiftGlibc
#else
import Darwin
#endif

let fcgiVersion1: UInt8 =		1
let fcgiBeginRequest: UInt8 =	1
let fcgiEndRequest: UInt8 =		3
let fcgiParams: UInt8 =			4
let fcgiStdin: UInt8 =			5
let fcgiStdout: UInt8 =			6
let fcgiData: UInt8 =			8
let fcgiXStdin: UInt8 = 		50
let fcgiRequestComplete =       0
let fcgiTimeoutSeconds =        5.0
let fcgiBaseRecordSize =        8
let fcgiBodyChunkSize =         0xFFFF

class FastCGIRecord {
    
    var version: UInt8 = 0
    var recType: UInt8 = 0
    var requestId: UInt16 = 0
    var contentLength: UInt16 = 0
    var paddingLength: UInt8 = 0
    var reserved: UInt8 = 0
    var content: [UInt8]? = nil
    var padding: [UInt8]? = nil
}

/// A server for the FastCGI protocol.
/// Listens for requests on either a named pipe or a TCP socket. Once started, it does not stop or return outside of a catastrophic error.
/// When a request is received, the server will instantiate a `WebRequest`/`WebResponse` pair and they will handle the remainder of the request.
public class FastCGIServer {

    private var net: NetTCP?
    /// Switch to user after binding socket file
    public var runAsUser: String?

	/// Empty public initializer
	public init() {

	}

	/// Start the server on the indicated named pipe
	public func start(namedPipe name: String) throws {
		if access(name, F_OK) != -1 {
			// exists. remove it
			unlink(name)
		}
		let pipe = NetNamedPipe()
		pipe.initSocket()
		try pipe.bind(address: name)
		pipe.listen()
		chmod(name, mode_t(S_IRWXU|S_IRWXO|S_IRWXG))
        
        if let runAs = self.runAsUser {
            try PerfectServer.switchTo(userName: runAs)
        }
		
        self.net = pipe

		defer { pipe.close() }

		print("Starting FastCGI server on named pipe "+name)

		self.start()
	}

	/// Start the server on the indicated TCP port and optional address
	public func start(port prt: UInt16, bindAddress: String = "0.0.0.0") throws {
		let socket = NetTCP()
		socket.initSocket()
		try socket.bind(port: prt, address: bindAddress)
		socket.listen()
		defer { socket.close() }
		print("Starting FastCGi server on \(bindAddress):\(prt)")
		self.start()
	}

	func start() {
		guard let n = self.net else {
            return
        }
        n.forEachAccept {
            [weak self]
            net in
            guard let n = net else {
                return
            }
            Threading.dispatch {
                self?.handleConnection(net: n)
            }
        }
	}

	func handleConnection(net: NetTCP) {
		let fcgiReq = FastCGIRequest(connection: net)
        fcgiReq.readRequest { [weak self]
            status in
            if case .ok = status {
                self?.runRequest(fcgiReq)
            } else {
                net.close()
            }
        }
	}

	func runRequest(_ request: FastCGIRequest) {
		let response = FastCGIResponse(request: request)
        Routing.handleRequest(request, response: response)
	}
}