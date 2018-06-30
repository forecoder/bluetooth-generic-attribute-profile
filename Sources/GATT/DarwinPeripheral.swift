//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS)
    
    import CoreBluetooth
    import CoreLocation
    
    /// The platform specific peripheral.
    public typealias PeripheralManager = DarwinPeripheral

    public final class DarwinPeripheral: NSObject, PeripheralProtocol, CBPeripheralManagerDelegate {
        
        // MARK: - Properties
        
        public let options: Options
        
        public var log: ((String) -> ())?
        
        public var stateChanged: (DarwinBluetoothState) -> () = { _ in }
        
        public var state: DarwinBluetoothState {
            
            return unsafeBitCast(internalManager.state, to: DarwinBluetoothState.self)
        }
        
        public var willRead: ((PeripheralReadRequest) -> ATT.Error?)?
        
        public var willWrite: ((PeripheralWriteRequest) -> ATT.Error?)?
        
        public var didWrite: ((PeripheralWriteRequest) -> ())?
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBPeripheralManager = CBPeripheralManager(delegate: self, queue: self.queue, options: self.options.optionsDictionary)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Internal Queue", attributes: [])
        
        private var addServiceState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var startAdvertisingState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var database = Database()
        
        // MARK: - Initialization
        
        public init(options: Options = Options()) {
            
            self.options = options
        }
        
        // MARK: - Methods
        
        public func start() throws {
            
            let options = AdvertisingOptions()
            
            try start(options: options)
        }
        
        public func start(options: AdvertisingOptions) throws {
            
            assert(startAdvertisingState == nil, "Already started advertising")
            
            let semaphore = DispatchSemaphore(value: 0)
            
            startAdvertisingState = (semaphore, nil) // set semaphore
            
            internalManager.startAdvertising(options.optionsDictionary)
            
            let _ = semaphore.wait(timeout: .distantFuture)
            
            let error = startAdvertisingState?.error
            
            // clear
            startAdvertisingState = nil
            
            if let error = error {
                
                throw error
            }
        }
        
        public func stop() {
            
            internalManager.stopAdvertising()
        }
        
        public func add(service: GATT.Service) throws -> UInt16 {
            
            assert(addServiceState == nil, "Already adding another Service")
            
            /// wait
            
            let semaphore = DispatchSemaphore(value: 0)
            
            addServiceState = (semaphore, nil) // set semaphore
            
            // add service
            let coreService = service.toCoreBluetooth()
            
            // CB add
            internalManager.add(coreService)
            
            let _ = semaphore.wait(timeout: .distantFuture)
            
            let error = addServiceState?.error
            
            // clear
            addServiceState = nil
            
            if let error = error {
                
                throw error
            }
            
            // DB cache add
            return database.add(service: service, coreService)
        }
        
        public func remove(service handle: UInt16) {
            
            // remove from daemon
            let coreService = database.service(for: handle)
            internalManager.remove(coreService)
            
            // remove from cache
            database.remove(service: handle)
        }
        
        public func removeAllServices() {
            
             // remove from daemon
            internalManager.removeAllServices()
            
            // clear cache
            database.removeAll()
        }
        
        /// Return the handles of the characteristics matching the specified UUID.
        public func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
         
            return database.characteristics(for: uuid)
        }
        
        // MARK: Subscript
        
        public subscript(characteristic handle: UInt16) -> Data {
            
            get { return database[characteristic: handle] }
            
            set {
                
                database[characteristic: handle] = newValue
                
                internalManager.updateValue(newValue,
                                            for: database.characteristic(for: handle),
                                            onSubscribedCentrals: nil)
            }
        }
        
        // MARK: - CBPeripheralManagerDelegate
        
        @objc(peripheralManagerDidUpdateState:)
        public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            
            let state = unsafeBitCast(peripheral.state, to: DarwinBluetoothState.self)
            
            log?("Did update state \(state)")
            
            stateChanged(state)
        }
        
        public func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState state: [String : Any]) {
            
            
        }
        
        @objc(peripheralManagerDidStartAdvertising:error:)
        public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
            
            guard let semaphore = startAdvertisingState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            startAdvertisingState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didAddService:error:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            
            if let error = error {
                
                log?("Could not add service \(service.uuid) (\(error))")
                
            } else {
                
                log?("Added service \(service.uuid)")
            }
            
            guard let semaphore = addServiceState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            addServiceState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didReceiveReadRequest:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            
            let peer = Central(request.central)
                        
            let characteristic = database[characteristic: request.characteristic]
            
            let uuid = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
            
            let value = characteristic.value
            
            let readRequest = PeripheralReadRequest(central: peer,
                                                maximumUpdateValueLength: request.central.maximumUpdateValueLength,
                                                uuid: uuid,
                                                handle: characteristic.handle,
                                                value: value,
                                                offset: request.offset)
            
            guard request.offset <= value.count
                else { internalManager.respond(to: request, withResult: .invalidOffset); return }
            
            if let error = willRead?(readRequest) {
                
                internalManager.respond(to: request, withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                return
            }
            
            let requestedValue = request.offset == 0 ? value : Data(value.suffix(request.offset))
            
            request.value = requestedValue
            
            internalManager.respond(to: request, withResult: .success)
        }
        
        @objc(peripheralManager:didReceiveWriteRequests:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            
            assert(requests.isEmpty == false)
            
            var newValues = [Data](repeating: Data(), count: requests.count)
            
            // validate write requests
            for (index, request) in requests.enumerated() {
                
                let peer = Central(request.central)
                
                let characteristic = database[characteristic: request.characteristic]
                
                let value = characteristic.value
                
                let uuid = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
                
                let newBytes = request.value ?? Data()
                
                var newValue = value
                newValue.replaceSubrange(request.offset ..< request.offset + newBytes.count, with: newBytes)
                
                let writeRequest = PeripheralWriteRequest(central: peer,
                                                        maximumUpdateValueLength: request.central.maximumUpdateValueLength,
                                                        uuid: uuid,
                                                        handle: characteristic.handle,
                                                        value: value,
                                                        newValue: newValue)
                
                if let error = willWrite?(writeRequest) {
                    
                    internalManager.respond(to: requests[0], withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                    
                    return
                }
                
                // compute new data
                newValues[index] = newValue
            }
            
            // write new values
            for (index, request) in requests.enumerated() {
                
                let newValue = newValues[index]
                
                database[data: request.characteristic] = newValue
            }
            
            internalManager.respond(to: requests[0], withResult: .success)
        }
        
        @objc
        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
            
            
        }
        
        @objc
        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            
            
        }
        
        @objc
        public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
            
            
        }
    }

// MARK: - Supporting Types

public extension DarwinPeripheral {
    
    public struct Options {
        
        public let showPowerAlert: Bool
        
        public let restoreIdentifier: String?
        
        public init(showPowerAlert: Bool = false,
                    restoreIdentifier: String? = nil) {
            
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
        }
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            
            if showPowerAlert {
                
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            
            #if swift(>=3.2) // Only with Xcode 9 SDK
            if let identifier = self.restoreIdentifier {
                
                options[CBPeripheralManagerOptionRestoreIdentifierKey] = identifier
            }
            #endif
            
            return options
        }
    }
    
    public struct AdvertisingOptions {
        
        /// The local name of the peripheral.
        public let localName: String?
        
        /// An array of service UUIDs.
        public let serviceUUIDs: [BluetoothUUID]
        
        #if os(iOS)
        public let beacon: AppleBeacon?
        #endif
        
        #if os(iOS)
        public init(localName: String? = nil,
                    serviceUUIDs: [BluetoothUUID] = [],
                    beacon: AppleBeacon? = nil) {
            
            self.localName = localName
            self.beacon = beacon
            self.serviceUUIDs = serviceUUIDs
        }
        #else
        public init(localName: String? = nil,
                    serviceUUIDs: [BluetoothUUID] = []) {
            
            self.localName = localName
            self.serviceUUIDs = serviceUUIDs
        }
        #endif
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            
            if let localName = self.localName {
                
                options[CBAdvertisementDataLocalNameKey] = localName
            }
            
            if serviceUUIDs.isEmpty == false {
                
                options[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs.map { $0.toCoreBluetooth() }
            }
            
            #if os(iOS)
            if let beacon = self.beacon {
                
                let beaconRegion = CLBeaconRegion(proximityUUID: beacon.uuid,
                                                  major: beacon.major,
                                                  minor: beacon.minor,
                                                  identifier: beacon.uuid.rawValue)
                
                let peripheralData = beaconRegion.peripheralData(withMeasuredPower: NSNumber(value: beacon.rssi))
                
                // copy key values
                peripheralData.forEach { (key, value) in
                    options[key as! String] = value
                }
            }
            #endif
            
            return options
        }
    }
}

private extension DarwinPeripheral {
    
    final class Database {
        
        struct Service {
            
            let handle: UInt16
        }
        
        struct Characteristic {
            
            let handle: UInt16
            
            let serviceHandle: UInt16
            
            var value: Data
        }
        
        private var services = [CBMutableService: Service]()
        
        private var characteristics = [CBMutableCharacteristic: Characteristic]()
        
        /// Do not access directly, use `newHandle()`
        private var lastHandle: UInt16 = 0x0000
        
        /// Simulate a GATT database.
        private func newHandle() -> UInt16 {
            
            assert(lastHandle != .max)
            
            // starts at 0x0001
            lastHandle += 1
            
            return lastHandle
        }
        
        func add(service: GATT.Service, _ coreService: CBMutableService) -> UInt16 {
            
            let serviceHandle = newHandle()
            
            services[coreService] = Service(handle: serviceHandle)
            
            for (index, characteristic) in ((coreService.characteristics ?? []) as! [CBMutableCharacteristic]).enumerated()  {
                
                let data = service.characteristics[index].value
                
                let characteristicHandle = newHandle()
                
                characteristics[characteristic] = Characteristic(handle: characteristicHandle,
                                                                 serviceHandle: serviceHandle,
                                                                 value: data)
            }
            
            return serviceHandle
        }
        
        func remove(service handle: UInt16) {
            
            let coreService = service(for: handle)
            
            // remove service
            services[coreService] = nil
            (coreService.characteristics as? [CBMutableCharacteristic])?.forEach { characteristics[$0] = nil }
            
            // remove characteristics
            while let index = characteristics.index(where: { $0.value.serviceHandle == handle }) {
                
                characteristics.remove(at: index)
            }
        }
        
        func removeAll() {
            
            services.removeAll()
            characteristics.removeAll()
        }
        
        /// Find the service with the specified handle
        func service(for handle: UInt16) -> CBMutableService {
            
            guard let coreService = services.first(where: { $0.value.handle == handle })?.key
                else { fatalError("Invalid handle \(handle)") }
            
            return coreService
        }
        
        /// Return the handles of the characteristics matching the specified UUID.
        func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
            
            let characteristicUUID = uuid.toCoreBluetooth()
            
            return characteristics
                .filter { $0.key.uuid == characteristicUUID }
                .map { $0.value.handle }
        }
        
        func characteristic(for handle: UInt16) -> CBMutableCharacteristic {
            
            guard let characteristic = characteristics.first(where: { $0.value.handle == handle })?.key
                else { fatalError("Invalid handle \(handle)") }
            
            return characteristic
        }
        
        subscript(characteristic handle: UInt16) -> Data {
            
            get {
                
                guard let value = characteristics.values.first(where: { $0.handle == handle })?.value
                    else { fatalError("Invalid handle \(handle)") }
                
                return value
            }
            
            set {
                
                guard let key = characteristics.first(where: { $0.value.handle == handle })?.key
                    else { fatalError("Invalid handle \(handle)") }
                
                characteristics[key]?.value = newValue
            }
        }
        
        subscript(characteristic uuid: BluetoothUUID) -> Data {
            
            get {
                
                let characteristicUUID = uuid.toCoreBluetooth()
                
                guard let characteristic = characteristics.first(where: { $0.key.uuid == characteristicUUID })?.value
                    else { fatalError("Invalid UUID \(uuid)") }
                
                return characteristic.value
            }
            
            set {
                
                let characteristicUUID = uuid.toCoreBluetooth()
                
                guard let key = characteristics.keys.first(where: { $0.uuid == characteristicUUID })
                    else { fatalError("Invalid UUID \(uuid)") }
                
                characteristics[key]?.value = newValue
            }
        }
        
        private(set) subscript(characteristic characteristic: CBCharacteristic) -> Characteristic {
            
            get {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                guard let value = characteristics[key]
                    else { fatalError("No stored characteristic matches \(characteristic)") }
                
                return value
            }
            
            set {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                characteristics[key] = newValue
            }
        }
        
        subscript(data characteristic: CBCharacteristic) -> Data {
            
            get {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                guard let cache = characteristics[key]
                    else { fatalError("No stored characteristic matches \(characteristic)") }
                
                return cache.value
            }
            
            set { self[characteristic: characteristic].value = newValue }
        }
    }
}

#endif
