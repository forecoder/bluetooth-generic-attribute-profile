//
//  DarwinPeer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/14/18.
//

import Foundation
import Bluetooth

#if canImport(CoreBluetooth)

import CoreBluetooth

internal extension CBCentral {
    
    var gattIdentifier: UUID {
        
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
}

internal extension CBPeripheral {
    
    var gattIdentifier: UUID {
        
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
    
    #if os(macOS)
    var address: BluetoothAddress? {
        
        guard let addressString = self.value(forKey: "BDAddress") as? String,
            let address = BluetoothAddress(rawValue: addressString)
            else { return nil }
        
        return address
    }
    #endif
}

#endif
