// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23;

/// @title Perp Engine interface
/// @notice Manage openning positions
interface IPerp {
    // 资金费率与未平仓量
    /// @notice Stores the market metrics of a market, including the funding rate and open interest.
    struct FundingRate {
        int128 cumulativeFunding18D; // 累计资金费率（累加资金费价差），类似a(n) = S(n) - S(n-1)概念。
        int128 openInterest;
    }

    /// @notice Stores openning position of an account of a market.
    struct Balance {
        int128 size; // 合约数量
        int128 quoteBalance; // 开仓价值（金额） quotePrice = quoteBalance / size
        int128 lastFunding; // 上一次最新操作的累计资金费率价差，这个作用是？
    }

    /// @notice Information of the account to modify
    struct AccountDelta {
        uint8 productIndex;
        address account;
        int128 amount; // 合约数量
        int128 quoteAmount; // 合约金额
    }

    /// @notice Modifies the balance of an account of a market
    /// @param accountDeltas The information of the account to modify
    /// Include token address, account address, amount of product, amount of quote
    function modifyAccount(IPerp.AccountDelta[] memory accountDeltas) external;

    /// @notice Updates the funding rate of a market
    /// @param productIndex Product id
    /// @param diffPrice Difference between index price and mark price
    function updateFundingRate(uint8 productIndex, int128 diffPrice) external returns (int128);

    /// @notice Gets the balance of an account
    /// @param productIndex Product Id
    /// @param account Account address
    /// @return Balance of the account
    function getBalance(address account, uint8 productIndex) external view returns (Balance memory);

    /// @notice Gets the funding rate of a market.
    /// @param productIndex Product Id
    /// @return Funding rate of the market
    function getFundingRate(uint8 productIndex) external view returns (FundingRate memory);
}
