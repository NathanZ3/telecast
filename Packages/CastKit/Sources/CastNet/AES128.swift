import Foundation
import CommonCrypto

public enum AES128Error: Error, Equatable {
    case badKeyOrIV
    case cryptFailed(Int32)
}

/// AES-128-CBC used by HLS `METHOD=AES-128` segments.
public enum AES128 {
    public static func decryptCBC(_ data: Data, key: Data, iv: Data) throws -> Data {
        do {
            return try crypt(CCOperation(kCCDecrypt), data, key: key, iv: iv, options: CCOptions(kCCOptionPKCS7Padding))
        } catch AES128Error.cryptFailed(let status) where status == CCCryptorStatus(kCCDecodeError) {
            // Some servers do not pad: retry without PKCS7.
            return try crypt(CCOperation(kCCDecrypt), data, key: key, iv: iv, options: 0)
        }
    }

    public static func encryptCBC(_ data: Data, key: Data, iv: Data) throws -> Data {
        try crypt(CCOperation(kCCEncrypt), data, key: key, iv: iv, options: CCOptions(kCCOptionPKCS7Padding))
    }

    /// HLS default IV: the media sequence number as a 128-bit big-endian integer.
    public static func iv(forSequence sequence: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        var value = UInt64(truncatingIfNeeded: sequence)
        for index in stride(from: 15, through: 8, by: -1) {
            bytes[index] = UInt8(value & 0xFF)
            value >>= 8
        }
        return Data(bytes)
    }

    private static func crypt(_ operation: CCOperation, _ data: Data, key: Data, iv: Data, options: CCOptions) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else { throw AES128Error.badKeyOrIV }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var moved = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), options,
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inputBytes.baseAddress, data.count,
                                outputBytes.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { throw AES128Error.cryptFailed(status) }
        output.count = moved
        return output
    }
}
