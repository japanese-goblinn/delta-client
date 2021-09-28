//
//  BlockEntity.swift
//  DeltaCore
//
//  Created by Rohan van Klinken on 13/1/21.
//

import Foundation

public struct BlockEntity {
  public let position: Position
  public let identifier: Identifier
  public let nbt: NBT.Compound
}