//
//  SocketLayer.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 31/3/21.
//

import Foundation
import Network
import os

class SocketLayer: OutermostNetworkLayer {
  var outboundSuccessor: OutboundNetworkLayer?
  var inboundSuccessor: InboundNetworkLayer?
  var inboundThread: DispatchQueue
  var ioThread: DispatchQueue
  var eventManager: EventManager<ServerEvent>
  
  var connection: NWConnection
  var state: State = .idle
  
  var host: String
  var port: UInt16
  
  enum State {
    case idle
    case connecting
    case connected
    case disconnected
  }
  
  init(_ host: String, _ port: UInt16, inboundThread: DispatchQueue, ioThread: DispatchQueue, eventManager: EventManager<ServerEvent>) {
    self.host = host
    self.port = port
    
    self.eventManager = eventManager
    self.inboundThread = inboundThread
    self.ioThread = ioThread
    
    self.connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(rawValue: port)!,
      using: .tcp
    )
    
    self.connection.stateUpdateHandler = stateUpdateHandler
  }
  
  // Connection
  
  func connect() {
    state = .connecting
    connection.start(queue: ioThread)
  }
  
  func disconnect() {
    state = .disconnected
    connection.cancel()
  }
  
  // Receive
  
  func receive() {
    connection.receive(minimumIncompleteLength: 0, maximumLength: 4096, completion: {
      (data, context, isComplete, error) in
      if data == nil {
        return
      } else if error != nil {
        self.handleNWError(error!)
        return
      }
      
      let bytes = [UInt8](data!)
      let buffer = Buffer(bytes)
      
      self.inboundThread.async {
        let bufferCopy = buffer
        self.inboundSuccessor?.handleInbound(bufferCopy)
      }
      
      if self.state != .disconnected {
        self.receive()
      }
    })
  }
  
  // Send
  
  func handleOutbound(_ buffer: Buffer) {
    let bytes = buffer.bytes
    connection.send(content: Data(bytes), completion: .idempotent)
  }
  
  // Housekeeping
  
  private func stateUpdateHandler(newState: NWConnection.State) {
    switch(newState) {
      case .ready:
        state = .connected
        receive()
        eventManager.triggerEvent(.connectionReady)
      case .waiting(let error):
        handleNWError(error)
      case .failed(let error):
        state = .disconnected
        handleNWError(error)
      case .cancelled:
        state = .disconnected
      default:
        break
    }
  }
  
  private func handleNWError(_ error: NWError) {
    if error == NWError.posix(.ECONNREFUSED) {
      Logger.error("connection refused: '\(self.host):\(self.port)'")
    } else if error == NWError.dns(-65554) {
      Logger.error("server at '\(self.host):\(self.port)' possibly uses SRV records (unsupported)")
    }
  }
}