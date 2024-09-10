// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23;

import {OrderSide} from "../share/Enums.sol";

/// @title LibOrder contract
/// @notice This contract defines the data structure of order.
library LibOrder {
    struct Order {
        address sender;
        uint128 size; // 合约数量
        uint128 price; //价格
        uint64 nonce;
        uint8 productIndex;
        OrderSide orderSide;
    }

    struct SignedOrder {
        Order order;
        bytes signature;
        address signer;
        bool isLiquidation; // true: liquidation order, false: normal order
    }

    struct MatchOrders {
        SignedOrder maker;
        SignedOrder taker;
    }
}

// 结构体，放在单独的一个lib里面。
