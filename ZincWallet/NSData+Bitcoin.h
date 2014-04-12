//
//  NSData+Bitcoin.h
//  ZincWallet
//
//  Created by Aaron Voisine on 10/9/13.
//  Copyright (c) 2013 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Bitcoin)

- (uint8_t)UInt8AtOffset:(NSUInteger)offset;
- (uint16_t)UInt16AtOffset:(NSUInteger)offset;
- (uint32_t)UInt32AtOffset:(NSUInteger)offset;
- (uint64_t)UInt64AtOffset:(NSUInteger)offset;
- (uint64_t)varIntAtOffset:(NSUInteger)offset length:(NSUInteger *)length;
- (NSData *)hashAtOffset:(NSUInteger)offset;
- (NSString *)stringAtOffset:(NSUInteger)offset length:(NSUInteger *)length;
- (NSData *)dataAtOffset:(NSUInteger)offset length:(NSUInteger *)length;
- (NSArray *)scriptDataElements;

@end
