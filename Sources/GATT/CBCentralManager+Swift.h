//
//  CBCentralManager+Swift.h
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#import <CoreBluetooth/CoreBluetooth.h>

@interface CBCentralManager (Swift)

- (nonnull instancetype)initWithSwiftDelegate:(nullable id)delegate
                                        queue:(nullable dispatch_queue_t)queue;

@end
