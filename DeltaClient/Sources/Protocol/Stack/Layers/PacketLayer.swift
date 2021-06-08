//
//  PacketLayer.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 31/3/21.
//

import Foundation


// TODO: this could do with some refactoring
class PacketLayer: NetworkLayer {
  var inboundSuccessor: InboundNetworkLayer?
  var outboundSuccessor: OutboundNetworkLayer?
  var receiveState: ReceiveState
  
  struct ReceiveState {
    var lengthBytes: [UInt8]
    var length: Int
    var packet: [UInt8]
  }
  
  init() {
    self.receiveState = ReceiveState(lengthBytes: [], length: 0, packet: [])
  }
  
  func handleInbound(_ inBuffer: Buffer) {
    var buffer = inBuffer // mutable copy
    while true {
      if receiveState.length == -1 {
        while buffer.remaining != 0 {
          let byte = buffer.readByte()
          receiveState.lengthBytes.append(byte)
          if byte & 0x80 == 0x00 {
            break
          }
        }
        
        if !receiveState.lengthBytes.isEmpty, let lastLengthByte = receiveState.lengthBytes.last {
          if lastLengthByte & 0x80 == 0x00 {
            // using standalone implementation of varint decoding to hopefully reduce networking overheads slightly?
            receiveState.length = 0
            for i in 0..<receiveState.lengthBytes.count {
              let byte = receiveState.lengthBytes[i]
              receiveState.length += Int(byte & 0x7f) << (i * 7)
            }
          }
        }
      }
      
      if receiveState.length == 0 {
        // TODO: investigate empty packets
        log.debug("received empty packet")
        receiveState.length = -1
        receiveState.lengthBytes = []
      } else if receiveState.length != -1 && buffer.remaining != 0 {
        while buffer.remaining != 0 {
          let byte = buffer.readByte()
          receiveState.packet.append(byte)
          
          if receiveState.packet.count == receiveState.length {
            inboundSuccessor?.handleInbound(Buffer(receiveState.packet))
            receiveState.packet = []
            receiveState.length = -1
            receiveState.lengthBytes = []
            break
          }
        }
      }
      
      if buffer.remaining == 0 {
        break
      }
    }
  }
  
  func handleOutbound(_ buffer: Buffer) {
    var packed = Buffer()
    packed.writeVarInt(Int32(buffer.length))
    packed.writeBytes(buffer.bytes)
    outboundSuccessor?.handleOutbound(packed)
  }
}
