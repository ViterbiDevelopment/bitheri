//
//  BTBlockProvider.m
//  bitheri
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "BTBlockProvider.h"
#import "BTDatabaseManager.h"
#import "NSString+Base58.h"

static BTBlockProvider *provider;

@implementation BTBlockProvider {

}

+ (instancetype)instance; {
    @synchronized (self) {
        if (provider == nil) {
            provider = [[self alloc] init];
        }
    }
    return provider;
}

- (NSMutableArray *)getAllBlocks; {
    __block NSMutableArray *blocks = [NSMutableArray new];
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks order by block_no desc";
        FMResultSet *rs = [db executeQuery:sql];
        while ([rs next]) {
            [blocks addObject:[self format:rs]];
        }
        [rs close];
    }];
    return blocks;
}

- (NSMutableArray *)getBlocksFrom:(uint)blockNo;{
    __block NSMutableArray *blocks = [NSMutableArray new];
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where block_no>? order by block_no desc";
        FMResultSet *rs = [db executeQuery:sql, @(blockNo)];
        while ([rs next]) {
            [blocks addObject:[self format:rs]];
        }
        [rs close];
    }];
    return blocks;
}

- (int)getBlockCount {
    __block int count = 0;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select count(*) cnt from blocks ";
        FMResultSet *rs = [db executeQuery:sql];
        if ([rs next]) {
            count = [rs intForColumn:@"cnt"];
        }
        [rs close];
    }];
    return count;
}

- (BTBlockItem *)getLastBlock {
    __block BTBlockItem *blockItem = nil;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where is_main=? order by block_no desc limit 1";
        FMResultSet *rs = [db executeQuery:sql, @1];
        while ([rs next]) {
            blockItem = [self format:rs];
        }
        [rs close];
    }];
    return blockItem;
}

- (BTBlockItem *)getLastOrphanBlock {
    __block BTBlockItem *blockItem = nil;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where is_main=? order by block_no desc limit 1";
        FMResultSet *rs = [db executeQuery:sql, @0];
        while ([rs next]) {
            blockItem = [self format:rs];
        }
        [rs close];
    }];
    return blockItem;
}

- (BTBlockItem *)getBlock:(NSData *)blockHash {
    __block BTBlockItem *blockItem = nil;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where block_hash=? ";
        FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:blockHash]];
        if ([rs next]) {
            blockItem = [self format:rs];
        }
        [rs close];
    }];
    return blockItem;
}

- (BTBlockItem *)getOrphanBlockByPrevHash:(NSData *)prevHash;{
    __block BTBlockItem *blockItem = nil;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where block_prev=? and is_main=?";
        FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:prevHash], @(NO)];
        if ([rs next]) {
            blockItem = [self format:rs];
        }
        [rs close];
    }];
    return blockItem;
}

- (BTBlockItem *)getMainChainBlock:(NSData *)blockHash;{
    __block BTBlockItem *blockItem = nil;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select * from blocks where block_hash=? and is_main=?";
        FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:blockHash], @(YES)];
        if ([rs next]) {
            blockItem = [self format:rs];
        }
        [rs close];
    }];
    return blockItem;
}

- (NSArray *)exists:(NSSet *)blockHashes; {
    __block NSMutableArray *exists = [NSMutableArray new];
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select count(0) cnt from blocks where block_hash=?";
        for (NSData *blockHash in blockHashes) {
            FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:blockHash]];
            while ([rs next]) {
                int cnt = [rs intForColumn:@"cnt"];
                if (cnt == 1) {
                    [exists addObject:blockHash];
                }
            }
            [rs close];
        }
    }];
    return exists;
}

- (BOOL)isExist:(NSData *)blockHash; {
    __block BOOL result = NO;
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select count(0) cnt from blocks where block_hash=?";
        FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:blockHash]];
        while ([rs next]) {
            int cnt = [rs intForColumn:@"cnt"];
            if (cnt > 0) {
                result = YES;
            }
        }
        [rs close];
    }];
    return result;
}

- (void)addBlocks:(NSArray *)blocks; {
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        [db beginTransaction];
        for (BTBlockItem *block in blocks) {
            [self addBlock:block db:db];
        }
        [db commit];
    }];
}

- (BOOL)blockExists:(NSData *)blockHash db:(FMDatabase *)db {
    NSString *sql = @"select count(0) cnt from blocks where block_hash=?";
    FMResultSet *rs = [db executeQuery:sql, [NSString base58WithData:blockHash]];
    int cnt = 0;
    if ([rs next]) {
        cnt = [rs intForColumn:@"cnt"];
    }
    [rs close];
    return cnt == 1;
}

- (void)addBlock:(BTBlockItem *)block {
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        if (![self blockExists:block.blockHash db:db]) {
            [self addBlock:block db:db];
        }
    }];
}

- (void)updateBlock:(NSData *)blockHash withIsMain:(BOOL)isMain;{
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"update blocks set is_main=? where block_hash=?";
        [db executeUpdate:sql, @(isMain), [NSString base58WithData:blockHash]];
    }];
}

- (void)addBlock:(BTBlockItem *)block db:(FMDatabase *)db {
    NSString *sql = @"insert into blocks(block_no,block_hash,block_root,block_ver,block_bits,block_nonce,block_time"
            ",block_prev,is_main) values(?,?,?,?,?,?,?,?,?)";
    [db executeUpdate:sql, @(block.blockNo), [NSString base58WithData:block.blockHash]
            , [NSString base58WithData:block.blockRoot], @(block.blockVer)
            , @(block.blockBits), @(block.blockNonce)
            , @(block.blockTime), [NSString base58WithData:block.blockPrev], @(block.isMain)];
}

- (void)removeBlock:(NSData *)blockHash;{
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"delete from blocks where block_hash=?";
        [db executeUpdate:sql, [NSString base58WithData:blockHash]];
    }];
}

- (void)cleanOldBlock;{
    [[[BTDatabaseManager instance] getDbQueue] inDatabase:^(FMDatabase *db) {
        NSString *sql = @"select count(0) cnt from blocks";
        FMResultSet *rs = [db executeQuery:sql];
        int cnt = 0;
        if ([rs next]) {
            cnt = [rs intForColumn:@"cnt"];
        }
        [rs close];
        if (cnt > 5000) {
            sql = @"select max(block_no) max_block_no from blocks where is_main=1";
            rs = [db executeQuery:sql];
            int maxBlockNo = 0;
            if ([rs next]) {
                maxBlockNo = [rs intForColumn:@"max_block_no"];
            }
            [rs close];
            int interval = 2016;
            int minBlockCount = 100;

            int left = maxBlockNo % interval;

            int blockNo = 0;
            if (left > minBlockCount)
                blockNo = maxBlockNo - left;
            else
                blockNo = maxBlockNo - left - interval;

            sql = @"delete from blocks where block_no<?";
            [db executeUpdate:sql, @(blockNo)];
        }
    }];
}

- (BTBlockItem *)format:(FMResultSet *)rs {
    BTBlockItem *block = [[BTBlockItem alloc] init];
    block.blockNo = (uint) [rs intForColumn:@"block_no"];
    block.blockHash = [[rs stringForColumn:@"block_hash"] base58ToData];
    block.blockRoot = [[rs stringForColumn:@"block_root"] base58ToData];
    block.blockVer = (uint) [rs intForColumn:@"block_ver"];
    block.blockBits = (uint) [rs intForColumn:@"block_bits"];
    block.blockNonce = (uint) [rs intForColumn:@"block_nonce"];
    block.blockTime = (uint) [rs intForColumn:@"block_time"];
    block.blockPrev = [[rs stringForColumn:@"block_prev"] base58ToData];
    block.isMain = [rs boolForColumn:@"is_main"];
    return block;
}

@end