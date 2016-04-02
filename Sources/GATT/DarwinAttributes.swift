//
//  DarwinAttributes.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Bluetooth

#if os(OSX) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    internal protocol CoreBluetoothConvertible {
        
        //associatedtype CoreBluetoothImmutableType
        associatedtype CoreBluetoothMutableType
        
        //init(_ CoreBluetooth: CoreBluetoothImmutableType)
        func toCoreBluetooth() -> CoreBluetoothMutableType
    }
    
    extension Service: CoreBluetoothConvertible {
        
        /*
        init(_ CoreBluetooth: CBService) {
            
            self.UUID = Bluetooth.UUID(foundation: CoreBluetooth.UUID)
            self.primary = CoreBluetooth.isPrimary
            self.includedServices = [] // TODO: Implement included services
            self.characteristics = (CoreBluetooth.characteristics ?? []).map { Characteristic(foundation: $0) }
        }*/
        
        func toCoreBluetooth() -> CBMutableService {
            
            let service = CBMutableService(type: UUID.toFoundation(), primary: primary)
            
            service.characteristics = characteristics.map { $0.toCoreBluetooth() }
            
            return service
        }
    }
    
    extension Characteristic: CoreBluetoothConvertible {
        
        func toCoreBluetooth() -> CBMutableCharacteristic {
            
            let propertiesMask = CBCharacteristicProperties(rawValue: Int(properties.optionsBitmask()))
            
            let permissionsMask = CBAttributePermissions(rawValue: Int(permissions.optionsBitmask()))
            
            let characteristic = CBMutableCharacteristic(type: UUID.toFoundation(), properties: propertiesMask, value: value.toFoundation(), permissions: permissionsMask)
            
            characteristic.descriptors = descriptors.map { $0.toCoreBluetooth() }
            
            return characteristic
        }
    }
    
    extension Descriptor: CoreBluetoothConvertible {
        
        func toCoreBluetooth() -> CBMutableDescriptor {
            
            let foundationUUID = UUID.toFoundation()
            
            // Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported.
            switch foundationUUID.UUIDString {
                
            case CBUUIDCharacteristicUserDescriptionString:
                
                guard let string = String(UTF8Data: value)
                    else { fatalError("Could not parse string for CBMutableDescriptor from \(self)") }
                
                return CBMutableDescriptor(type: foundationUUID, value: string)
                
            case CBUUIDCharacteristicFormatString:
                
                return CBMutableDescriptor(type: foundationUUID, value: value.toFoundation())
                
            default: fatalError("Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported. Unsupported UUID \(UUID).")
            }
        }
    }

#endif