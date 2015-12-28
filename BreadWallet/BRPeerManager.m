//
//  BRPeerManager.m
//  DashWallet
//
//  Created by Aaron Voisine on 10/6/13.
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

#import "BRPeerManager.h"
#import "BRPeer.h"
#import "BRPeerEntity.h"
#import "BRBloomFilter.h"
#import "BRKeySequence.h"
#import "BRTransaction.h"
#import "BRMerkleBlock.h"
#import "BRMerkleBlockEntity.h"
#import "BRWalletManager.h"
#import "NSString+Dash.h"
#import "NSData+Dash.h"
#import "NSManagedObject+Sugar.h"
#import <netdb.h>

#define FIXED_PEERS          @"FixedPeers"
#define PROTOCOL_TIMEOUT     20.0
#define MAX_CONNECT_FAILURES 20 // notify user of network problems after this many connect failures in a row
#define CHECKPOINT_COUNT     (sizeof(checkpoint_array)/sizeof(*checkpoint_array))
#define GENESIS_BLOCK_HASH   ([NSString stringWithUTF8String:checkpoint_array[0].hash].hexToData.reverse)

#if DASH_TESTNET


static const struct { uint32_t height; char *hash; time_t timestamp; uint32_t target; } checkpoint_array[] = {
    {      261, "00000c26026d0815a7e2ce4fa270775f61403c040647ff2c3091f99e894a4618", 1296688602, 0x1d00ffffu }
};

static const char *dns_seeds[] = {
    "ip1.groestlcoin.org",
    "ip2.groestlcoin.org"
};

#else // main net

// blockchain checkpoints - these are also used as starting points for partial chain downloads, so they need to be at
// difficulty transition boundaries in order to verify the block difficulty at the immediately following transition
static const struct { uint32_t height; char *hash; time_t timestamp; uint32_t target; } checkpoint_array[] = {
    { 0, "00000ac5927c594d49cc0bdb81759d0da8297eb614683d3acb62f0703b639023", 1395342829, 0x01000000u },
    { 2016, "00000000022f827cfb0fd67d5ae0f42d757a48cea496017cd52aaf39d6764025", 1395633136, 0x011e0000u },
    { 4032, "0000000001772ac01301089da772e6ea8ab7500c0db063519cb22c18fba977ad", 1395754066, 0x01460000u },
    { 6048, "000000000112a674d071a0d85fedfaba9a9844b3beb48cf7a2d5e9f7283957d3", 1395875402, 0x01430000u },
    { 8064, "0000000001a96b8e05de84452487d4052fe4e0697cc3eb6bce50287cf8717097", 1395996464, 0x02009100u },
    { 10080, "00000000015130d0bdd7a3346a1d351a261df662101d3665fb1d1046075e517d", 1396117729, 0x016c0000u },
    { 12096, "0000000001918fbd7edfa1f2a10d4d8c389546b4491828485c66b156d3c6d7c5", 1396238901, 0x01460000u },
    { 14112, "00000000005d8b7c9be297363ae5a00dab4dc236dd0378681f52a361351e855e", 1396359283, 0x01610000u },
    { 16128, "00000000006d04174fab0f49125562d7db1e68aa85016e2a7e75990abf4e76ae", 1396480059, 0x01560000u },
    { 18144, "0000000000fb7dede5e8b946bc721518bcc956971b53caf635eb31b6cae7c48a", 1396599694, 0x01610000u },
    { 20160, "00000000021334f6883b834ad4969ecddce33b8ae83f4545bb927e172b246577", 1396718053, 0x014d0000u },
    { 22176, "0000000000e4657a83c58a209b275b93e98d5a5eee05ca2667f057b17aee3766", 1396836427, 0x02008800u },
    { 24192, "0000000002352f04740cd406cc80f69ae26b896f4fc8c45723faafded6dacef2", 1396955662, 0x01320000u },
    { 26208, "0000000000945a5e87a84963b64031b388b7719cd1737baf48af41ebcfab4841", 1397073579, 0x02008600u },
    { 28224, "000000000034a1c782bbff1c2375bb84c23f818ae4b9f28ae5565fe7e5ffec0e", 1397189988, 0x02011c00u },
    { 30240, "00000000001188bb4e0936915b618a88653e63193b91b819c7ae6f14f81d95f9", 1397306935, 0x0200b000u },
    { 32256, "00000000004f6460d78fbf3fa3f22d2042c704a796885af0259b75b5a346bd2e", 1397423622, 0x0200db00u },
    { 34272, "000000000013199619f4cfe6360dc425582569d4166db83c433dda75c800bfb1", 1397538344, 0x0200cf00u },
    { 36288, "00000000014948481cf8671ec8dee86a0bdf8b7856b7702041233db612986988", 1397650869, 0x02009a00u },
    { 38304, "0000000000b9f1a19ce276515cac9e1ce07c75656013ca2af904de3dbcfe707d", 1397763323, 0x02009600u },
    { 40320, "0000000000767fa13decb77c468385423a260f38a6156000f16b17aea32a8a6d", 1397875997, 0x02010500u },
    { 42336, "0000000000560db946cbd1479a79dd4fdf18371c702d9f6215dd8541ca68c877", 1397987128, 0x01530000u },
    { 44352, "0000000003630cedb0d5b9f30e719401d16e41af600a64966c8b2994d215a5a8", 1398095749, 0x01460000u },
    { 46368, "00000000017aee1bc756daf199e3c6db3de5d930be74f39fcc0bb5476694d5d7", 1398201579, 0x014a0000u },
    { 48384, "000000000191eb396cca5633e54d7a24e74085d6cc7056096a2e3bdf5479f267", 1398306191, 0x01550000u },
    { 50400, "000000000070038037f3a02a2057cdfab10d33922050c21337927d9d4abc8d24", 1398405939, 0x01690000u },
    { 52416, "0000000001e4da1cabce301da6967a0ac6a1249b73b800436d0a40b918808a74", 1398508405, 0x016c0000u },
    { 54432, "00000000015eeb19c858a4da8eebf02c18c72ce6d850f6ddf6191f808417d176", 1398611068, 0x0200b800u },
    { 56448, "0000000001969e6195f14d700df7543f968964896bc3a0c7b59e4c8a9e80907e", 1398714770, 0x01770000u },
    { 58464, "0000000001ca9c1281535ffc4c70be9d6e5bee3622004349328303ce281b6104", 1398823076, 0x02008b00u },
    { 60480, "00000000007009d84594d93c3a3384202417a87fcf3f93ca9e9b697c0a285ebe", 1398937697, 0x0200f600u },
    { 62496, "000000000099c1e6aff921a846e5c9cede513076d919c3c588c652f28a0f218a", 1399048497, 0x02015000u },
    { 64512, "00000000001dcd88c7bb0c4e22beab29e1b87925b3dca7032659547c0e405cc2", 1399147556, 0x0200f000u },
    { 66528, "00000000013a3abacea28a5ba3db8acb55f5ba59f81d75624abd80d0701acdd5", 1399235593, 0x02008400u },
    { 68544, "000000000164c03c365b254d5b728b677604802132d917b7845ba0dc2b15315e", 1399321097, 0x02008f00u },
    { 70560, "00000000006e1ab60a5c5b755a3063605965dad2a70d3bb114a7e7b8b05a9502", 1399410080, 0x0200cb00u },
    { 72576, "0000000000b028094e1a41963e6b06395daa651738df72c59c89d23a98fa7ade", 1399496886, 0x02013800u },
    { 74592, "0000000000eb8983987b9485050b7e2e06e3e7c1677c8ee19cc4507e72d8848a", 1399568004, 0x01600000u },
    { 76608, "0000000000dd6af67db229d89edb0d45ceecfda2bfda577148c0a5132be4696b", 1399614952, 0x017d0000u },
    { 78624, "0000000002169c8fefe25c91f8c8d2d11c7b5918bb447641b2ae89455574ff72", 1399663010, 0x014b0000u },
    { 80640, "0000000001e7e6feb002fd6db9388579036789861aff96b5e294f7a9a36fcd14", 1399707652, 0x01620000u },
    { 82656, "0000000001dc70ff5cb69f119e63e6dcdf7211804b5c14c28ffd254f6bb77ef3", 1399742267, 0x015c0000u },
    { 84672, "0000000000987f3e7674541514932754f262a3e8d6eaefefbc3af4a9809269d9", 1399778259, 0x01670000u },
    { 86688, "00000000014f0dfcc8fa842503e889894cc4266dde357beaac54e612f64d93ad", 1399830406, 0x0200aa00u },
    { 88704, "0000000000817f23861e3ed1f7b3aebe82ae22cd49155484a41595f40b2fe2b9", 1399934192, 0x0200ef00u },
    { 90720, "0000000000f00acc34243782228f38d9c0ceb12a42dca3ba7dd2c05675656c22", 1400053178, 0x0200e500u },
    { 92736, "0000000000582a8ef7774bc775e76eef2e837afa34ba4129ae2998506656673f", 1400172682, 0x01720000u },
    { 94752, "0000000000046c992238d03341790cce93d3af8465602f9a4ea362b3df4ef221", 1400293522, 0x02008c00u },
    { 96768, "0000000001510b3f805d0eae14277439444bc34505ea354bc22e82756964b825", 1400412229, 0x02009c00u },
    { 98784, "00000000021ec1d8488fbaf8691969c1d32c458f50fcafee9e1e9ad0b80b2150", 1400532960, 0x01740000u },
    { 100800, "0000000001c27d92fa1a3d1912b7caf3b398cfab5aa3d18cd21442bebdfb119a", 1400649214, 0x02008300u },
    { 102816, "0000000001f601ece9ea73ef9d5d82f46d56db464dc80547cb34c43fa484d6ac", 1400776738, 0x02008000u },
    { 104832, "0000000002433a6769e3104a12158a55756e01fa4371aa771f2da7f9638e4446", 1400904012, 0x01670000u },
    { 106848, "0000000001fd1f3a77bf9e524171ce9de9363af2008c12876255712c337b22f1", 1401031328, 0x01680000u },
    { 108864, "00000000004160b657766ef75f16e3280dd470d560ed15dec8ca967734909813", 1401158425, 0x02009300u },
    { 110880, "0000000000f1e31f822e5fa575c5c70dc6d9a1e579e8e37d7a83519c18744c7c", 1401285437, 0x017c0000u },
    { 112896, "0000000001530405ac65bb337b60a77b27a01ad5b98134a133bcd3f4b2bc247f", 1401412579, 0x01700000u },
    { 114912, "000000000130e8682d9cb8f3a1b6520e2c3a493dd9c4d782f04433a7e6e7867b", 1401539422, 0x02009d00u },
    { 116928, "00000000006f808162824ed8f43b83802e7f140ea14348066f4da3a9cf05e46d", 1401666086, 0x0200ff00u },
    { 118944, "0000000001ba7a392d58177afd7a2cf07318b54351ac2bf830756f99710720ca", 1401793762, 0x02008000u },
    { 120960, "0000000001d7db2f318c594eb085ee99470b8617abc132f0f10f4bd65bce0a3d", 1401920577, 0x02008100u },
    { 122976, "00000000007fa97547bdb0bda2601818040499ee91a505f443879fffcbff13b0", 1402047818, 0x01670000u },
    { 124992, "00000000013d811bcdf9e1af937d80ccbd9d5694f3f489ae7079b209b648251b", 1402174913, 0x02009100u },
    { 127008, "00000000007e29a873be8f97457f97b47e0f515b3bf1e3aa598ad545af964d59", 1402302533, 0x015e0000u },
    { 129024, "0000000001b2c243c54ba369856d055370a608008781d4844d6f396ad3de552b", 1402429877, 0x01640000u },
    { 131040, "0000000003261de03df37a7c795ee3eb8ffb5eaced78bc0cc4513ab825fba867", 1402557079, 0x01440000u },
    { 133056, "0000000003006857cb197c3f41960030d80b4fde5ce1826c5ad367e42aadd054", 1402684200, 0x014f0000u },
    { 135072, "000000000181264acbd859ea6f09ac5075bac1c5abff8864adbe2b37a8d2f35a", 1402810839, 0x0200a400u },
    { 137088, "00000000025e53fe788f84d7b5c155b2dcb367029174ba092d6a2cb313966ccc", 1402938416, 0x016a0000u },
    { 139104, "0000000000cb553cc22128aca1eb3a4d9dfd8a8c964cd21315b23149e9af1d71", 1403065446, 0x015d0000u },
    { 141120, "000000000246e60ae5d74939a6da26b28a6c88831ff7421368c96d3e1327372c", 1403192770, 0x01480000u },
    { 143136, "00000000026bc4b1d3ad19e50022469fea0da90ffe1af5f2597105d6f67f92ce", 1403320170, 0x01420000u },
    { 145152, "0000000000a22d1705649229a8956d5bb5398b9779b2d287aef097145a2143a9", 1403447143, 0x01410000u },
    { 147168, "0000000005b1af26791b0174a2bc2142577b7cb535fce9801bd169753a87bc94", 1403574774, 0x01260000u },
    { 149184, "0000000005e9fc2235014f415d42ad32ebed8ced22fd63b20957a3e5d9d9bb1b", 1403701988, 0x01280000u },
    { 151200, "0000000003194c4316b0a5ff88d1e60dbcef5f23b2ba9129ea5b2b37c04ea5dd", 1403828833, 0x012c0000u },
    { 153216, "00000000045d0dee91af5c2874b9337c6d704914a7ddf4fa2fc45852599d5f16", 1403956013, 0x01340000u },
    { 155232, "0000000000fe5649852fa121e09e22aeec21c5ef80afca4bfac78fbcb6795e04", 1404082939, 0x01480000u },
    { 157248, "000000000599637e8cab6926edaaefcca7eeb0ff00738801c2780769a15136b8", 1404210698, 0x011e0000u },
    { 159264, "000000000030f9e8784f63d8d56b07abeff6e59c8bb9b794db6723c31e7830bf", 1404337767, 0x01300000u },
    { 161280, "000000000289f3f995327efc116a60fa60aad5cb4406262cdc4d5caf5339f620", 1404464778, 0x01380000u },
    { 163296, "0000000006a7bf93299effedca181bd91eda82ba6579ba8c1e39607b8628a622", 1404592346, 0x011b0000u },
    { 165312, "0000000001c0f67d992a751574b32007bdf8110c3835f6429a43ecb77bffe750", 1404719367, 0x01270000u },
    { 167328, "00000000051323b3757df98ae6a0fa2c7c52811f84843b61618daea8b243955b", 1404846629, 0x011a0000u },
    { 169344, "00000000014799b5ec2aa44b78d903507326c6fe55ab1f5f8342d1a21b25e809", 1404973315, 0x01270000u },
    { 171360, "0000000009e25fabd5e465a3d96cead2a3cfdfa08b087d3d56de94866032a8f3", 1405101058, 0x01170000u },
    { 173376, "0000000000bd5776a6383992d4cd13ce87e925c298d292f13fb821b0a8b2579b", 1405227944, 0x01260000u },
    { 175392, "0000000000539c0b4680931994b973f9be59024c91cb0be3b2ca1eb1832fd746", 1405355209, 0x011a0000u },
    { 177408, "0000000000be1dbc448f5be16a256b4f6531b876a9c67b6381ffd58bb2d967da", 1405482140, 0x01190000u },
    { 179424, "000000000634739cc3e522f68553f7167e50d6416f47ddf23cb09817eab3a09f", 1405609575, 0x01160000u },
    { 181440, "0000000006c48af0b605029fce970f1e6621b25459998fcb532b6c8cdac0d000", 1405736570, 0x01150000u },
    { 183456, "000000000028c62e077f3adc18a47cdaff5fb25ad1fe3ab62333484beebc27ff", 1405863731, 0x011a0000u },
    { 185472, "0000000009458120d711bef78c05682e978f5265193c6a8bea20b56c832f76e5", 1405991113, 0x01160000u },
    { 187488, "00000000006caea9a91e002e87d7c6797072a2013f49d62bcaf980766f3f6cdf", 1406117961, 0x01130000u },
    { 189504, "0000000001275d7fc1817e2cd5c0c029b100c683c9ffb43eb8af9a1c3eaeda58", 1406244876, 0x011e0000u },
    { 191520, "0000000001cf5f0120f5ad420eef9253679fa6aeea6ae4d81132a7122e6532ec", 1406372164, 0x01170000u },
    { 193536, "00000000036521cc1c36eb112e157a6f2556902303a882be06be374381d8b5bc", 1406499142, 0x01110000u },
    { 195552, "0000000000693a72d19da7ab28be93c95cf832e3be9dc5e43ecfa78f712af537", 1406626310, 0x01120000u },
    { 197568, "000000000963f448fb19060670b7b2ffa043f2e2e8c46e0be664bdb69deada40", 1406753579, 0x01100000u },
    { 199584, "0000000003054ee610ac494c6fdd39b1696933b5e271b16af8b6c4d451d78273", 1406879981, 0x01270000u },
    { 201600, "000000000022f0e174efd1284206168fd32f607525d95dc44b4db15b6860b5dc", 1407007210, 0x011c0000u },
    { 203616, "000000000275820cae243a2b1f8abd0471d206e112f0cecb08ccefae2338bef2", 1407134796, 0x01150000u },
    { 205632, "0000000004ee49e6e85b011db83bf3f2f757c8425a93009b5e14caabd00510b6", 1407261813, 0x011a0000u },
    { 207648, "000000000344f6b90d306d6f2aa7c19bd26068cc9b224974cd35c028c89e0689", 1407388857, 0x01230000u },
    { 209664, "00000000046f2c13b753bc93d9e7b1975fdcd696c6964190995820af2fd3ef57", 1407516359, 0x01160000u },
    { 211680, "000000000263f46e8aef1d6d6786f099eb816eb79863590d86eb051a5705dad2", 1407643655, 0x011b0000u },
    { 213696, "0000000007bf084d19880aa61252ec90af02cc6e92c4cf7791c1df721b32b493", 1407770559, 0x01160000u },
    { 215712, "00000000065aad61cf20882b290c695112231bb812d5107bbe4bde3cd6039d4d", 1407897867, 0x011b0000u },
    { 217728, "000000000a0fd0d06b4f4e89cd1bfc476fb8858b8bbe6cdd496bf6d4cf61ca6f", 1408024865, 0x01170000u },
    { 219744, "000000000386ace50455ff268c949fc55ddd33e826e10120610918fd6cca88bc", 1408151956, 0x011b0000u },
    { 221760, "00000000086de4bfc643a826345c2ff7218c5210912eb6c767a9bcc875b71052", 1408279138, 0x011e0000u },
    { 223776, "000000000b8b7486edd9847a787e068da0a4a412ac25b323885f47a49bb5e070", 1408406714, 0x01150000u },
    { 225792, "00000000098dfccab37c182674ac112f974e9c36051affb45824b563efbb25ac", 1408533827, 0x01180000u },
    { 227808, "0000000006d2f7aa488ef684b7850a1ce9bd357f176f7880b36604665cb9461f", 1408661071, 0x01130000u },
    { 229824, "00000000036a89b318dbde09155fde430e14b74484f7726096ac3bd10a3b7bd3", 1408788121, 0x01130000u },
    { 231840, "000000000e1ab9dcc9381546e6357bd412691d70f50bd14224cb6855b5d59ade", 1408915244, 0x01110000u },
    { 233856, "0000000002a544766b25b37ba5a17b04d3893a03b5e5777878f4423d2acb8341", 1409042728, 0x010c0000u },
    { 235872, "0000000006f566e6d40fcb4d0f3e232e1fed8a99a218c48c508f4fbd44e75d90", 1409169543, 0x01100000u },
    { 237888, "0000000003a2af7bc92477d235ac5617239d3e04b7e442dc8e202f8feca34730", 1409296681, 0x01120000u },
    { 239904, "0000000004d2808a205cdea73f80a08ade71347100cc0577739c05346995240c", 1409424083, 0x010e0000u },
    { 241920, "000000000af1634708c3f101dd3bec13443f372750e7f46f1aa163db3a255bd8", 1409551093, 0x010d0000u },
    { 243936, "0000000002507b2ada397a55c1fbbfed2e362b15a4cbf4f14ab88ce8250b13ae", 1409678359, 0x01100000u },
    { 245952, "000000000bdcf468cf635781e1f6fc90f113d49c2f3817b83aa2cf899c6c272f", 1409805918, 0x010c0000u },
    { 247968, "000000000e669298cdfedaa1aa022653b33c789999beba213ccfba4ae6848f81", 1409933206, 0x010b0000u },
    { 249984, "0000000007770c66bf0de7ea09bf7b6622980c572d8d799ac4032f7fef4b18dc", 1410060420, 0x010b0000u },
    { 252000, "0000000004f7d25c3737f98b6c33ae26709174c6bb53853826e7218a76793320", 1410187655, 0x010a0000u },
    { 254016, "000000001170873f63a9e922ed9b9fa8c467220b56aa73893f02a6e382fae503", 1410314428, 0x010c0000u },
    { 256032, "0000000008a5b26a8922969ebc5bc5d59c334794f1b7e50f13731e53bf69093c", 1410441938, 0x010f0000u },
    { 258048, "0000000008cb73b1d900f4e5798b9c1c50ff4e6ad03cae26a6d10a299c01637c", 1410568410, 0x01140000u },
    { 260064, "000000000340663443ad794a296f7a82d3d240e934509ddc03ab8b1ec8d0c118", 1410695486, 0x011b0000u },
    { 262080, "000000000613df294c332a10e9db8f1e563ee6aa930edc984557a7cbed862f57", 1410822787, 0x01130000u },
    { 264096, "000000000957c28eb557ed7f248ebfde2984d60fefcf240469ee36ff7dbf5098", 1410949714, 0x01190000u },
    { 266112, "000000000124629a271ac1927d26a38db33ec0b4da2046de8a036bd0933aaebc", 1411076631, 0x011e0000u },
    { 268128, "0000000008a4f777364a78c1e869c02f279e9492718bad31939db1f812b5141a", 1411204261, 0x01170000u },
    { 270144, "0000000003f31cf0ff1b0a93935f38324827ef63e97ead8bbaf8ae19f6e6a626", 1411331371, 0x011f0000u },
    { 272160, "000000000240fe561f88c7d0bf099c8dcb869b693075efb59325769791fc48db", 1411458757, 0x011d0000u },
    { 274176, "00000000021737f3f540c379f5e857eb54432fc83c9f2ead6789836ea920be0a", 1411586116, 0x01170000u },
    { 276192, "00000000049303a35ba58e8503e644a5d52d001d08a18f3bdb7466c1024ee8c5", 1411713520, 0x011b0000u },
    { 278208, "00000000040aa71dcdd7985277499578bdc27e27cf2fdc12e9d08b444af7550a", 1411840607, 0x01190000u },
    { 280224, "000000000aea12e575e5494330ee1db0eaef78cef1aac92d649d36bde50add55", 1411967766, 0x01140000u },
    { 282240, "00000000014c86f78b129ea3f6fde31e3be60e08976eecff1c37d3b37fcc667a", 1412095585, 0x010a0000u },
    { 284256, "00000000059ceb7b8d25ebdf452a85915aad973a8c069a3db596ef342a1904d3", 1412222537, 0x010c0000u },
    { 286272, "000000000082b36315166573afd131fb24d839dc035fa03753c36fbda733fa5f", 1412349635, 0x010c0000u },
    { 288288, "0000000004783f197fec2a9f844e5e0c70f1282c56b26cb5af1e3fad8edc48a9", 1412477049, 0x01070000u },
    { 290304, "0000000009983cd02aa043b0f68b88e56dfab96ae0f099257f092b30b106887e", 1412603754, 0x010f0000u },
    { 292320, "0000000006e0622bd7717e18833ae6f9a6ec8e387492217355da0c8f62eca4f7", 1412730771, 0x01110000u },
    { 294336, "0000000009a2392d64365c61896e7c1438c9a800eb46478c162b99d96ee2db56", 1412858027, 0x010e0000u },
    { 296352, "00000000096fec0deaff384cc1f78e9ac056cd24d352eb3dba3c97ac22a3016f", 1412985012, 0x010f0000u },
    { 298368, "00000000095e18ac30907a3af9fcb2152a277a294f1e70a42f29e76aa80011ed", 1413112401, 0x010a0000u },
    { 300384, "000000000f889db3ba8fbb4b7fccf7620af5acf9212d684a3a8bd9098494395f", 1413239612, 0x010e0000u },
    { 302400, "0000000008017e15beaf106ad3153fc087f049d3f770e3da7c38d31aca777dcd", 1413367184, 0x010b0000u },
    { 304416, "0000000003f9c6578fbdf3b1084a739afb8a5810e08cb7087ca91d43a7b0cc64", 1413494500, 0x010a0000u },
    { 306432, "000000000a6c561a1e5b279add6144eca39a5f111ebb809bb59ee98dbbc86d5b", 1413620951, 0x01110000u },
    { 308448, "0000000007380bf2ed157feac1e53df5dca89e172d292e7840d4f1dee1e9d6df", 1413748860, 0x010b0000u },
    { 310464, "000000000a36a58306b5405431ca4fa4abec93cbfd7ebe036bbeefbfafde6768", 1413875960, 0x01090000u },
    { 312480, "00000000033f23beca5f32a9df96e608f1f30148d9481ec23ec55ac8559b4919", 1414002703, 0x010c0000u },
    { 314496, "000000000aab96acbf337249e78aec2ac0117936c6999c30f0e5a7e54475ff15", 1414129869, 0x010c0000u },
    { 316512, "000000000fa6e70cf8ad5d23ef5a046af3d5f9f4113fa62913f5a0ccf1c980b5", 1414257299, 0x010a0000u },
    { 318528, "000000000de48ea8f14f489cbe96f8125ca88cfd7403e4d5ade1ee0daffffdcf", 1414384520, 0x010a0000u },
    { 320544, "000000000a4cbb66e4a77ec016523104db095ea5b325a8278c77c35ee190e28e", 1414511648, 0x010a0000u },
    { 322560, "0000000007fbe746252aee768f8e4d858fc34818f46a696385dbdfaea784df45", 1414639037, 0x010a0000u },
    { 324576, "000000000b8abea9316ad80f0badf4c325bffcbdb239392d2e2ae72398553bcd", 1414766168, 0x010a0000u },
    { 326592, "0000000007d46707028d83231143399b72b1724a52a4d328e02cbc3738870078", 1414893924, 0x01060000u },
    { 328608, "000000000f8ef14402a33711f2180dd55ff381baa7142f060ff9ac0bfa0785aa", 1415021019, 0x010b0000u },
    { 330624, "000000001f75b7c27b7d406307add19c6726859a080ec166e08be7cd349b8c4b", 1415148524, 0x01070000u },
    { 332640, "0000000006d0179896d0a743a93fd063d85ed013348fc23eadd5392fa511284e", 1415275759, 0x010b0000u },
    { 334656, "0000000011aadab6e8bd99c2f73e1585e6a0ec7334f4b3839d925b33c838c844", 1415403369, 0x01090000u },
    { 336672, "000000001498ed9ae361d32e7bc8f11e661f83beaa2b629ace38fef1e6548d9e", 1415530197, 0x01080000u },
    { 338688, "0000000005f3cce53e487a9a499483c8e8d6633bfa7e5b10d4c6d802e50cf354", 1415657500, 0x010c0000u },
    { 340704, "00000000193808c064649c29e8576bf1012a2a586f64183048067e27f648de99", 1415785028, 0x01080000u },
    { 342720, "00000000104c70677dc6249505b2e66c1d80ce2289e7f76015b61eaf30226975", 1415913369, 0x01070000u },
    { 344736, "000000001439f33d83f1f03a3d7535590dd34d5b3d00ac69991b19547ae3cb5e", 1416041193, 0x01080000u },
    { 346752, "0000000015379f47912519217724ea8c8348deb79e5b7990d8c847096518bc65", 1416169574, 0x010a0000u },
    { 348768, "000000000f8536eaddf3874691c55fbb8718da40fbbbd605c92bd395cac5d4be", 1416297686, 0x01060000u },
    { 350784, "0000000003d1fe08a211baba7b815ec2b9cf6dbd6f97d4b09e7e9e05336deb11", 1416425042, 0x01060000u },
    { 352800, "0000000016e4010a958e4346c456471e3120e76dc98e1e09fc2328c5ae37bd65", 1416552378, 0x01070000u },
    { 354816, "0000000006e55ec6e52636027e72ee119c857eb1b118332f5fd2edcb683c1271", 1416680258, 0x01090000u },
    { 356832, "000000000a574c4d31d0916a20ec12d4a6c3f1ac624fd2b517a8c8d1e5ba5991", 1416807472, 0x010a0000u },
    { 358848, "00000000007c4ad0ddc099e3c29d2365d1cb52b8bd52c22d7a4abeda56b2e15e", 1416934610, 0x010d0000u },
    { 360864, "000000001c0e05b23fa149768ecd168518132a4e4e99653074f789191077f843", 1417062410, 0x01040000u },
    { 362880, "0000000000470dcfb6b0296a3990aed7c3f276c0599ca2ae5ced26ceec156cb5", 1417189860, 0x01040000u },
    { 364896, "000000003101fec1e6a329ff3667ab25e109c9aaa406f6bc90fbb7e2f6e6035c", 1417316859, 0x01040000u },
    { 366912, "0000000007e51d2c0680120889c45e8b883ad3c2ea66ce12304b25ce3af1e1ef", 1417444085, 0x01040000u },
    { 368928, "0000000016e0c41e0d9fbe1907c41b366c079c03d9a3f6f7dec31f5a02fa3a38", 1417571473, 0x01040000u },
    { 370944, "000000000e05fabaffb61da2f333d39cabc885f894a8ad1ec71cb1c156074ad4", 1417698412, 0x01060000u },
    { 372960, "00000000262c01a4905838bb0d7023f6d444c82fecb9e9f19150d3ef03f0897c", 1417825582, 0x01060000u },
    { 374976, "0000000007107d8e5934cfb976eedc71958ccae875be82a7ad3503b5a460c6e3", 1417952318, 0x010a0000u },
    { 376992, "000000000951928f4c2b98c6f232a7b1080dd235e44598232964198ed0cd7eb2", 1418079378, 0x010b0000u },
    { 379008, "000000000392f04e0bb8ea9c31cd0805ceffea588638354c686f7265fae754bd", 1418206671, 0x01090000u },
    { 381024, "000000000157882dbb43515cb13c9fda7469019d8446548b545ff4a6505bb8e4", 1418334348, 0x01050000u },
    { 383040, "000000001a2896ac832076f1e3778c59aa3676111d0bdef0adf2bf600a9d4a8d", 1418461332, 0x01060000u },
    { 385056, "000000000e2f9a0f37388bcde06f604e71dd03174ee24b9e9a3bc2c227841947", 1418588306, 0x01080000u },
    { 387072, "0000000025d1dd677e722eb3ce6ee087cfbcbb03913a8fc7754eacef784c7acb", 1418715724, 0x01060000u },
    { 389088, "0000000002446300d878296d3e12bb9d3d434d683c5944982e966ac780e393cd", 1418842567, 0x01090000u },
    { 391104, "000000000cf823129aa8d39c744554cea0d3f954915f917bbb6018d721f6f360", 1418969937, 0x01090000u },
    { 393120, "000000000f775b1587c0ebd61e9f78e607da9de9c14b70cd6c92b244b13b888c", 1419097281, 0x01070000u },
    { 395136, "0000000010d3ec1817519f867880938b986bba368b40b367fad4eb5acbb1fdf6", 1419224906, 0x01070000u },
    { 397152, "0000000010fac8a00a288ca3c494e213264a0ec3e639efe0eac6f771f41609d9", 1419352893, 0x01050000u },
    { 399168, "0000000010e5222ab97bb83d905b93f1362e6750bef36fa8986cb3b39905dfe7", 1419479355, 0x01060000u },
    { 401184, "00000000123f7badd09a6e91627f8d008928faa460f60c111ae0e0b888a930fd", 1419606587, 0x01090000u },
    { 403200, "00000000009af4b38d179c51b28002bc9e448a426f17aa737cf615445f7d7247", 1419734182, 0x01060000u },
    { 405216, "000000002294b8ad89fedc5cd3ac90435bf08f4bfc871c3ead0c74508f9be170", 1419860880, 0x01060000u },
    { 407232, "00000000175ec3b3208aca2044e94c5e83976f9b3b04ffb75b425cf4b88c3a80", 1419988732, 0x01040000u },
    { 409248, "000000002690cc19dfcf50e0e7ad70c8137c44a677ef6a5caa4d6f19c426001b", 1420115420, 0x01060000u },
    { 411264, "000000001479765a4af33db02a430bb0fcce6405b8696ab1a94055a430e8f181", 1420243233, 0x01050000u },
    { 413280, "00000000170cdf113d79234433fe0f04060e6fe79d020b6bcf8dd503567a95ce", 1420369575, 0x01080000u },
    { 415296, "000000000e32723cb8e14ba982efda0ebd58fb3394da70e2a3e50af0caed3d3e", 1420497465, 0x01040000u },
    { 417312, "00000000083933c0fe9b0de804f2d9ab2b574110be4c52cbc34793697b42b23a", 1420624162, 0x01060000u },
    { 419328, "0000000013e2575fe89c726de6c30e33c469c8302a9e537d3a872cf6513b8e32", 1420751230, 0x010a0000u },
    { 421344, "0000000007342d8fe7426892c46dfc2c77d5650cbdafdc3f259ca362131b1072", 1420878374, 0x01080000u },
    { 423360, "0000000033e29dde910e35e2e30569baadaeb1e5ae984a4dae028c14ed8635b2", 1421006143, 0x01040000u },
    { 425376, "00000000243f5455673d06f9f913b5ac3a655bd4fa2302b5c84de2645e50631a", 1421133057, 0x01060000u },
    { 427392, "000000000bf179f0b4a3964a6cd40929ab7361be45ac5fbd8da0e294b89fa597", 1421260540, 0x01050000u },
    { 429408, "000000002511a6b41d2bdd3f329f37e9007303a87fd5df5132822ce1153eaef4", 1421387419, 0x01060000u },
    { 431424, "000000000e8f6f7fa54bf1310b8b668146fd8b0904882cc6078824452046910e", 1421514905, 0x01050000u },
    { 433440, "000000001b3e865f9e54d975422eb9b0da3e920cd9a49ff873ad9b6e499acdd2", 1421642341, 0x01050000u },
    { 435456, "0000000016bff18744e15ab52ba8f8c963044ef1a8a421c005ce6bd2db59ec62", 1421769161, 0x01080000u },
    { 437472, "0000000028e810dde762f40c0785a8cbb3c19ea247d3c966001286a0608affab", 1421897338, 0x01050000u },
    { 439488, "00000000220ab3134067f2a0c388f701642332d75a72f855f50f74aab2b5ff19", 1422024799, 0x01070000u },
    { 441504, "0000000013eed8f012b8f4988148dee0372d1ed54aae9d6cd5bbe21bbdb8dd8e", 1422152874, 0x01060000u },
    { 443520, "000000001dc9f889828d651ea375e997e574b2fc39d4d4011395d39acc71f27c", 1422280422, 0x01070000u },
    { 445536, "0000000019aa36c55484d52291271319e5717c94b233610c8819168e88b9d66d", 1422407946, 0x01090000u },
    { 447552, "000000002ff22003584bd18843e298dcd46c4e09538890169f41a696eadb847c", 1422535752, 0x01050000u },
    { 449568, "00000000109213cd372a59edf09ebd020c3d21015d850ea1ab93c6ce80342075", 1422663010, 0x01090000u },
    { 451584, "000000002ec7b1b8446eab2bf1ea7be8d9d6938374a2d9fde966b2ce6fa37095", 1422791957, 0x01050000u },
    { 453600, "000000001e6dcceb7f47f58a7d785d85b6fc5469ea291185f141b85ea05531ba", 1422919349, 0x01070000u },
    { 455616, "0000000004723d80d45d7ee04ae458c14c381a3cdf1c20c928ac1b365933aab4", 1423046857, 0x01080000u },
    { 457632, "00000000086d36746199de8929c9d6092764c8c59309b3d68317534f82ae77e4", 1423173868, 0x01070000u },
    { 459648, "000000000f8d6a571d74c788cd42459e2569f2d98f1e64d1b109fff45901f844", 1423300892, 0x01070000u },
    { 461664, "00000000038331f12d56c0f30b5777a5aa1621234ea65f59a5171e0bf3b55133", 1423427939, 0x01080000u },
    { 463680, "00000000138ae5e0659af0016e25c63ff87ac48416244ec618f5e4cc2d83136d", 1423554981, 0x01080000u },
    { 465696, "00000000143cc1dde3f699be3f847f7cf972ef37c20dc3e96b9315693927616f", 1423682517, 0x01070000u },
    { 467712, "000000002b4652102a4e4eb5b874950bf186e008d7307efc5f1e0f85002c146d", 1423809594, 0x01050000u },
    { 469728, "000000000f85e45235d8545f7df3c5bb57609837243e76180cae1397277fd074", 1423936871, 0x01060000u },
    { 471744, "000000000b87d77b9c45d5c25aa7ba947dff1cbc5c2dc600dcca9107adcc2b54", 1424064390, 0x01080000u },
    { 473760, "0000000009b3a015eb2060da32b6df58845ec90ae32a59d5d45e4a0f7e1ced99", 1424191144, 0x010b0000u },
    { 475776, "000000000e1ef28577c2621165edb5968e07f198d3f0cd5de25fabf723c86649", 1424318118, 0x01110000u },
    { 477792, "00000000179d05a12e576e6961bd94b38fd594231a880a85fe7b25f6b716c40f", 1424445401, 0x010a0000u },
    { 479808, "0000000003275633306e4482febfe347fc31e5090363b95539f15d5378842252", 1424572165, 0x011b0000u },
    { 481824, "0000000019972e461d5c8d1c60108bcb299d274ade2be8194e0f0da6b16c7ead", 1424700607, 0x01070000u },
    { 483840, "0000000008c48153501b3c56cee109a66e14da3448ad424b5da1475a3e814cc5", 1424826962, 0x010f0000u },
    { 485856, "0000000009f4394196f3c43d472a0fbf3625b51a7a8aba5f2e64206814abe19d", 1424955494, 0x01070000u },
};

static const char *dns_seeds[] = {
    "ip1.groestlcoin.org",
    "ip2.groestlcoin.org"
};

#endif

@interface BRPeerManager ()

@property (nonatomic, strong) NSMutableOrderedSet *peers;
@property (nonatomic, strong) NSMutableSet *connectedPeers, *misbehavinPeers;
@property (nonatomic, strong) BRPeer *downloadPeer;
@property (nonatomic, assign) uint32_t tweak, syncStartHeight, filterUpdateHeight;
@property (nonatomic, strong) BRBloomFilter *bloomFilter;
@property (nonatomic, assign) double fpRate;
@property (nonatomic, assign) NSUInteger taskId, connectFailures, misbehavinCount;
@property (nonatomic, assign) NSTimeInterval earliestKeyTime, lastRelayTime;
@property (nonatomic, strong) NSMutableDictionary *blocks, *orphans, *checkpoints, *txRelays;
@property (nonatomic, strong) NSMutableDictionary *publishedTx, *publishedCallback;
@property (nonatomic, strong) BRMerkleBlock *lastBlock, *lastOrphan;
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) id backgroundObserver, seedObserver;

@end

@implementation BRPeerManager

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    self.earliestKeyTime = [[BRWalletManager sharedInstance] seedCreationTime];
    self.connectedPeers = [NSMutableSet set];
    self.misbehavinPeers = [NSMutableSet set];
    self.tweak = arc4random();
    self.taskId = UIBackgroundTaskInvalid;
    self.q = dispatch_queue_create("peermanager", NULL);
    self.orphans = [NSMutableDictionary dictionary];
    self.txRelays = [NSMutableDictionary dictionary];
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];

    dispatch_async(self.q, ^{
        for (BRTransaction *tx in [[[BRWalletManager sharedInstance] wallet] recentTransactions]) {
            if (tx.blockHeight != TX_UNCONFIRMED) break;
            self.publishedTx[tx.txHash] = tx; // add unconfirmed tx to mempool
        }
    });

    self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self savePeers];
            [self saveBlocks];
            [BRMerkleBlockEntity saveContext];

            if (self.taskId == UIBackgroundTaskInvalid) {
                self.misbehavinCount = 0;
                [self.connectedPeers makeObjectsPerformSelector:@selector(disconnect)];
            }
        }];

    self.seedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletManagerSeedChangedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.earliestKeyTime = [[BRWalletManager sharedInstance] seedCreationTime];
            self.syncStartHeight = 0;
            [self.txRelays removeAllObjects];
            [self.publishedTx removeAllObjects];
            [self.publishedCallback removeAllObjects];
            [BRMerkleBlockEntity deleteObjects:[BRMerkleBlockEntity allObjects]];
            [BRMerkleBlockEntity saveContext];
            _blocks = nil;
            _bloomFilter = nil;
            _lastBlock = nil;
            [self.connectedPeers makeObjectsPerformSelector:@selector(disconnect)];
        }];

    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.seedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.seedObserver];
}

- (NSMutableOrderedSet *)peers
{
    if (_peers.count >= PEER_MAX_CONNECTIONS) return _peers;

    if (![NSThread isMainThread]) { //this should never be called on the main thread
        @synchronized(self) {
            if (_peers.count >= PEER_MAX_CONNECTIONS) return _peers;
            _peers = [NSMutableOrderedSet orderedSet];
            
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            
            [[BRPeerEntity context] performBlockAndWait:^{
                for (BRPeerEntity *e in [BRPeerEntity allObjects]) {
                    if (e.misbehavin == 0) [_peers addObject:[e peer]];
                    else [self.misbehavinPeers addObject:[e peer]];
                }
            }];
            
            [self sortPeers];
            
            if (_peers.count < PEER_MAX_CONNECTIONS ||
                [(BRPeer *)_peers[PEER_MAX_CONNECTIONS - 1] timestamp] + 3*24*60*60 < now) {
                NSMutableArray *peers = [NSMutableArray array];
                
                for (size_t i = 0; i < sizeof(dns_seeds)/sizeof(*dns_seeds); i++) [peers addObject:[NSMutableArray array]];
                
                dispatch_apply(peers.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
                    NSString *servname = [@(DASH_STANDARD_PORT) stringValue];
                    struct addrinfo hints = { 0, AF_UNSPEC, SOCK_STREAM, 0, 0, 0, NULL, NULL }, *servinfo, *p;
                    
                    
                    NSLog(@"DNS lookup %s", dns_seeds[i]);
                    if (getaddrinfo(dns_seeds[i], [servname UTF8String], &hints, &servinfo) == 0) {
                        for (p = servinfo; p != NULL; p = p->ai_next) {
                            if (p->ai_addr->sa_family != AF_INET) continue;
                            
                            uint32_t addr = CFSwapInt32BigToHost(((struct sockaddr_in *)p->ai_addr)->sin_addr.s_addr);
                            uint16_t port = CFSwapInt16BigToHost(((struct sockaddr_in *)p->ai_addr)->sin_port);
                            [peers[i] addObject:[[BRPeer alloc] initWithAddress:addr port:port
                                                                      timestamp:now - (3*24*60*60 + arc4random_uniform(4*24*60*60)) services:SERVICES_NODE_NETWORK]];
                        }
                        
                        freeaddrinfo(servinfo);
                    }
                });
                
                for (NSArray *a in peers) [_peers addObjectsFromArray:a];
                
                
#if DASH_TESTNET
                [self sortPeers];
                return _peers;
#endif
                if (_peers.count < PEER_MAX_CONNECTIONS) {
                    //                 if DNS peer discovery fails, fall back on a hard coded list of peers (masternode list from dash core client)
                    for (NSNumber *address in [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                                                                                pathForResource:FIXED_PEERS ofType:@"plist"]]) {
                        // give hard coded peers a timestamp between 7 and 14 days ago
                        [_peers addObject:[[BRPeer alloc] initWithAddress:address.unsignedIntValue
                                                                     port:DASH_STANDARD_PORT timestamp:now - (WEEK_TIME_INTERVAL + arc4random_uniform(WEEK_TIME_INTERVAL))
                                                                 services:SERVICES_NODE_NETWORK]];
                    }
                }
                
                [self sortPeers];
            }
        }
        
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [self peers];
        });
    }
    
    return _peers;
    
}

- (NSMutableDictionary *)blocks
{
    if (_blocks.count > 0) return _blocks;

    [[BRMerkleBlockEntity context] performBlockAndWait:^{
        if (_blocks.count > 0) return;
        _blocks = [NSMutableDictionary dictionary];
        self.checkpoints = [NSMutableDictionary dictionary];

        for (int i = 0; i < CHECKPOINT_COUNT; i++) { // add checkpoints to the block collection
            NSData *hash = [NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse;

            _blocks[hash] = [[BRMerkleBlock alloc] initWithBlockHash:hash version:1 prevBlock:nil merkleRoot:nil
                             timestamp:checkpoint_array[i].timestamp target:checkpoint_array[i].target nonce:0
                             totalTransactions:0 hashes:nil flags:nil height:checkpoint_array[i].height];
            self.checkpoints[@(checkpoint_array[i].height)] = hash;
        }

        for (BRMerkleBlockEntity *e in [BRMerkleBlockEntity allObjects]) {
            BRMerkleBlock *b = e.merkleBlock;

            _blocks[e.blockHash] = b;
            
            // track moving average transactions per block using a 1% low pass filter
            if (b.totalTransactions > 0) _averageTxPerBlock = _averageTxPerBlock*0.99 + b.totalTransactions*0.01;
        };
        
        [[BRWalletManager sharedInstance] setAverageBlockSize:self.averageTxPerBlock*TX_AVERAGE_SIZE];
    }];

    return _blocks;
}

// this is used as part of a getblocks or getheaders request
- (NSArray *)blockLocatorArray
{
    // append 10 most recent block hashes, decending, then continue appending, doubling the step back each time,
    // finishing with the genesis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -15, -23, -39, -71, -135, ..., 0)
    NSMutableArray *locators = [NSMutableArray array];
    int32_t step = 1, start = 0;
    BRMerkleBlock *b = self.lastBlock;

    while (b && b.height > 0) {
        [locators addObject:b.blockHash];
        if (++start >= 10) step *= 2;

        for (int32_t i = 0; b && i < step; i++) {
            b = self.blocks[b.prevBlock];
        }
    }

    [locators addObject:GENESIS_BLOCK_HASH];
    return locators;
}

- (BRMerkleBlock *)lastBlock
{
    if (_lastBlock) return _lastBlock;

    NSFetchRequest *req = [BRMerkleBlockEntity fetchRequest];

    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:NO]];
    req.predicate = [NSPredicate predicateWithFormat:@"height >= 0 && height != %d", BLOCK_UNKNOWN_HEIGHT];
    req.fetchLimit = 1;
    _lastBlock = [[BRMerkleBlockEntity fetchObjects:req].lastObject merkleBlock];

    // if we don't have any blocks yet, use the latest checkpoint that's at least a week older than earliestKeyTime
    for (int i = CHECKPOINT_COUNT - 1; ! _lastBlock && i >= 0; i--) {
        if (i == 0 || checkpoint_array[i].timestamp + WEEK_TIME_INTERVAL < self.earliestKeyTime + NSTimeIntervalSince1970) {
            _lastBlock = [[BRMerkleBlock alloc]
                          initWithBlockHash:[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse
                          version:1 prevBlock:nil merkleRoot:nil timestamp:checkpoint_array[i].timestamp
                          target:checkpoint_array[i].target nonce:0 totalTransactions:0 hashes:nil flags:nil
                          height:checkpoint_array[i].height];
        }
    }

    return _lastBlock;
}

- (uint32_t)lastBlockHeight
{
    return self.lastBlock.height;
}

// last block height reported by current download peer
- (uint32_t)estimatedBlockHeight
{
    return (self.downloadPeer.lastblock > self.lastBlockHeight) ? self.downloadPeer.lastblock : self.lastBlockHeight;
}

- (double)syncProgress
{
    if (! self.downloadPeer) return (self.syncStartHeight == self.lastBlockHeight) ? 0.05 : 0.0;
    if (self.lastBlockHeight >= self.downloadPeer.lastblock) return 1.0;
    return 0.1 + 0.9*(self.lastBlockHeight - self.syncStartHeight)/(self.downloadPeer.lastblock - self.syncStartHeight);
}

// number of connected peers
- (NSUInteger)peerCount
{
    NSUInteger count = 0;

    for (BRPeer *peer in self.connectedPeers) {
        if (peer.status == BRPeerStatusConnected) count++;
    }

    return count;
}

- (BRBloomFilter *)bloomFilter
{
    if (_bloomFilter) return _bloomFilter;

    BRWalletManager *m = [BRWalletManager sharedInstance];
    
    // every time a new wallet address is added, the bloom filter has to be rebuilt, and each address is only used for
    // one transaction, so here we generate some spare addresses to avoid rebuilding the filter each time a wallet
    // transaction is encountered during the blockchain download
    [m.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL + 100 internal:NO];
    [m.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL + 100 internal:YES];

    [self.orphans removeAllObjects]; // clear out orphans that may have been received on an old filter
    self.lastOrphan = nil;
    self.filterUpdateHeight = self.lastBlockHeight;
    self.fpRate = BLOOM_DEFAULT_FALSEPOSITIVE_RATE;
    if (self.lastBlockHeight + 500 < self.estimatedBlockHeight) self.fpRate = BLOOM_REDUCED_FALSEPOSITIVE_RATE;

    NSUInteger elemCount = m.wallet.addresses.count + m.wallet.unspentOutputs.count;
    BRBloomFilter *filter = [[BRBloomFilter alloc] initWithFalsePositiveRate:self.fpRate
                             forElementCount:elemCount + 100 tweak:self.tweak flags:BLOOM_UPDATE_ALL];

    for (NSString *address in m.wallet.addresses) { // add addresses to watch for any tx receiveing money to the wallet
        NSData *hash = address.addressToHash160;

        if (hash && ! [filter containsData:hash]) [filter insertData:hash];
    }

    for (NSData *utxo in m.wallet.unspentOutputs) { // add unspent outputs to watch for tx sending money from the wallet
        if (! [filter containsData:utxo]) [filter insertData:utxo];
    }

    _bloomFilter = filter;
    return _bloomFilter;
}

- (void)connect
{
    if ([[BRWalletManager sharedInstance] noWallet]) return; // check to make sure the wallet has been created
    if (self.connectFailures >= MAX_CONNECT_FAILURES) self.connectFailures = 0; // this attempt is a manual retry
    
    if (self.syncProgress < 1.0) {
        if (self.syncStartHeight == 0) self.syncStartHeight = self.lastBlockHeight;

        if (self.taskId == UIBackgroundTaskInvalid) { // start a background task for the chain sync
            self.taskId =
                [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                    dispatch_async(self.q, ^{
                        [self saveBlocks];
                        [BRMerkleBlockEntity saveContext];
                    });

                    [self syncStopped];
                }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerSyncStartedNotification object:nil];
        });
    }

    dispatch_async(self.q, ^{
        [self.connectedPeers minusSet:[self.connectedPeers objectsPassingTest:^BOOL(id obj, BOOL *stop) {
            return ([obj status] == BRPeerStatusDisconnected) ? YES : NO;
        }]];

        if (self.connectedPeers.count >= PEER_MAX_CONNECTIONS) return; //already connected to PEER_MAX_CONNECTIONS peers

        NSMutableOrderedSet *peers = [NSMutableOrderedSet orderedSetWithOrderedSet:self.peers];

        if (peers.count > 100) [peers removeObjectsInRange:NSMakeRange(100, peers.count - 100)];

        while (peers.count > 0 && self.connectedPeers.count < PEER_MAX_CONNECTIONS) {
            // pick a random peer biased towards peers with more recent timestamps
            BRPeer *p = peers[(NSUInteger)(pow(arc4random_uniform((uint32_t)peers.count), 2)/peers.count)];

            if (p && ! [self.connectedPeers containsObject:p]) {
                [p setDelegate:self queue:self.q];
                p.earliestKeyTime = self.earliestKeyTime;
                [self.connectedPeers addObject:p];
                [p connect];
            }

            [peers removeObject:p];
        }

        [self bloomFilter]; // initialize wallet and bloomFilter while connecting

        if (self.connectedPeers.count == 0) {
            [self syncStopped];

            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"DashWallet" code:1
                                  userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"no peers found", nil)}];

                [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerSyncFailedNotification
                 object:nil userInfo:@{@"error":error}];
            });
        }
    });
}

// rescans blocks and transactions after earliestKeyTime, a new random download peer is also selected due to the
// possibility that a malicious node might lie by omitting transactions that match the bloom filter
- (void)rescan
{
    if (! self.connected) return;

    dispatch_async(self.q, ^{
        _lastBlock = nil;

        // start the chain download from the most recent checkpoint that's at least a week older than earliestKeyTime
        for (int i = CHECKPOINT_COUNT - 1; ! _lastBlock && i >= 0; i--) {
            if (i == 0 || checkpoint_array[i].timestamp + WEEK_TIME_INTERVAL < self.earliestKeyTime + NSTimeIntervalSince1970) {
                _lastBlock = self.blocks[[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse];
            }
        }

        if (self.downloadPeer) { // disconnect the current download peer so a new random one will be selected
            [self.peers removeObject:self.downloadPeer];
            [self.downloadPeer disconnect];
        }

        self.syncStartHeight = self.lastBlockHeight;
        [self connect];
    });
}

- (void)publishTransaction:(BRTransaction *)transaction completion:(void (^)(NSError *error))completion
{
    if (! [transaction isSigned]) {
        if (completion) {
            completion([NSError errorWithDomain:@"DashWallet" code:401 userInfo:@{NSLocalizedDescriptionKey:
                        NSLocalizedString(@"dash transaction not signed", nil)}]);
        }
        
        return;
    }
    else if (! self.connected && self.connectFailures >= MAX_CONNECT_FAILURES) {
        if (completion) {
            completion([NSError errorWithDomain:@"DashWallet" code:-1009 userInfo:@{NSLocalizedDescriptionKey:
                        NSLocalizedString(@"not connected to the dash network", nil)}]);
        }
        
        return;
    }

    self.publishedTx[transaction.txHash] = transaction;
    if (completion) self.publishedCallback[transaction.txHash] = completion;

    NSMutableSet *peers = [NSMutableSet setWithSet:self.connectedPeers];
    NSArray *txHashes = self.publishedTx.allKeys;

    // instead of publishing to all peers, leave out the download peer to see if the tx propogates and gets relayed back
    // TODO: XXX connect to a random peer with an empty or fake bloom filter just for publishing
    if (self.peerCount > 1) [peers removeObject:self.downloadPeer];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self performSelector:@selector(txTimeout:) withObject:transaction.txHash afterDelay:PROTOCOL_TIMEOUT];

        for (BRPeer *p in peers) {
            [p sendInvMessageWithTxHashes:txHashes];
            [p sendPingMessageWithPongHandler:^(BOOL success) {
                //TODO: XXXX have peer:requestedTransaction: send getdata, and only send getdata here if the tx wasn't
                // requested, then ping again, and if pong comes back before the tx, we know the tx was refused
                if (success) [p sendGetdataMessageWithTxHashes:txHashes andBlockHashes:nil];
            }];
        }
    });
}

// number of connected peers that have relayed the transaction
- (NSUInteger)relayCountForTransaction:(NSData *)txHash
{
    return [self.txRelays[txHash] count];
}

// seconds since reference date, 00:00:00 01/01/01 GMT
// NOTE: this is only accurate for the last two weeks worth of blocks, other timestamps are estimated from checkpoints
- (NSTimeInterval)timestampForBlockHeight:(uint32_t)blockHeight
{
    if (blockHeight == TX_UNCONFIRMED) return (self.lastBlock.timestamp - NSTimeIntervalSince1970) + 10*60; //next block

    if (blockHeight >= self.lastBlockHeight) { // future block, assume 10 minutes per block after last block
        return (self.lastBlock.timestamp - NSTimeIntervalSince1970) + (blockHeight - self.lastBlockHeight)*10*60;
    }

    if (_blocks.count > 0) {
        if (blockHeight >= self.lastBlockHeight /*- BLOCK_DIFFICULTY_INTERVAL*/*2) { // recent block we have the header for
            BRMerkleBlock *block = self.lastBlock;

            while (block && block.height > blockHeight) block = self.blocks[block.prevBlock];
            if (block) return block.timestamp - NSTimeIntervalSince1970;
        }
    }
    else [[BRMerkleBlockEntity context] performBlock:^{ [self blocks]; }];

    uint32_t h = self.lastBlockHeight, t = self.lastBlock.timestamp;

    for (int i = CHECKPOINT_COUNT - 1; i >= 0; i--) { // estimate from checkpoints
        if (checkpoint_array[i].height <= blockHeight) {
            t = checkpoint_array[i].timestamp + (t - checkpoint_array[i].timestamp)*
                (blockHeight - checkpoint_array[i].height)/(h - checkpoint_array[i].height);
            return t - NSTimeIntervalSince1970;
        }

        h = checkpoint_array[i].height;
        t = checkpoint_array[i].timestamp;
    }

    return checkpoint_array[0].timestamp - NSTimeIntervalSince1970;
}

- (void)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    [[[BRWalletManager sharedInstance] wallet] setBlockHeight:height andTimestamp:timestamp forTxHashes:txHashes];
    
    if (height != TX_UNCONFIRMED) { // remove confirmed tx from publish list and relay counts
        [self.publishedTx removeObjectsForKeys:txHashes];
        [self.publishedCallback removeObjectsForKeys:txHashes];
        [self.txRelays removeObjectsForKeys:txHashes];
    }
}

- (void)txTimeout:(NSData *)txHash
{
    void (^callback)(NSError *error) = self.publishedCallback[txHash];

    [self.publishedTx removeObjectForKey:txHash];
    [self.publishedCallback removeObjectForKey:txHash];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];

    if (callback) {
        callback([NSError errorWithDomain:@"DashWallet" code:DASH_TIMEOUT_CODE userInfo:@{NSLocalizedDescriptionKey:
                  NSLocalizedString(@"transaction canceled, network timeout", nil)}]);
    }
}

- (void)syncTimeout
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (now - self.lastRelayTime < PROTOCOL_TIMEOUT) { // the download peer relayed something in time, so restart timer
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
        [self performSelector:@selector(syncTimeout) withObject:nil
         afterDelay:PROTOCOL_TIMEOUT - (now - self.lastRelayTime)];
        return;
    }

    dispatch_async(self.q, ^{
        if (! self.downloadPeer) return;
        NSLog(@"%@:%d chain sync timed out", self.downloadPeer.host, self.downloadPeer.port);
        [self.peers removeObject:self.downloadPeer];
        [self.downloadPeer disconnect];
    });
}

- (void)syncStopped
{
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
        [self.connectedPeers makeObjectsPerformSelector:@selector(disconnect)];
        [self.connectedPeers removeAllObjects];
    }

    if (self.taskId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
        self.taskId = UIBackgroundTaskInvalid;
        
        if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground) {
            NSArray *txHashes = self.publishedTx.allKeys;

            for (BRPeer *p in self.connectedPeers) { // after syncing, load filters and get mempools from other peers
                if (p != self.downloadPeer) [p sendFilterloadMessage:self.bloomFilter.data];
                [p sendInvMessageWithTxHashes:txHashes]; // publish unconfirmed tx
                [p sendMempoolMessage];
                [p sendPingMessageWithPongHandler:^(BOOL success) {
                    if (! success) return;
                    p.synced = YES;
                    [p sendGetaddrMessage]; // request a list of other bitcoin peers

                    if (txHashes.count > 0) {
                        [p sendGetdataMessageWithTxHashes:txHashes andBlockHashes:nil];
                        [p sendPingMessageWithPongHandler:^(BOOL success) {
                            if (success) [self removeUnrelayedTransactions];
                        }];
                    }
                    else [self removeUnrelayedTransactions];
                }];
            }
        }
    }

    self.syncStartHeight = 0;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
    });
}

// unconfirmed transactions that aren't in the mempools of any of connected peers have likely dropped off the network
- (void)removeUnrelayedTransactions
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    BOOL rescan = NO;

    // don't remove transactions until we're connected to PEER_MAX_CONNECTION peers
    if (self.connectedPeers.count < PEER_MAX_CONNECTIONS) return;
    
    for (BRPeer *p in self.connectedPeers) { // don't remove tx until all peers have finished relaying their mempools
        if (! p.synced) return;
    }

    for (BRTransaction *tx in m.wallet.recentTransactions) {
        if (tx.blockHeight != TX_UNCONFIRMED) break;

        if ([self.txRelays[tx.txHash] count] == 0) {
            // if this is for a transaction we sent, and inputs were all confirmed, and it wasn't already known to be
            // invalid, then recommend a rescan
            if (! rescan && [m.wallet amountSentByTransaction:tx] > 0 && [m.wallet transactionIsValid:tx]) {
                rescan = YES;
                
                for (NSData *hash in tx.inputHashes) {
                    if ([[m.wallet transactionForHash:hash] blockHeight] != TX_UNCONFIRMED) continue;
                    rescan = NO;
                    break;
                }
            }
            
            [m.wallet removeTransaction:tx.txHash];
        }
        else if ([self.txRelays[tx.txHash] count] < PEER_MAX_CONNECTIONS) { // set timestamp 0 to mark as unverified
            [m.wallet setBlockHeight:TX_UNCONFIRMED andTimestamp:0 forTxHashes:@[tx.txHash]];
        }
    }
    
    if (rescan) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"transaction rejected", nil)
              message:NSLocalizedString(@"Your wallet may be out of sync.\n"
                                        "This can often be fixed by rescanning the blockchain.", nil) delegate:self
              cancelButtonTitle:NSLocalizedString(@"cancel", nil)
              otherButtonTitles:NSLocalizedString(@"rescan", nil), nil] show];
        });
    }
}

- (void)updateFilter
{
    if (self.downloadPeer.needsFilterUpdate) return;
    self.downloadPeer.needsFilterUpdate = YES;
    NSLog(@"filter update needed, waiting for pong");
    
    [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so we include already sent tx
        if (! success) return;
        if (! _bloomFilter) NSLog(@"updating filter with newly created wallet addresses");
        _bloomFilter = nil;

        if (self.lastBlockHeight < self.downloadPeer.lastblock) { // if we're syncing, only update download peer
            [self.downloadPeer sendFilterloadMessage:self.bloomFilter.data];
            [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so filter is loaded
                if (! success) return;
                self.downloadPeer.needsFilterUpdate = NO;
                [self.downloadPeer rerequestBlocksFrom:self.lastBlock.blockHash];
                [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) {
                    if (! success || self.downloadPeer.needsFilterUpdate) return;
                    [self.downloadPeer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
                }];
            }];
        }
        else {
            for (BRPeer *p in self.connectedPeers) {
                [p sendFilterloadMessage:self.bloomFilter.data];
                [p sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so we know filter is loaded
                    if (! success) return;
                    p.needsFilterUpdate = NO;
                    [p sendMempoolMessage];
                }];
            }
        }
    }];
}

- (void)peerMisbehavin:(BRPeer *)peer
{
    peer.misbehavin++;
    [self.peers removeObject:peer];
    [self.misbehavinPeers addObject:peer];

    if (++self.misbehavinCount >= 10) { // clear out stored peers so we get a fresh list from DNS for next connect
        self.misbehavinCount = 0;
        [self.misbehavinPeers removeAllObjects];
        [BRPeerEntity deleteObjects:[BRPeerEntity allObjects]];
        _peers = nil;
    }
    
    [peer disconnect];
    [self connect];
}

- (void)sortPeers
{
    [_peers sortUsingComparator:^NSComparisonResult(BRPeer *p1, BRPeer *p2) {
        if (p1.timestamp > p2.timestamp) return NSOrderedAscending;
        if (p1.timestamp < p2.timestamp) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (void)savePeers
{
    NSMutableSet *peers = [[self.peers.set setByAddingObjectsFromSet:self.misbehavinPeers] mutableCopy];
    NSMutableSet *addrs = [NSMutableSet set];

    for (BRPeer *p in peers) [addrs addObject:@((int32_t)p.address)];

    [[BRPeerEntity context] performBlock:^{
        [BRPeerEntity deleteObjects:[BRPeerEntity objectsMatching:@"! (address in %@)", addrs]]; // remove deleted peers

        for (BRPeerEntity *e in [BRPeerEntity objectsMatching:@"address in %@", addrs]) { // update existing peers
            BRPeer *p = [peers member:[e peer]];

            if (p) {
                e.timestamp = p.timestamp;
                e.services = p.services;
                e.misbehavin = p.misbehavin;
                [peers removeObject:p];
            }
            else [e deleteObject];
        }

        for (BRPeer *p in peers) [[BRPeerEntity managedObject] setAttributesFromPeer:p]; // add new peers
    }];
}

- (void)saveBlocks
{
    NSMutableDictionary *blocks = [NSMutableDictionary dictionary];
    BRMerkleBlock *b = self.lastBlock;

    while (b) {
        blocks[b.blockHash] = b;
        b = self.blocks[b.prevBlock];
    }

    [[BRMerkleBlockEntity context] performBlock:^{
        [BRMerkleBlockEntity deleteObjects:[BRMerkleBlockEntity objectsMatching:@"! (blockHash in %@)",
                                            blocks.allKeys]];

        for (BRMerkleBlockEntity *e in [BRMerkleBlockEntity objectsMatching:@"blockHash in %@", blocks.allKeys]) {
            [e setAttributesFromBlock:blocks[e.blockHash]];
            [blocks removeObjectForKey:e.blockHash];
        }

        for (BRMerkleBlock *b in blocks.allValues) {
            [[BRMerkleBlockEntity managedObject] setAttributesFromBlock:b];
        }
    }];
}

#pragma mark - BRPeerDelegate

- (void)peerConnected:(BRPeer *)peer
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (peer.timestamp > now + 2*60*60 || peer.timestamp < now - 2*60*60) peer.timestamp = now; //timestamp sanity check
    self.connectFailures = 0;
    NSLog(@"%@:%d connected with lastblock %d", peer.host, peer.port, peer.lastblock);
    
    // drop peers that don't carry full blocks, or aren't synced yet
    if (! (peer.services & SERVICES_NODE_NETWORK) || peer.lastblock + 10 < self.lastBlockHeight) {
        [peer disconnect];
        return;
    }

    if (self.connected && (self.downloadPeer.lastblock >= peer.lastblock || self.lastBlockHeight >= peer.lastblock)) {
        if (self.lastBlockHeight < self.downloadPeer.lastblock) return; // don't load bloom filter yet if we're syncing
        [peer sendFilterloadMessage:self.bloomFilter.data];
        [peer sendInvMessageWithTxHashes:self.publishedTx.allKeys]; // publish unconfirmed tx
        [peer sendMempoolMessage];
        [peer sendPingMessageWithPongHandler:^(BOOL success) {
            if (! success) return;
            peer.synced = YES;
            [peer sendGetaddrMessage]; // request a list of other bitcoin peers
            [self removeUnrelayedTransactions];
        }];

        return; // we're already connected to a download peer
    }

    // select the peer with the lowest ping time to download the chain from if we're behind
    // BUG: XXX a malicious peer can report a higher lastblock to make us select them as the download peer, if two
    // peers agree on lastblock, use one of them instead
    for (BRPeer *p in self.connectedPeers) {
        if ((p.pingTime < peer.pingTime && p.lastblock >= peer.lastblock) || p.lastblock > peer.lastblock) peer = p;
    }

    [self.downloadPeer disconnect];
    self.downloadPeer = peer;
    _connected = YES;
    _bloomFilter = nil; // make sure the bloom filter is updated with any newly generated addresses
    [peer sendFilterloadMessage:self.bloomFilter.data];
    peer.currentBlockHeight = self.lastBlockHeight;
    
    NSArray *txHashes = self.publishedCallback.allKeys;
    
    if (txHashes.count > 0) { // publish pending transactions
        [peer sendInvMessageWithTxHashes:txHashes];
        [peer sendPingMessageWithPongHandler:^(BOOL success) {
            if (success) [peer sendGetdataMessageWithTxHashes:txHashes andBlockHashes:nil];
        }];
    }
    
    if (self.lastBlockHeight < peer.lastblock) { // start blockchain sync
        self.lastRelayTime = 0;

        dispatch_async(dispatch_get_main_queue(), ^{ // setup a timer to detect if the sync stalls
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
            [self performSelector:@selector(syncTimeout) withObject:nil afterDelay:PROTOCOL_TIMEOUT];

            dispatch_async(self.q, ^{
                // request just block headers up to a week before earliestKeyTime, and then merkleblocks after that
                // BUG: XXX headers can timeout on slow connections (each message is over 160k)
                // 604800 is one week in seconds WEEK_TIME_INTERVAL
                if (self.lastBlock.timestamp + WEEK_TIME_INTERVAL >= self.earliestKeyTime + NSTimeIntervalSince1970) {
                    [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
                }
                else [peer sendGetheadersMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
            });
        });
    }
    else { // we're already synced
        [self syncStopped];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerSyncFinishedNotification
             object:nil];
        });
    }
}

- (void)peer:(BRPeer *)peer disconnectedWithError:(NSError *)error
{
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, (error ? @", " : @""), (error ? error : @""));
    
    if ([error.domain isEqual:@"DashWallet"] && error.code != DASH_TIMEOUT_CODE) {
        [self peerMisbehavin:peer]; // if it's protocol error other than timeout, the peer isn't following the rules
    }
    else if (error) { // timeout or some non-protocol related network error
        [self.peers removeObject:peer];
        self.connectFailures++;
    }

    for (NSData *txHash in self.txRelays.allKeys) {
        [self.txRelays[txHash] removeObject:peer];
    }

    if ([self.downloadPeer isEqual:peer]) { // download peer disconnected
        _connected = NO;
        self.downloadPeer = nil;
        if (self.connectFailures > MAX_CONNECT_FAILURES) self.connectFailures = MAX_CONNECT_FAILURES;
    }

    if (! self.connected && self.connectFailures == MAX_CONNECT_FAILURES) {
        [self syncStopped];
        
        // clear out stored peers so we get a fresh list from DNS on next connect attempt
        [self.misbehavinPeers removeAllObjects];
        [BRPeerEntity deleteObjects:[BRPeerEntity allObjects]];
        _peers = nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerSyncFailedNotification
             object:nil userInfo:(error) ? @{@"error":error} : nil];
        });
    }
    else if (self.connectFailures < MAX_CONNECT_FAILURES && (self.taskId != UIBackgroundTaskInvalid ||
             [[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground)) {
        [self connect]; // try connecting to another peer
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerTxStatusNotification object:nil];
    });
}

- (void)peer:(BRPeer *)peer relayedPeers:(NSArray *)peers
{
    NSLog(@"%@:%d relayed %d peer(s)", peer.host, peer.port, (int)peers.count);
    [self.peers addObjectsFromArray:peers];
    [self.peers minusSet:self.misbehavinPeers];
    [self sortPeers];

    // limit total to 2500 peers
    if (self.peers.count > 2500) [self.peers removeObjectsInRange:NSMakeRange(2500, self.peers.count - 2500)];

    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate] - 3*60*60;

    // remove peers more than 3 hours old, or until there are only 1000 left
    while (self.peers.count > 1000 && [(BRPeer *)self.peers.lastObject timestamp] < t) {
        [self.peers removeObject:self.peers.lastObject];
    }

    if (peers.count > 1 && peers.count < 1000) [self savePeers]; // peer relaying is complete when we receive <1000
}

- (void)peer:(BRPeer *)peer relayedTransaction:(BRTransaction *)transaction
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    NSData *txHash = transaction.txHash;
    void (^callback)(NSError *error) = self.publishedCallback[txHash];

    NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, txHash);

    transaction.timestamp = [NSDate timeIntervalSinceReferenceDate];
    if (! [m.wallet registerTransaction:transaction]) return;
    if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
    self.publishedTx[txHash] = transaction;
        
    // keep track of how many peers have or relay a tx, this indicates how likely the tx is to confirm
    if (callback || ! [self.txRelays[txHash] containsObject:peer]) {
        if (! self.txRelays[txHash]) self.txRelays[txHash] = [NSMutableSet set];
        [self.txRelays[txHash] addObject:peer];
        if (callback) [self.publishedCallback removeObjectForKey:txHash];

        if ([self.txRelays[txHash] count] >= PEER_MAX_CONNECTIONS &&
            [[m.wallet transactionForHash:txHash] blockHeight] == TX_UNCONFIRMED) { // set timestamp when tx is verified
            [m.wallet setBlockHeight:TX_UNCONFIRMED andTimestamp:[NSDate timeIntervalSinceReferenceDate]
             forTxHashes:@[txHash]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerTxStatusNotification object:nil];
            if (callback) callback(nil);
        });
    }
    
    if (! _bloomFilter) return; // bloom filter is aready being updated

    // the transaction likely consumed one or more wallet addresses, so check that at least the next <gap limit>
    // unused addresses are still matched by the bloom filter
    NSArray *external = [m.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO],
            *internal = [m.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];
        
    for (NSString *address in [external arrayByAddingObjectsFromArray:internal]) {
        NSData *hash = address.addressToHash160;

        if (! hash || [_bloomFilter containsData:hash]) continue;
        _bloomFilter = nil; // reset bloom filter so it's recreated with new wallet addresses
        [self updateFilter];
        break;
    }
}

- (void)peer:(BRPeer *)peer hasTransaction:(NSData *)txHash
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    BRTransaction *tx = self.publishedTx[txHash];
    void (^callback)(NSError *error) = self.publishedCallback[txHash];
    
    NSLog(@"%@:%d has transaction %@", peer.host, peer.port, txHash);
    if ((! tx || ! [m.wallet registerTransaction:tx]) && ! [m.wallet.txHashes containsObject:txHash]) return;
    if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
        
    // keep track of how many peers have or relay a tx, this indicates how likely the tx is to confirm
    if (callback || ! [self.txRelays[txHash] containsObject:peer]) {
        if (! self.txRelays[txHash]) self.txRelays[txHash] = [NSMutableSet set];
        [self.txRelays[txHash] addObject:peer];
        if (callback) [self.publishedCallback removeObjectForKey:txHash];

        if ([self.txRelays[txHash] count] >= PEER_MAX_CONNECTIONS &&
            [[m.wallet transactionForHash:txHash] blockHeight] == TX_UNCONFIRMED) { // set timestamp when tx is verified
            [m.wallet setBlockHeight:TX_UNCONFIRMED andTimestamp:[NSDate timeIntervalSinceReferenceDate]
             forTxHashes:@[txHash]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerTxStatusNotification object:nil];
            if (callback) callback(nil);
        });
    }
}

- (void)peer:(BRPeer *)peer rejectedTransaction:(NSData *)txHash withCode:(uint8_t)code
{
    BRWalletManager *m = [BRWalletManager sharedInstance];
    
    if ([self.txRelays[txHash] containsObject:peer]) {
        [self.txRelays[txHash] removeObject:peer];

        if ([[m.wallet transactionForHash:txHash] blockHeight] == TX_UNCONFIRMED) { // set timestamp to 0 for unverified
            [m.wallet setBlockHeight:TX_UNCONFIRMED andTimestamp:0 forTxHashes:@[txHash]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerTxStatusNotification object:nil];
        });
    }
}

- (void)peer:(BRPeer *)peer relayedBlock:(BRMerkleBlock *)block
{
    // ignore block headers that are newer than one week before earliestKeyTime (headers have 0 totalTransactions)
    if (block.totalTransactions == 0 &&
        block.timestamp + WEEK_TIME_INTERVAL > self.earliestKeyTime + NSTimeIntervalSince1970 + 2*60*60) return;

    // track the observed bloom filter false positive rate using a low pass filter to smooth out variance
    if (peer == self.downloadPeer && block.totalTransactions > 0) {
        NSMutableSet *fp = [NSMutableSet setWithArray:block.txHashes];
    
        // 1% low pass filter, also weights each block by total transactions, using 600 tx per block as typical
        [fp minusSet:[[[BRWalletManager sharedInstance] wallet] txHashes]];
        self.fpRate = self.fpRate*(1.0 - 0.01*block.totalTransactions/600) + 0.01*fp.count/600;

        // false positive rate sanity check
        if (self.downloadPeer.status == BRPeerStatusConnected && self.fpRate > BLOOM_DEFAULT_FALSEPOSITIVE_RATE*10.0) {
            NSLog(@"%@:%d bloom filter false positive rate %f too high after %d blocks, disconnecting...", peer.host,
                  peer.port, self.fpRate, self.lastBlockHeight + 1 - self.filterUpdateHeight);
            self.tweak = arc4random(); // new random filter tweak in case we matched satoshidice or something
            [self.downloadPeer disconnect];
        }
        else if (self.lastBlockHeight + 500 < peer.lastblock && self.fpRate > BLOOM_REDUCED_FALSEPOSITIVE_RATE*10.0) {
            [self updateFilter]; // rebuild bloom filter when it starts to degrade
        }
    }

    if (! _bloomFilter) { // ingore potentially incomplete blocks when a filter update is pending
        if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
        return;
    }

    BRMerkleBlock *prev = self.blocks[block.prevBlock];
    uint32_t transitionTime = 0, txTime = 0;

    if (! prev) { // block is an orphan
        NSLog(@"%@:%d relayed orphan block %@, height %d, previous %@, last block is %@, height %d", peer.host, peer.port,
              block.blockHash,block.height, block.prevBlock, self.lastBlock.blockHash, self.lastBlockHeight);

        // ignore orphans older than one week ago
        if (block.timestamp < [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 - WEEK_TIME_INTERVAL) return;

        // call getblocks, unless we already did with the previous block, or we're still downloading the chain
        if (self.lastBlockHeight >= peer.lastblock && ! [self.lastOrphan.blockHash isEqual:block.prevBlock]) {
            NSLog(@"%@:%d calling getblocks", peer.host, peer.port);
            [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
        }

        self.orphans[block.prevBlock] = block; // orphans are indexed by previous block rather than their own hash
        self.lastOrphan = block;
        return;
    }

    block.height = prev.height + 1;
    txTime = (block.timestamp + prev.timestamp)/2;
    
    if ((block.height % 1000) == 0) { //free up some memory from time to time
        
        BRMerkleBlock *b = block;
        
        for (uint32_t i = 0; b && i < (DGW_PAST_BLOCKS_MAX + 50); i++) {
            b = self.blocks[b.prevBlock];
        }
        
        while (b) { // free up some memory
            b = self.blocks[b.prevBlock];
            if (b) [self.blocks removeObjectForKey:b.blockHash];
        }
    }
    
    // verify block difficulty if block is past last checkpoint
    if ((block.height > (checkpoint_array[CHECKPOINT_COUNT - 1].height + DGW_PAST_BLOCKS_MAX)) &&
        ![block verifyDifficultyWithPreviousBlocks:self.blocks]) {
        NSLog(@"%@:%d relayed block with invalid difficulty height %d target %x, blockHash: %@", peer.host, peer.port,
              block.height,block.target, block.blockHash);
        [self peerMisbehavin:peer];
        return;
    }

    // verify block chain checkpoints
    if (self.checkpoints[@(block.height)] && ! [block.blockHash isEqual:self.checkpoints[@(block.height)]]) {
        NSLog(@"%@:%d relayed a block that differs from the checkpoint at height %d, blockHash: %@, expected: %@",
              peer.host, peer.port, block.height, block.blockHash, self.checkpoints[@(block.height)]);
        [self peerMisbehavin:peer];
        return;
    }

    if ([block.prevBlock isEqual:self.lastBlock.blockHash]) { // new block extends main chain
//        if ((block.height % 500) == 0 || block.txHashes.count > 0 || block.height > peer.lastblock) {
//            NSLog(@"adding block at height: %d, false positive rate: %f", block.height, self.fpRate);
//        }
        //NSLog(@"adding block at height: %d, %@", block.height, block.blockHash);
        self.blocks[block.blockHash] = block;
        self.lastBlock = block;
        [self setBlockHeight:block.height andTimestamp:txTime - NSTimeIntervalSince1970 forTxHashes:block.txHashes];
        if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
        self.downloadPeer.currentBlockHeight = block.height;

        // track moving average transactions per block using a 1% low pass filter
        if (block.totalTransactions > 0) _averageTxPerBlock = _averageTxPerBlock*0.99 + block.totalTransactions*0.01;
    }
    else if (self.blocks[block.blockHash] != nil) { // we already have the block (or at least the header)
        if ((block.height % 500) == 0 || block.txHashes.count > 0 || block.height > peer.lastblock) {
            NSLog(@"%@:%d relayed existing block at height %d", peer.host, peer.port, block.height);
        }
//NSLog(@"2 adding block at height: %d, false positive rate: %f", block.height, self.fpRate);
        self.blocks[block.blockHash] = block;

        BRMerkleBlock *b = self.lastBlock;

        while (b && b.height > block.height) b = self.blocks[b.prevBlock]; // check if block is in main chain

        if ([b.blockHash isEqual:block.blockHash]) { // if it's not on a fork, set block heights for its transactions
            [self setBlockHeight:block.height andTimestamp:txTime - NSTimeIntervalSince1970 forTxHashes:block.txHashes];
            if (block.height == self.lastBlockHeight) self.lastBlock = block;
        }
    }
    else { // new block is on a fork
        if (block.height <= checkpoint_array[CHECKPOINT_COUNT - 1].height) { // fork is older than last checkpoint
            NSLog(@"ignoring block on fork older than most recent checkpoint, fork height: %d, blockHash: %@",
                  block.height, block.blockHash);
            return;
        }

        // special case, if a new block is mined while we're rescanning the chain, mark as orphan til we're caught up
        if (self.lastBlockHeight < peer.lastblock && block.height > self.lastBlockHeight + 1) {
            NSLog(@"marking new block at height %d as orphan until rescan completes", block.height);
            self.orphans[block.prevBlock] = block;
            self.lastOrphan = block;
            return;
        }

        NSLog(@"chain fork to height %d", block.height);
        self.blocks[block.blockHash] = block;
        if (block.height <= self.lastBlockHeight) return; // if fork is shorter than main chain, ingore it for now

        NSMutableArray *txHashes = [NSMutableArray array];
        BRMerkleBlock *b = block, *b2 = self.lastBlock;

        while (b && b2 && ! [b.blockHash isEqual:b2.blockHash]) { // walk back to where the fork joins the main chain
            b = self.blocks[b.prevBlock];
            if (b.height < b2.height) b2 = self.blocks[b2.prevBlock];
        }

        NSLog(@"reorganizing chain from height %d, new height is %d", b.height, block.height);

        // mark transactions after the join point as unconfirmed
        for (BRTransaction *tx in [[[BRWalletManager sharedInstance] wallet] recentTransactions]) {
            if (tx.blockHeight <= b.height) break;
            [txHashes addObject:tx.txHash];
        }

        [self setBlockHeight:TX_UNCONFIRMED andTimestamp:0 forTxHashes:txHashes];
        b = block;

        while (b.height > b2.height) { // set transaction heights for new main chain
            [self setBlockHeight:b.height andTimestamp:txTime - NSTimeIntervalSince1970 forTxHashes:b.txHashes];
            b = self.blocks[b.prevBlock];
            txTime = b.timestamp/2 + [(BRMerkleBlock *)self.blocks[b.prevBlock] timestamp]/2;
        }

        self.lastBlock = block;
    }
    
    if (block.height == peer.lastblock && block == self.lastBlock) { // chain download is complete
        [self saveBlocks];
        [BRMerkleBlockEntity saveContext];
        [self syncStopped];
        [[BRWalletManager sharedInstance] setAverageBlockSize:self.averageTxPerBlock*TX_AVERAGE_SIZE];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerSyncFinishedNotification
             object:nil];
        });
    }

    if (block == self.lastBlock && self.orphans[block.blockHash]) { // check if the next block was received as an orphan
        BRMerkleBlock *b = self.orphans[block.blockHash];

        [self.orphans removeObjectForKey:block.blockHash];
        [self peer:peer relayedBlock:b];
    }

    if (block.height > peer.lastblock) { // notify that transaction confirmations may have changed
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BRPeerManagerTxStatusNotification object:nil];
        });
    }
}

- (BRTransaction *)peer:(BRPeer *)peer requestedTransaction:(NSData *)txHash
{
    return self.publishedTx[txHash];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    [self rescan];
}

@end
