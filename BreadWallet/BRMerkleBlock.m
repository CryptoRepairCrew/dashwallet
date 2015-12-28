//
//  BRMerkleBlock.m
//  DashWallet
//
//  Created by Aaron Voisine on 10/22/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRMerkleBlock.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Dash.h"

#define MAX_TIME_DRIFT    (2*60*60)     // the furthest in the future a block is allowed to be timestamped
#define MAX_PROOF_OF_WORK 0x1e0fffff   // highest value for difficulty target (higher values are less difficult)


// from https://en.bitcoin.it/wiki/Protocol_specification#Merkle_Trees
// Merkle trees are binary trees of hashes. Merkle trees in darkcoin use  , a cobined hash of 11 of the NIST
// SHA-3 finalists. If, when forming a row in the tree (other than the root of the tree), it would have an odd
// number of elements, the final hash is duplicated to ensure that the row has an even number of hashes. First
// form the bottom row of the tree with the ordered x11 hashes of the byte streams of the transactions in the block.
// Then the row above it consists of half that number of hashes. Each entry is the x11 of the 64-byte concatenation
// of the corresponding two hashes below it in the tree. This procedure repeats recursively until we reach a row
// consisting of just a single hash. This is the merkle root of the tree.
//
// from https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki#Partial_Merkle_branch_format
// The encoding works as follows: we traverse the tree in depth-first order, storing a bit for each traversed node,
// signifying whether the node is the parent of at least one matched leaf txid (or a matched txid itself). In case we
// are at the leaf level, or this bit is 0, its merkle node hash is stored, and its children are not explored further.
// Otherwise, no hash is stored, but we recurse into both (or the only) child branch. During decoding, the same
// depth-first traversal is performed, consuming bits and hashes as they written during encoding.
//
// example tree with three transactions, where only tx2 is matched by the bloom filter:
//
//     merkleRoot
//      /     \
//    m1       m2
//   /  \     /  \
// tx1  tx2 tx3  tx3
//
// flag bits (little endian): 00001011 [merkleRoot = 1, m1 = 1, tx1 = 0, tx2 = 1, m2 = 0, byte padding = 000]
// hashes: [tx1, tx2, m2]

@interface BRMerkleBlock ()

@property (nonatomic, strong) NSData *blockHash;
    
@end

@implementation BRMerkleBlock

// message can be either a merkleblock or header message
+ (instancetype)blockWithMessage:(NSData *)message
{
    return [[self alloc] initWithMessage:message];
}

- (instancetype)initWithMessage:(NSData *)message
{
    if (! (self = [self init])) return nil;
    
    if (message.length < 80) return nil;

    NSUInteger off = 0, l = 0, len = 0;
    NSMutableData *d = [NSMutableData data];

    _version = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _prevBlock = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _merkleRoot = [message hashAtOffset:off];
    off += CC_SHA256_DIGEST_LENGTH;
    _timestamp = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _target = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _nonce = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    _totalTransactions = [message UInt32AtOffset:off];
    off += sizeof(uint32_t);
    len = (NSUInteger)[message varIntAtOffset:off length:&l]*CC_SHA256_DIGEST_LENGTH;
    off += l;
    _hashes = (off + len > message.length) ? nil : [message subdataWithRange:NSMakeRange(off, len)];
    off += len;
    _flags = [message dataAtOffset:off length:&l];
    _height = BLOCK_UNKNOWN_HEIGHT;
    
    [d appendUInt32:_version];
    [d appendData:_prevBlock];
    [d appendData:_merkleRoot];
    [d appendUInt32:_timestamp];
    [d appendUInt32:_target];
    [d appendUInt32:_nonce];
    _blockHash = d.HashGroestl_2;

    return self;
}

- (instancetype)initWithBlockHash:(NSData *)blockHash version:(uint32_t)version prevBlock:(NSData *)prevBlock
merkleRoot:(NSData *)merkleRoot timestamp:(uint32_t)timestamp target:(uint32_t)target nonce:(uint32_t)nonce
totalTransactions:(uint32_t)totalTransactions hashes:(NSData *)hashes flags:(NSData *)flags height:(uint32_t)height
{
    if (! (self = [self init])) return nil;
    
    _blockHash = blockHash;
    _version = version;
    _prevBlock = prevBlock;
    _merkleRoot = merkleRoot;
    _timestamp = timestamp;
    _target = target;
    _nonce = nonce;
    _totalTransactions = totalTransactions;
    _hashes = hashes;
    _flags = flags;
    _height = height;
    
    return self;
}

// true if merkle tree and timestamp are valid, and proof-of-work matches the stated difficulty target
// NOTE: This only checks if the block difficulty matches the difficulty target in the header. It does not check if the
// target is correct for the block's height in the chain. Use verifyDifficultyFromPreviousBlock: for that.
- (BOOL)isValid
{
    // target is in "compact" format, where the most significant byte is the size of resulting value in bytes, the next
    // bit is the sign, and the remaining 23bits is the value after having been right shifted by (size - 3)*8 bits
    static const uint32_t maxsize = MAX_PROOF_OF_WORK >> 24, maxtarget = MAX_PROOF_OF_WORK & 0x00ffffffu;
    const uint32_t *b = _blockHash.bytes, size = _target >> 24, target = _target & 0x00ffffffu;
    NSMutableData *d = [NSMutableData data];
    int hashIdx = 0, flagIdx = 0;

    
    if (_totalTransactions > 0) { // no need to check if only getting headers
        NSData *merkleRoot =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return hash;
        } :^id (id left, id right) {
            [d setData:left];
            [d appendData:(right) ? right : left]; // if right branch is missing, duplicate left branch
            return d.SHA256_2; //this is right for dash, it should not be x11
        }];
        if (![merkleRoot isEqual:_merkleRoot]) {
            NSLog(@"Merkle root is not valid : check failed");
            return NO; // merkle root check failed
        }
    }
    
    // check if timestamp is too far in future
    //TODO: use estimated network time instead of system time (avoids timejacking attacks and misconfigured time)
    if (_timestamp > [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 + MAX_TIME_DRIFT) {
        NSLog(@"Merkle root is not valid : timestamp too far in the future");
        return NO; // timestamp too far in future
    }
    
    // check if proof-of-work target is out of range
    if (target == 0 || target & 0x00800000u || size > maxsize || (size == maxsize && target > maxtarget)) {
        NSLog(@"Merkle root is not valid : proof of work target is out of range");
        return NO;
    }

    d = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    if (size > 3) *(uint32_t *)((uint8_t *)d.mutableBytes + size - 3) = CFSwapInt32HostToLittle(target);
    else *(uint32_t *)d.mutableBytes = CFSwapInt32HostToLittle(target >> (3 - size)*8);
    
    for (int i = CC_SHA256_DIGEST_LENGTH/sizeof(uint32_t) - 1; i >= 0; i--) { // check proof-of-work
        if (CFSwapInt32LittleToHost(b[i]) < CFSwapInt32LittleToHost(((const uint32_t *)d.bytes)[i])) break;
        if (CFSwapInt32LittleToHost(b[i]) > CFSwapInt32LittleToHost(((const uint32_t *)d.bytes)[i])) return NO;
    }
    
    return YES;
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData data];
    
    [d appendUInt32:_version];
    [d appendData:_prevBlock];
    [d appendData:_merkleRoot];
    [d appendUInt32:_timestamp];
    [d appendUInt32:_target];
    [d appendUInt32:_nonce];
    [d appendUInt32:_totalTransactions];
    [d appendVarInt:_hashes.length/CC_SHA256_DIGEST_LENGTH];
    [d appendData:_hashes];
    [d appendVarInt:_flags.length];
    [d appendData:_flags];
    
    return d;
}

// true if the given tx hash is included in the block
- (BOOL)containsTxHash:(NSData *)txHash
{
    for (NSUInteger i = 0; i < _hashes.length/CC_SHA256_DIGEST_LENGTH; i += CC_SHA256_DIGEST_LENGTH) {
        if ([txHash isEqual:[_hashes hashAtOffset:i]]) return YES;
    }
    
    return NO;
}

// returns an array of the matched tx hashes
- (NSArray *)txHashes
{
    int hashIdx = 0, flagIdx = 0;
    NSArray *txHashes =
        [self _walk:&hashIdx :&flagIdx :0 :^id (NSData *hash, BOOL flag) {
            return (flag && hash) ? @[hash] : @[];
        } :^id (id left, id right) {
            return [left arrayByAddingObjectsFromArray:right];
        }];
    
    return txHashes;
}

- (BOOL)verifyDifficultyWithPreviousBlocks:(NSMutableDictionary *)previousBlocks
{
//    int V3_FORK_HEIGHT = 99999;
//    NSLog(@"Checking Difficulties");
//    uint32_t darkGravityWaveTarget;
//    if (self.height > V3_FORK_HEIGHT)
//    {
//        NSLog(@"Checking DGW V3 Difficulty at Block %d", self.height);
//        darkGravityWaveTarget = [self darkGravityWaveV3TargetWithPreviousBlocks:previousBlocks];
//    }
//    else
//    {
//        darkGravityWaveTarget = [self darkGravityWaveTargetWithPreviousBlocks:previousBlocks];
//    }
    uint32_t darkGravityWaveTarget = [self darkGravityWaveV3TargetWithPreviousBlocks:previousBlocks];
    int32_t diff = (self.target & 0x00ffffffu) - darkGravityWaveTarget;
    return true;
    return (abs(diff) < 10);

}

-(int32_t)darkGravityWaveTargetWithPreviousBlocks:(NSMutableDictionary *)previousBlocks {
    /* current difficulty formula, darkcoin - based on DarkGravity v1, original work done by evan duffield, modified for iOS */
    BRMerkleBlock *BlockLastSolved = previousBlocks[self.prevBlock];
    BRMerkleBlock *BlockReading    = previousBlocks[self.prevBlock];
    int64_t nBlockTimeAverage = 0;
    int64_t nBlockTimeAveragePrev = 0;
    int64_t nBlockTimeCount = 0;
    int64_t nBlockTimeSum2 = 0;
    int64_t nBlockTimeCount2 = 0;
    int64_t LastBlockTime = 0;
    int64_t PastBlocksMin = 12;
    int64_t PastBlocksMax = 120;
    int64_t CountBlocks = 0;
    int64_t nTargetSpacing = 1 * 60; // groestlcoin every 60 seconds
    long double PastDifficultyAverage = 0;
    long double PastDifficultyAveragePrev = 0;
    
    if (_prevBlock == NULL || BlockLastSolved.height == 0 || BlockLastSolved.height < PastBlocksMin) {
        // This is the first block or the height is < PastBlocksMin
        // Return minimal required work. (1e0ffff0)
        return MAX_PROOF_OF_WORK & 0x00ffffffu;
    }
    
    // loop over the past n blocks, where n == PastBlocksMax
    for (unsigned int i = 1; BlockReading && BlockReading.height > 0; i++) {
        if (PastBlocksMax > 0 && i > PastBlocksMax) { break; }
        CountBlocks++;
        
        if(CountBlocks <= PastBlocksMin) {
            if (CountBlocks == 1) { PastDifficultyAverage = BlockReading->_target; }
            else { PastDifficultyAverage = ((BlockReading->_target - PastDifficultyAveragePrev) / CountBlocks) + PastDifficultyAveragePrev; }
            PastDifficultyAveragePrev = PastDifficultyAverage;
        }

        
        // If this is the second iteration (LastBlockTime was set)
        if(LastBlockTime > 0){
            int64_t Diff = LastBlockTime - BlockReading.timestamp;
            if(Diff < 0 )
            {
                Diff = 0;
            }
            if(nBlockTimeCount <= PastBlocksMin) {
                nBlockTimeCount++;
                
                if (nBlockTimeCount == 1) { nBlockTimeAverage = Diff; }
                else { nBlockTimeAverage = ((Diff - nBlockTimeAveragePrev) / nBlockTimeCount) + nBlockTimeAveragePrev; }
                nBlockTimeAveragePrev = nBlockTimeAverage;

            }
            nBlockTimeCount2++;
            nBlockTimeSum2 += Diff;
        }
        LastBlockTime = BlockReading.timestamp;
        
        if (BlockReading->_prevBlock == NULL) { assert(BlockReading); break; }
        BlockReading = previousBlocks[BlockReading.prevBlock];
    }
    
    long double darkTarget = PastDifficultyAverage;
    if (nBlockTimeCount != 0 && nBlockTimeCount2 != 0) {
        double SmartAverage = (((nBlockTimeAverage)*0.7)+((nBlockTimeSum2 / nBlockTimeCount2)*0.3));
        if(SmartAverage < 1) SmartAverage = 1;
        double Shift = nTargetSpacing/SmartAverage;

        int64_t nActualTimespan = (CountBlocks*nTargetSpacing)/Shift;
        int64_t nTargetTimespan = (CountBlocks*nTargetSpacing);
        if (nActualTimespan < nTargetTimespan/3)
            nActualTimespan = nTargetTimespan/3;
        if (nActualTimespan > nTargetTimespan*3)
            nActualTimespan = nTargetTimespan*3;

        // Retarget
        darkTarget *= nActualTimespan;
        darkTarget /= nTargetTimespan;
    }
    
    // If calculated difficulty is lower than the minimal diff, set the new difficulty to be the minimal diff.
    if (darkTarget > MAX_PROOF_OF_WORK){
        darkTarget = MAX_PROOF_OF_WORK;
    }
    
    // Return the new diff.
    return (uint32_t)darkTarget;
}


-(int32_t)darkGravityWaveV3TargetWithPreviousBlocks:(NSMutableDictionary *)previousBlocks {
    /* current difficulty formula, darkcoin - based on DarkGravity v3, original work done by evan duffield, modified for iOS */
    BRMerkleBlock *previousBlock = previousBlocks[self.prevBlock];
    
    int64_t nActualTimespan = 0;
    int64_t lastBlockTime = 0;
    int64_t blockCount = 0;
    int64_t sumTargets = 0;
    int64_t PastBlocksMin = 24;
    int64_t PastBlocksMax = 24;
    
    if (_prevBlock == NULL || previousBlock.height == 0 || previousBlock.height < PastBlocksMin) {
        // This is the first block or the height is < PastBlocksMin
        // Return minimal required work. (1e0ffff0)
        return MAX_PROOF_OF_WORK & 0x00ffffffu;
    }
    
    BRMerkleBlock *currentBlock = previousBlock;
    
    // loop over the past n blocks, where n == PastBlocksMax
    for (blockCount = 1; currentBlock && currentBlock.height > 0 && blockCount<= PastBlocksMax; blockCount++) {
        
        // Calculate average difficulty based on the blocks we iterate over in this for loop
        if(blockCount <= PastBlocksMin) {
            uint32_t currentTarget = currentBlock.target & 0x00ffffffu;
            if (blockCount == 1) {
                sumTargets = currentTarget * 2;
            } else {
                sumTargets += currentTarget;
            }
        }
        
        // If this is the second iteration (LastBlockTime was set)
        if(lastBlockTime > 0){
            // Calculate time difference between previous block and current block
            int64_t currentBlockTime = currentBlock.timestamp;
            int64_t diff = ((lastBlockTime) - (currentBlockTime));
            // Increment the actual timespan
            nActualTimespan += diff;
        }
        // Set lastBlockTime to the block time for the block in current iteration
        lastBlockTime = currentBlock.timestamp;
        
        if (previousBlock == NULL) { assert(currentBlock); break; }
        currentBlock = previousBlocks[currentBlock.prevBlock];
    }
    
    // darkTarget is the difficulty
    long double darkTarget = sumTargets / (long double)(blockCount);
    
    // nTargetTimespan is the time that the CountBlocks should have taken to be generated.
    long double nTargetTimespan = (blockCount - 1)* (1*60);
    
    // Limit the re-adjustment to 3x or 0.33x
    // We don't want to increase/decrease diff too much.
    if (nActualTimespan < nTargetTimespan/3.0f)
        nActualTimespan = nTargetTimespan/3.0f;
    if (nActualTimespan > nTargetTimespan*3.0f)
        nActualTimespan = nTargetTimespan*3.0f;
    
    // Calculate the new difficulty based on actual and target timespan.
    darkTarget *= nActualTimespan / nTargetTimespan;
    
    // If calculated difficulty is lower than the minimal diff, set the new difficulty to be the minimal diff.
    if (darkTarget > MAX_PROOF_OF_WORK){
        darkTarget = MAX_PROOF_OF_WORK;
    }
    
    // Return the new diff.
    return (uint32_t)darkTarget;
}


// recursively walks the merkle tree in depth first order, calling leaf(hash, flag) for each stored hash, and
// branch(left, right) with the result from each branch
- (id)_walk:(int *)hashIdx :(int *)flagIdx :(int)depth :(id (^)(NSData *, BOOL))leaf :(id (^)(id, id))branch
{
    if ((*flagIdx)/8 >= _flags.length || (*hashIdx + 1)*CC_SHA256_DIGEST_LENGTH > _hashes.length) return leaf(nil, NO);
    
    BOOL flag = (((const uint8_t *)_flags.bytes)[*flagIdx/8] & (1 << (*flagIdx % 8)));
    
    (*flagIdx)++;
    
    if (! flag || depth == (int)(ceil(log2(_totalTransactions)))) {
        NSData *hash = [_hashes hashAtOffset:(*hashIdx)*CC_SHA256_DIGEST_LENGTH];
        
        (*hashIdx)++;
        return leaf(hash, flag);
    }
    
    id left = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    id right = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch];
    
    return branch(left, right);
}

- (NSUInteger)hash
{
    if (_blockHash.length < sizeof(NSUInteger)) return [super hash];
    return *(const NSUInteger *)_blockHash.bytes;
}

- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[BRMerkleBlock class]] && [[object blockHash] isEqual:_blockHash]);
}

@end
